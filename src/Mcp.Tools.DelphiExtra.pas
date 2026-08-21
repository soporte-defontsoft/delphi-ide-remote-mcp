unit Mcp.Tools.DelphiExtra;

{ Value tools: delphi_diagnostics (Error Insight on demand via LSP linter
  mode), delphi_references (hybrid text-scan + definition validation) and
  delphi_build (real MSBuild on the machine that owns the compiler). }

interface

uses
  System.SysUtils,
  System.JSON,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Client,
  Lsp.Session;

type
  TDelphiDiagnosticsParams = class
  private
    FPath: string;
  public
    [SchemaDescription('Absolute path of the Delphi source file to lint (.pas/.dpr)')]
    property Path: string read FPath write FPath;
  end;

  TDelphiReferencesParams = class
  private
    FPath: string;
    FLine: Integer;
    FCharacter: Integer;
  public
    [SchemaDescription('Absolute path of the Delphi source file')]
    property Path: string read FPath write FPath;
    [SchemaDescription('Zero-based line of the identifier to find references for')]
    property Line: Integer read FLine write FLine;
    [SchemaDescription('Zero-based character inside the identifier')]
    property Character: Integer read FCharacter write FCharacter;
  end;

  TDelphiBuildParams = class
  private
    FProject: string;
    FPlatform: string;
    FConfig: string;
    FTarget: string;
    FProfile: string;
    FDeviceId: string;
  public
    [SchemaDescription('Absolute path of the .dproj to build')]
    property Project: string read FProject write FProject;
    [SchemaDescription('Target platform (default Win32): Win32/Win64 build natively here; Linux64/OSX64/OSXARM64/Android64/iOSDevice64... need the platform enabled in the project (delphi_config) and a PAServer profile (delphi_paserver)')]
    property Platform: string read FPlatform write FPlatform;
    [SchemaDescription('Debug or Release (default Debug)')]
    property Config: string read FConfig write FConfig;
    [SchemaDescription('Build (full, default), Make (incremental), Clean, or Deploy (always builds first, then deploys: to the PAServer of "profile" for Linux/macOS, or packages the app for Android). After switching platforms use Build')]
    property Target: string read FTarget write FTarget;
    [SchemaDescription('Connection profile name for target=Deploy on a PAServer platform (see delphi_paserver command=profiles). The deployed files land on the target under its PAServer scratch dir, in <profile>/<project name>/')]
    property Profile: string read FProfile write FProfile;
    [SchemaDescription('Android device serial for target=Deploy on Android platforms (see delphi_adb command=devices; attach one over wifi with command=connect)')]
    property DeviceId: string read FDeviceId write FDeviceId;
  end;

  TDelphiDiagnosticsTool = class(TMCPToolBase<TDelphiDiagnosticsParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiDiagnosticsParams): string; override;
  public
    constructor Create; override;
  end;

  TDelphiReferencesTool = class(TMCPToolBase<TDelphiReferencesParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiReferencesParams): string; override;
  public
    constructor Create; override;
  end;

  TDelphiBuildTool = class(TMCPToolBase<TDelphiBuildParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiBuildParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  MCPServer.Registration,
  Lsp.References,
  Lsp.BuildRunner;

{ TDelphiDiagnosticsTool }

constructor TDelphiDiagnosticsTool.Create;
begin
  inherited;
  FName := 'delphi_diagnostics';
  FDescription := 'Compiler-grade errors/warnings/hints for one Delphi source ' +
    'file (Error Insight via the official DelphiLSP linter), WITHOUT building. ' +
    'Real compiler codes (E2003, W1000, H2164...) with exact 0-based positions. ' +
    'Severity: 1=error, 2=warning, 3=hint. Lints the CURRENT on-disk content.';
end;

function TDelphiDiagnosticsTool.ExecuteWithParams(
  const Params: TDelphiDiagnosticsParams): string;
var
  Settings: string;
  P, Return: TJSONObject;
  Diags, OutArr: TJSONArray;
  V: TJSONValue;
  Errors, WarningsC, Hints: Integer;
  Sev: Integer;
begin
  P := TLspSession.Instance.LintFile(Params.Path, 120000, Settings);
  if P = nil then
    Exit('timeout: no diagnostics arrived within 120 s' +
      ' [hint: very large units take a while on first lint; retry once]');
  try
    Diags := P.GetValue('diagnostics') as TJSONArray;
    Return := TJSONObject.Create;
    try
      Errors := 0;
      WarningsC := 0;
      Hints := 0;
      OutArr := TJSONArray.Create;
      if Diags <> nil then
        for V in Diags do
        begin
          Sev := (V as TJSONObject).GetValue<Integer>('severity');
          case Sev of
            1: Inc(Errors);
            2: Inc(WarningsC);
          else
            Inc(Hints);
          end;
          OutArr.Add(V.Clone as TJSONObject);
        end;
      Return.AddPair('errors', TJSONNumber.Create(Errors));
      Return.AddPair('warnings', TJSONNumber.Create(WarningsC));
      Return.AddPair('hints', TJSONNumber.Create(Hints));
      Return.AddPair('diagnostics', OutArr);
      Result := Return.ToJSON;
      if Settings = '' then
        Result := Result + ' [warning: no project settings found - results may be incomplete]';
    finally
      Return.Free;
    end;
  finally
    P.Free;
  end;
end;

{ TDelphiReferencesTool }

constructor TDelphiReferencesTool.Create;
begin
  inherited;
  FName := 'delphi_references';
  FDescription := 'Find references to the identifier at a 0-based ' +
    'line:character position. Hybrid method (DelphiLSP has no native ' +
    'references): project-wide text scan, then every candidate is validated ' +
    'by asking the compiler engine for its definition - only candidates ' +
    'resolving to the SAME symbol are confirmed, homonyms are rejected. ' +
    'Bounded work: leftovers are listed as unverified, never silently dropped.';
end;

function TDelphiReferencesTool.ExecuteWithParams(
  const Params: TDelphiReferencesParams): string;
var
  R: TJSONObject;
begin
  R := FindDelphiReferences(Params.Path, Params.Line, Params.Character);
  try
    Result := R.ToJSON;
  finally
    R.Free;
  end;
end;

{ TDelphiBuildTool }

constructor TDelphiBuildTool.Create;
begin
  inherited;
  FName := 'delphi_build';
  FDescription := 'Build a Delphi project for real with MSBuild on this ' +
    'machine (rsvars located via registry). Returns success flag, compiler ' +
    'errors/warnings and the output tail. Use this as the closing ' +
    'verification after editing - the linter does not link nor produce ' +
    'binaries. Compile-only: a project that would EXECUTE a shell during build ' +
    '(a custom <Target>/<Exec>, a build-event, a foreign <Import>) is refused ' +
    'unless the operator set [Security] AllowRun=1.';
end;

function TDelphiBuildTool.ExecuteWithParams(const Params: TDelphiBuildParams): string;
var
  R: TJSONObject;
begin
  R := RunMsBuild(Params.Project, Params.Platform, Params.Config, Params.Target,
    Params.Profile, Params.DeviceId);
  try
    Result := R.ToJSON;
  finally
    R.Free;
  end;
end;

initialization
  TMCPRegistry.RegisterTool('delphi_diagnostics',
    function: IMCPTool begin Result := TDelphiDiagnosticsTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_references',
    function: IMCPTool begin Result := TDelphiReferencesTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_build',
    function: IMCPTool begin Result := TDelphiBuildTool.Create; end);

end.
