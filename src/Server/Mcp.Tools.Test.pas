unit Mcp.Tools.Test;

{ delphi_test: discover and run a project's tests, with a structured result.
  See Lsp.TestRunner for what counts as a test project and why running them
  has its own switch. }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Texts,
  Lsp.Attributes;  // [RutaDelServidor]: que parametro es una ruta NUESTRA

type
  TDelphiTestParams = class
  private
    FCommand: string;
    FPath: string;
    FProject: string;
    FConfig: string;
    FFilter: string;
    FTimeoutMs: Integer;
    FNoBuild: Boolean;
    FPlatform: string;
  public
    [SchemaDescription(SP_TEST_COMMAND)]
    property Command: string read FCommand write FCommand;
    [SchemaDescription(SP_TEST_PATH)]
    [RutaDelServidor]
    property Path: string read FPath write FPath;
    [SchemaDescription(SP_TEST_PROJECT)]
    [RutaDelServidor]
    [RutaRelativa] // un NOMBRE suelto lo explica la tool (TEST-005): lo que da delphi_projects
    property Project: string read FProject write FProject;
    [SchemaDescription(SP_TEST_CONFIG)]
    [SchemaDefault('Debug')]
    property Config: string read FConfig write FConfig;
    [SchemaDescription(SP_TEST_FILTER)]
    property Filter: string read FFilter write FFilter;
    [SchemaDescription(SP_TEST_TIMEOUT)]
    property TimeoutMs: Integer read FTimeoutMs write FTimeoutMs;
    [SchemaDescription(SP_TEST_PLATFORM)]
    property Platform: string read FPlatform write FPlatform;
    [SchemaDescription(SP_TEST_NOBUILD)]
    property NoBuild: Boolean read FNoBuild write FNoBuild;
  end;

  TDelphiTestTool = class(TMCPToolBase<TDelphiTestParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiTestParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  System.JSON,
  System.StrUtils,
  MCPServer.Registration,
  Lsp.Guard,
  Lsp.TestRunner,
  Lsp.Settings;

constructor TDelphiTestTool.Create;
begin
  inherited;
  FName := 'delphi_test';
  FDescription := SD_TEST;
end;

function TDelphiTestTool.ExecuteWithParams(const Params: TDelphiTestParams): string;
var
  Cmd: string;
  Ret: TJSONObject;
begin
  // el comando efectivo: LA regla vive en Lsp.Guard.ComandoDeTest, la misma
  // que aplica la puerta de solo lectura (undecima revision)
  Cmd := ComandoDeTest(Params.Command, Params.Project, Params.Path);
  if not MatchText(Cmd, ['discover', 'run']) then
    Exit(MsgText(SR_TEST_CMD));
  // lo que no es del comando se dice (Lsp.Guard.ParametroQueNoVa): discover
  // con filter o config los ignoraba en silencio (decima revision)
  var Suyos: string;
  var Sobra := ParametroQueNoVa(Cmd, [
      'discover', 'path',
      'run', 'project config filter platform timeoutms nobuild'],
    ['path', Params.Path, '', 'project', Params.Project, '',
     'config', Params.Config, 'Debug', 'filter', Params.Filter, '',
     'platform', Params.Platform, 'Win64',
     'timeoutms', IfThen(Params.TimeoutMs <> 0, IntToStr(Params.TimeoutMs)), '',
     'nobuild', IfThen(Params.NoBuild, 'true'), ''], Suyos);
  if Sobra <> '' then
    Exit(MsgFmt(SR_TEST_NO_VA_CON_COMANDO_FMT, [Sobra, Cmd, Cmd, Suyos]));
  try
    if Cmd = 'discover' then
    begin
      if Params.Path.Trim = '' then
        Exit(MsgText(SR_TEST_NEED_PATH));
      Ret := TestDiscover(Params.Path.Trim);
    end
    else
    begin
      // running tests IS execution: its own opt-in, the only one this machine
      // has (delphi_run retired 2026-09-23).
      if not AllowTests then
        Exit(MsgText(SR_TEST_DISABLED));
      if Params.Project.Trim = '' then
        Exit(MsgText(SR_TEST_NEED_PROJECT));
      Ret := TestRun(Params.Project.Trim, Params.Config.Trim,
        Params.Filter.Trim, Params.Platform.Trim, Params.TimeoutMs,
        Params.NoBuild);
    end;
    try
      Result := Ret.ToJSON;
    finally
      Ret.Free;
    end;
  except
    on E: Exception do
      Result := MsgExcepcion(E.ClassName, E.Message);
  end;
  // (lo enmascara el filtro de salida, Lsp.Host; una segunda pasada con el
  // nombre de la tool gastaba lo que la llamada dejo anotado)
end;

initialization
  TMCPRegistry.RegisterTool('delphi_test',
    function: IMCPTool begin Result := TDelphiTestTool.Create; end);

end.
