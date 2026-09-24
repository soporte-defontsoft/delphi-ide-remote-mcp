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
  MCPServer.Registration;

constructor TDelphiHelpTool.Create;
begin
  inherited;
  FName := 'delphi_help';
  FDescription := SD_HELP;
end;

function OneTool(const AName: string): string; forward;

{ Levenshtein distance, capped: enough to tell "delphi_edt" from
  "delphi_edit" without pretending to be a spell checker. }
function EditDistance(const A, B: string): Integer;
var
  I, J, Cost, Prev, Cur: Integer;
  Row: TArray<Integer>;
begin
  if A = B then
    Exit(0);
  if (A = '') or (B = '') then
    Exit(Max(Length(A), Length(B)));
  SetLength(Row, Length(B) + 1);
  for J := 0 to Length(B) do
    Row[J] := J;
  for I := 1 to Length(A) do
  begin
    Prev := Row[0];
    Row[0] := I;
    for J := 1 to Length(B) do
    begin
      Cost := IfThen(A[I] = B[J], 0, 1);
      Cur := Row[J];
      Row[J] := Min(Min(Row[J] + 1, Row[J - 1] + 1), Prev + Cost);
      Prev := Cur;
    end;
  end;
  Result := Row[Length(B)];
end;

{ One tool in full: what tools/list would say about it, alone. }
function OneTool(const AName: string): string;
var
  Tool: IMCPTool;
  Ret: TJSONObject;
  Schema: TJSONObject;
  Names: TArray<string>;
  N, Close, BestName: string;
  Best, Ties: Integer;
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
    Best := MaxInt;
    BestName := '';
    Ties := 0;
    for var Cand in Names do
    begin
      var D := EditDistance(N, Cand);
      if D < Best then
      begin
        Best := D;
        BestName := Cand;
        Ties := 1;
      end
      else if D = Best then
        Inc(Ties);
    end;
    if (Best <= 2) and (Ties = 1) then
      Exit(Format(SN_HELP_ASSUMED_FMT, [AName.Trim, BestName]) + #10 +
        OneTool(BestName));
    if Close = '' then
      for var Cand in Names do
        if EditDistance(N, Cand) <= 2 then
          Close := Close + IfThen(Close <> '', ', ', '') + Cand;
    if Close = '' then
      Exit(Format(SR_HELP_NO_TOOL_ALL_FMT,
        [AName.Trim, string.Join(', ', Names)]));
    Exit(Format(SR_HELP_NO_TOOL_FMT, [AName.Trim, Close]));
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
    Ret.AddPair('note', SN_HELP_TOOL_NOTE);
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
    Result := SN_HELP_TASKS
  else if MatchText(Cmd, ['conventions', 'rules', 'reglas']) then
    Result := SN_HELP_CONVENTIONS
  else if MatchText(Cmd, ['tool', 'tools']) then
  begin
    if Params.Name.Trim = '' then
      Exit(SR_HELP_NEED_NAME + #10#10 +
        string.Join(', ', TMCPRegistry.GetToolNames));
    Result := OneTool(Params.Name);
  end
  else
    Result := SR_HELP_CMD;
end;

initialization
  TMCPRegistry.RegisterTool('delphi_help',
    function: IMCPTool begin Result := TDelphiHelpTool.Create; end);

end.
