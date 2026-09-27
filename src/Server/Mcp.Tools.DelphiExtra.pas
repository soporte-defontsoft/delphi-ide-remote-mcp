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
  Lsp.Session,
  Lsp.Texts, // los textos de los parametros viven ahi, y son de interface
  Lsp.Attributes;  // [RutaDelServidor]: que parametro es una ruta NUESTRA

type
  TDelphiDiagnosticsParams = class
  private
    FPath: string;
  public
    [SchemaDescription(SP_BUILD_PATH)]
    [Required]
    [RutaDelServidor]
    property Path: string read FPath write FPath;
  end;

  TDelphiReferencesParams = class
  private
    FPath: string;
    FLine: Integer;
    FCharacter: Integer;
  public
    [SchemaDescription(SP_BUILD_PATH_2)]
    [Required]
    [RutaDelServidor]
    property Path: string read FPath write FPath;
    [SchemaDescription(SP_BUILD_LINE)]
    [Required]
    property Line: Integer read FLine write FLine;
    [SchemaDescription(SP_BUILD_CHARACTER)]
    [Required]
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
    FSdk: string;
    FVerbosity: string;
  public
    [SchemaDescription(SP_BUILD_PROJECT)]
    [Required]
    [RutaDelServidor]
    property Project: string read FProject write FProject;
    [SchemaDescription(SP_BUILD_PLATFORM)]
    [SchemaDefault('Win32')]
    property Platform: string read FPlatform write FPlatform;
    [SchemaDescription(SP_BUILD_CONFIG)]
    [SchemaDefault('Debug')]
    property Config: string read FConfig write FConfig;
    [SchemaDescription(SP_BUILD_TARGET)]
    [SchemaDefault('Build')]
    property Target: string read FTarget write FTarget;
    [SchemaDescription(SP_BUILD_PROFILE)]
    property Profile: string read FProfile write FProfile;
    [SchemaDescription(SP_BUILD_SDK)]
    property Sdk: string read FSdk write FSdk;
    [SchemaDescription(SP_BUILD_VERBOSITY)]
    [SchemaDefault('quiet')]
    property Verbosity: string read FVerbosity write FVerbosity;
    [SchemaDescription(SP_BUILD_DEVICEID)]
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
  System.StrUtils,
  System.IOUtils,
  MCPServer.Registration,
  Lsp.References,
  Lsp.Patch,      // PositionOutOfRange: la misma validacion que las otras cinco
  Lsp.BuildRunner;

const
  DIAG_WAIT_MS = 40000; // under the 60 s most MCP clients allow per call

{ TDelphiDiagnosticsTool }

constructor TDelphiDiagnosticsTool.Create;
begin
  inherited;
  FName := 'delphi_diagnostics';
  FDescription := SD_BUILD_DIAGNOSTICS;
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
  // A file the linter will never have an opinion about (a .txt, a .json) used
  // to answer "in progress, call again" forever, and the note SAID the next
  // call would bring the result. An obedient agent stayed in that loop until
  // it ran out of budget (measured 2026-08-25). It never was a Delphi source:
  // say so once.
  if not TFile.Exists(Params.Path) then
    Exit(MsgFmt(SR_PATCH_EDITS_NOFILE_FMT, [Params.Path]));
  if not MatchText(TPath.GetExtension(Params.Path),
       ['.pas', '.dpr', '.dpk', '.inc']) then
    Exit(MsgFmt(SR_DIAG_NOT_SOURCE_FMT,
      [TPath.GetFileName(Params.Path), TPath.GetExtension(Params.Path)]));
  // Answer well inside the usual MCP client timeout (60 s): a slow lint keeps
  // running on the LSP, and the next call on the same text collects it.
  P := TLspSession.Instance.LintFile(Params.Path, DIAG_WAIT_MS, Settings);
  if P = nil then
    Exit(MsgText(SF_DIAG_IN_PROGRESS));
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
          // 3 (information) y 4 (hint) de la escala LSP se cuentan juntos en
          // "hints": son los dos "ni error ni aviso". Lo que NO puede pasar
          // es que el numero llegue sin estar documentado, que es lo que
          // ocurria con el 4 (medido 2026-09-20).
          case Sev of
            1: Inc(Errors);
            2: Inc(WarningsC);
          else
            Inc(Hints);
          end;
          // La 1-based al lado del range 0-based del motor, como en
          // definition/hover/references: diagnostics era la ultima tool del
          // motor sin gemela (Hermes, 2026-09-23).
          var D := V.Clone as TJSONObject;
          var L0 := D.FindValue('range.start.line');
          if L0 <> nil then
            D.AddPair('line1', TJSONNumber.Create(L0.GetValue<Integer> + 1));
          OutArr.Add(D);
        end;
      Return.AddPair('errors', TJSONNumber.Create(Errors));
      Return.AddPair('warnings', TJSONNumber.Create(WarningsC));
      Return.AddPair('hints', TJSONNumber.Create(Hints));
      Return.AddPair('diagnostics', OutArr);
      Result := Return.ToJSON;
      if Settings = '' then
        Result := Result + MsgText(SN_BUILD_NO_PROJECT_SETTINGS);
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
  FDescription := SD_BUILD_REFERENCES;
end;

function TDelphiReferencesTool.ExecuteWithParams(
  const Params: TDelphiReferencesParams): string;
var
  R: TJSONObject;
begin
  // La misma validacion que definition, hover, signature y completion. Sin
  // ella, una linea que no existe salia como "Error executing tool: Line 9999
  // out of range" - una excepcion cruda, en ingles, y que en las reglas de
  // este servidor significa "me he roto por dentro". Era el caller el que se
  // equivoco, y el mensaje rico ya existia: solo estaba en una unidad que
  // esta no podia ver.
  Result := PositionOutOfRange(Params.Path, Params.Line, Params.Character);
  if Result <> '' then
    Exit;
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
  FDescription := SD_BUILD_BUILD;
end;

function TDelphiBuildTool.ExecuteWithParams(const Params: TDelphiBuildParams): string;
var
  R: TJSONObject;
begin
  // The engine refuses three things by POLICY (a project that would run a shell
  // during the build, a {$I}/{$R} pointing outside the jail, and an output
  // folder the session may not write or does not declare) and it does
  // it by raising. Raising means the dispatcher labels it "Error executing
  // tool", which this server's own rules define as an internal failure worth
  // reporting as a bug. A refusal is not a crash: it goes out as itself.
  try
    // quiet por defecto, como el bat de la casa: la mayoria de los builds de
    // un agente son "?sigue compilando?" y pagar los warnings enteros en cada
    // uno se lo come el contexto.
    R := RunMsBuild(Params.Project, Params.Platform, Params.Config, Params.Target,
      Params.Profile, Params.DeviceId, 600000, Params.Sdk,
      IfThen(Params.Verbosity.Trim = '', 'quiet', Params.Verbosity.Trim.ToLower));
  except
    on E: Exception do
      // "error:" tambien, no solo "RECHAZADO": desde v1.0.4-beta el motor
      // rechaza con ese prefijo lo que no es un proyecto (regla 11: corrige
      // y repite), y ese mensaje se estaba re-lanzando y saliendo disfrazado
      // de averia interna - justo lo que este try/except existe para evitar.
      if EsRechazo(E.Message) then
        Exit(E.Message)
      else
        raise;
  end;
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
