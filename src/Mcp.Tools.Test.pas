unit Mcp.Tools.Test;

{ delphi_test: discover and run a project's tests, with a structured result.
  See Lsp.TestRunner for what counts as a test project and why running them
  has its own switch. }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Texts;

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
  public
    [SchemaDescription(SP_TEST_COMMAND)]
    property Command: string read FCommand write FCommand;
    [SchemaDescription(SP_TEST_PATH)]
    property Path: string read FPath write FPath;
    [SchemaDescription(SP_TEST_PROJECT)]
    property Project: string read FProject write FProject;
    [SchemaDescription(SP_TEST_CONFIG)]
    property Config: string read FConfig write FConfig;
    [SchemaDescription(SP_TEST_FILTER)]
    property Filter: string read FFilter write FFilter;
    [SchemaDescription(SP_TEST_TIMEOUT)]
    property TimeoutMs: Integer read FTimeoutMs write FTimeoutMs;
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
  Lsp.TestRunner;

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
  Cmd := Params.Command.Trim.ToLower;
  if Cmd = '' then
    Cmd := 'discover';
  if not MatchText(Cmd, ['discover', 'run']) then
    Exit(SR_TEST_CMD);
  try
    if Cmd = 'discover' then
    begin
      if Params.Path.Trim = '' then
        Exit(SR_TEST_NEED_PATH);
      Ret := TestDiscover(Params.Path.Trim);
    end
    else
    begin
      // running tests IS execution: its own opt-in, and AllowRun (full
      // execution) implies it.
      if not (AllowTests or AllowRun) then
        Exit(SR_TEST_DISABLED);
      if Params.Project.Trim = '' then
        Exit(SR_TEST_NEED_PROJECT);
      Ret := TestRun(Params.Project.Trim, Params.Config.Trim,
        Params.Filter.Trim, Params.TimeoutMs, Params.NoBuild);
    end;
    try
      Result := Ret.ToJSON;
    finally
      Ret.Free;
    end;
  except
    on E: Exception do
      Result := 'error: ' + E.Message;
  end;
  Result := MaskDriveText('delphi_test', Result);
end;

initialization
  TMCPRegistry.RegisterTool('delphi_test',
    function: IMCPTool begin Result := TDelphiTestTool.Create; end);

end.
