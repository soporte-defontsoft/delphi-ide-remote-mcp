unit Mcp.Tools.Help;

// delphi_help: the map an agent arriving cold does not have.
//
// Measured 2026-08-25, in an agent's own words after doing a real job through
// nothing but this server: "no hay forma de preguntarle al servidor como se
// usa". Forty tools is a lot of surface; tools/list answers with every schema
// at once (about 14k tokens) and answers the question "what exists", not the
// question an agent actually has, which is "what do I use for THIS, and what
// are the house rules". Both of those cost calls, and calls cost context.
//
// Three commands, all read-only and all cheap:
//   tasks       (default) task -> tool, one line each
//   tool        one tool: its full description and its parameters
//   conventions the rules that are the same for every tool (paths, the jail,
//               anchored editing, backups, encodings)
//
// Deliberately NOT a duplicate of tools/list: this is the shortcut, not the
// catalogue. Whatever a tool's own description says is authoritative; this
// only points at it.

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Texts;

type
  TDelphiHelpParams = class
  private
    FCommand: string;
    FName: string;
  public
    [SchemaDescription(SP_HELP_COMMAND)]
    property Command: string read FCommand write FCommand;
    [SchemaDescription(SP_HELP_NAME)]
    property Name: string read FName write FName;
  end;

  TDelphiHelpTool = class(TMCPToolBase<TDelphiHelpParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiHelpParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  System.StrUtils,
  System.Math,
  System.JSON,
  MCPServer.Registration,
  Lsp.Guard, // ToolHiddenFromList / IsReadOnlyNow: la tabla dice lo que tools/list anuncia
  Lsp.Pascal; // EditDistance

constructor TDelphiHelpTool.Create;
begin
  inherited;
  FName := 'delphi_help';
  FDescription := SD_HELP;
end;

function OneTool(const AName: string): string; forward;

// (EditDistance, Levenshtein: vive en Lsp.Pascal desde la 1.17.0, cuando
// delphi_designer set la necesito para la propiedad casi bien escrita)

{ One tool in full: what tools/list would say about it, alone. }
function OneTool(const AName: string): string;
var
  Tool: IMCPTool;
  Ret: TJSONObject;
  Schema: TJSONObject;
  Names: TArray<string>;
  N, Close, BestName: string;
begin
  N := AName.Trim.ToLower.Replace(' ', '_').Replace('-', '_');
  if (N <> '') and not N.StartsWith('delphi_') and not N.StartsWith('vault_') then
    N := 'delphi_' + N;
  if not TMCPRegistry.HasTool(N) then
  begin
    // Say which ones DO exist rather than just "no": a wrong guess about a
    // tool name should cost one call, not three.
    Close := '';
    Names := TMCPRegistry.GetToolNames;
    for var Cand in Names do
      if (N <> '') and (Cand.Contains(N) or N.Contains(Cand)) then
        Close := Close + IfThen(Close <> '', ', ', '') + Cand;
    // Substring matching finds "buil" but not "delphi_edt", and a slip of one
    // letter on a name you almost got right is the commonest miss there is
    // (field round 10). When ONE name is closer than every other, that is
    // what was meant: answer it and say so, instead of handing back a list
    // and charging another call for the obvious.
    // EL mas parecido de la casa (Lsp.Pascal): este bucle era su copia
    // (revision de la 1.17.0)
    BestName := ElMasParecido(N, Names, 1);
    if BestName <> '' then
      Exit(MsgFmt(SN_HELP_ASSUMED_FMT, [AName.Trim, BestName]) + #10 +
        OneTool(BestName));
    if Close = '' then
      for var Cand in Names do
        if EditDistance(N, Cand) <= 2 then
          Close := Close + IfThen(Close <> '', ', ', '') + Cand;
    if Close = '' then
      Exit(MsgFmt(SR_HELP_NO_TOOL_ALL_FMT,
        [AName.Trim, string.Join(', ', Names)]));
    Exit(MsgFmt(SR_HELP_NO_TOOL_FMT, [AName.Trim, Close]));
  end;
  Tool := TMCPRegistry.CreateTool(N);
  Ret := TJSONObject.Create;
  try
    Ret.AddPair('tool', N);
    Ret.AddPair('description', Tool.Description);
    // GetInputSchema BUILDS a fresh object on every call, so the caller owns
    // it: hand it straight to the result (which frees it) instead of cloning
    // and leaking the original.
    Schema := Tool.InputSchema;
    if Assigned(Schema) then
      Ret.AddPair('parameters', Schema);
    Ret.AddPair('note', MsgText(SN_HELP_TOOL_NOTE));
    Result := Ret.ToJSON;
  finally
    Ret.Free;
  end;
end;

function TDelphiHelpTool.ExecuteWithParams(const Params: TDelphiHelpParams): string;
var
  Cmd: string;
begin
  Cmd := Params.Command.Trim.ToLower;
  if (Cmd = '') and (Params.Name.Trim <> '') then
    Cmd := 'tool'; // name given, intent obvious
  if Cmd = '' then
    Cmd := 'tasks';
  if MatchText(Cmd, ['tasks', 'task', 'index']) then
  begin
    // las filas del vault, las que tools/list anuncia a ESTE workspace: se le
    // pregunta al mismo filtro (ToolHiddenFromList), no se repite su regla -
    // repetida, no siguio a la de la credencial de solo lectura (revision del
    // 6-oct-2026)
    Result := MsgFmt(SN_HELP_TASKS, [IfThen(not ToolHiddenFromList('vault_read'),
      MsgText(SF_HELP_TASKS_VAULT_LEER) + IfThen(not ToolHiddenFromList('vault_append'),
      MsgText(SF_HELP_TASKS_VAULT_ESCRIBIR), ''), '')]);
    // y a una credencial de solo lectura, lo mismo que tools/list: las de
    // escritura no se le anuncian, y la tabla se las nombraria
    if IsReadOnlyNow then
      Result := Result + MsgText(SF_HELP_TASKS_SOLO_LECTURA);
    // y lo que falta y POR QUE, con la misma regla (MotivoToolOculta): sin
    // decirlo, un agente conto 37 tools donde la documentacion dice 42 y creyo
    // que se habian fusionado (Hermes, validacion de la 1.16.0: la VM no
    // declara vault). vault_read se pregunta aunque no este registrada: sin
    // vault en ningun workspace no se registra, y es justo cuando falta.
    case MotivoToolOculta('vault_read') of
      moSinVault: Result := Result + MsgText(SF_HELP_TASKS_SIN_VAULT);
    else
      if MotivoToolOculta('vault_append') = moVaultLectura then
        Result := Result + MsgText(SF_HELP_TASKS_VAULT_LECTURA);
    end;
    var PorPerfil := '';
    for var T in TMCPRegistry.GetToolNames do
      if MotivoToolOculta(T) = moPerfil then
        PorPerfil := PorPerfil + IfThen(PorPerfil <> '', ', ', '') + T;
    if PorPerfil <> '' then
      Result := Result + MsgFmt(SF_HELP_TASKS_PERFIL_FMT, [PorPerfil]);
  end
  else if MatchText(Cmd, ['conventions', 'rules', 'reglas']) then
    Result := MsgText(SN_HELP_CONVENTIONS)
  else if MatchText(Cmd, ['tool', 'tools']) then
  begin
    if Params.Name.Trim = '' then
      Exit(MsgText(SR_HELP_NEED_NAME) + #10#10 +
        string.Join(', ', TMCPRegistry.GetToolNames));
    Result := OneTool(Params.Name);
  end
  else
    Result := MsgText(SR_HELP_CMD);
end;

initialization
  TMCPRegistry.RegisterTool('delphi_help',
    function: IMCPTool begin Result := TDelphiHelpTool.Create; end);

end.
