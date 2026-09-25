unit Mcp.Tools.Messages;

{ delphi_messages: the operator's mailbox for the agents - the way back of
  delphi_report. The operator (a person, or the assistant working next to
  them) drops a Markdown file in the agent's own folder, messages\<agent>\,
  next to the server executable; the agent reads its mail with this tool.
  Reading DELETES it, like a delivered capture: nothing is kept aside and
  nothing is purged later, so the box only ever holds what has not been read
  (David, 2026-09-25). There is no box "for everyone": a notice for all goes
  into each agent's folder - two places to look at meant agents looked at
  the wrong one.

  There is no reliable push in MCP clients (a server notification never
  reaches the model), so the push is the tool result itself: while the
  caller's own mail waits, EVERY tool answer ends with a one-line notice
  (hooked in the host's result filter through PendingMessagesNote). }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types;

type
  TDelphiMessagesParams = class
  private
    FCommand: string;
    FAgent: string;
  public
    [SchemaDescription('read (default: deliver every pending message in your box, then DELETE it: a message is read once) | check (titles and dates of what is pending, nothing consumed)')]
    property Command: string read FCommand write FCommand;
    [SchemaDescription('Your agent id - the same value you give delphi_report as "agent" (e.g. dsh, hermes). Omitted: the id your client declared at the handshake')]
    property Agent: string read FAgent write FAgent;
  end;

  TDelphiMessagesTool = class(TMCPToolBase<TDelphiMessagesParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiMessagesParams): string; override;
  public
    constructor Create; override;
  end;

{ One line for the end of any tool result while the CALLER's own mail waits
  ('' when none). The caller is the identity bound at the handshake
  (clientInfo.name). Other agents' boxes are never named or counted here: a
  count of other people's post was 90 bytes of untrue, unclearable noise on
  every answer (measured 2026-09-20, ~40 consecutive calls) - that count
  lives in delphi_workspace, the orientation call. The caller's own mail is
  different: it can read it, and reading it turns the line off. }
function PendingMessagesNote: string;

{ How many messages wait in NAMED agent boxes. For delphi_workspace only:
  it is server state, not a message for the caller. }
function DirectedMessagesPending: Integer;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.Generics.Collections,
  MCPServer.Registration,
  Lsp.Guard,
  Lsp.Patch,   // DecodeSourceBytes: el lector de la casa
  Lsp.Texts;

const
  MESSAGES_DIR = 'messages';

// Slug: EL normalizador de nombres de cliente vive en Lsp.Guard (uno solo).

function MessagesRoot: string;
begin
  Result := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), MESSAGES_DIR);
end;

{ Pending .md files of one folder, oldest first (by name: the operator's
  files are named by date, and sorting by name is deterministic). }
function PendingIn(const ADir: string): TArray<string>;
var
  L: TList<string>;
  F: string;
begin
  L := TList<string>.Create;
  try
    if TDirectory.Exists(ADir) then
      for F in TDirectory.GetFiles(ADir, '*.md') do
        L.Add(F);
    L.Sort;
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

function PendingMessagesNote: string;
var
  Agent: string;
  N: Integer;
begin
  Result := '';
  // El correo del que PREGUNTA, y solo el suyo. Antes solo se anunciaba el
  // buzon "para todos"; desde que no existe (David, 25-sep-2026) el aviso es
  // el del propio agente, que puede leerlo y apagarlo.
  Agent := Slug(CurrentAgent);
  if Agent = '' then
    Exit;
  N := Length(PendingIn(TPath.Combine(MessagesRoot, Agent)));
  if N > 0 then
    Result := Format(SN_MESSAGES_PENDING_FMT, [N, Agent]);
end;

function DirectedMessagesPending: Integer;
var
  Root, D: string;
begin
  Result := 0;
  Root := MessagesRoot;
  if not TDirectory.Exists(Root) then
    Exit;
  for D in TDirectory.GetDirectories(Root) do
  begin
    Inc(Result, Length(PendingIn(D)));
  end;
end;

function FirstLine(const APath: string): string;
var
  L: TStringList;
  I: Integer;
begin
  Result := '';
  L := TStringList.Create;
  try
    L.Text := DecodeSourceBytes(TFile.ReadAllBytes(APath));
    for I := 0 to L.Count - 1 do
      if L[I].Trim <> '' then
        Exit(L[I].Trim.TrimLeft(['#', ' ']));
  finally
    L.Free;
  end;
end;

{ TDelphiMessagesTool }

constructor TDelphiMessagesTool.Create;
begin
  inherited;
  FName := 'delphi_messages';
  FDescription := SD_MESSAGES;
end;

function TDelphiMessagesTool.ExecuteWithParams(const Params: TDelphiMessagesParams): string;
var
  Cmd, Agent, F: string;
  Files: TArray<string>;
  Sb: TStringBuilder;
  N: Integer;
begin
  Cmd := Params.Command.Trim.ToLower;
  if Cmd = '' then
    Cmd := 'read';
  if not MatchText(Cmd, ['read', 'check']) then
    Exit('error: command debe ser read | check');
  // Your id, without typing it: the handshake bound clientInfo.name to this
  // session, so the box knows who is asking. An explicit agent= still wins
  // (an operator reading a specific box, an agent whose name differs from its
  // id), but the common case - "read my mail" - needs no argument now.
  Agent := Slug(Params.Agent);
  if Agent = '' then
    Agent := Slug(CurrentAgent);
  if Agent = '' then
    Exit(SN_MESSAGES_NONE_NO_AGENT);
  // UN buzon por agente y ninguno "para todos" (David, 25-sep-2026): un aviso
  // general se deja en la carpeta de cada uno.
  Files := PendingIn(TPath.Combine(MessagesRoot, Agent));
  if Length(Files) = 0 then
    Exit(Format(SN_MESSAGES_NONE_FMT, [Agent]));
  Sb := TStringBuilder.Create;
  try
    if Cmd = 'check' then
    begin
      Sb.AppendLine(Format(SN_MESSAGES_CHECK_FMT, [Length(Files)]));
      for F in Files do
        Sb.AppendLine(Format('  - %s  (%s)', [FirstLine(F), TPath.GetFileName(F)]));
      Exit(Sb.ToString.TrimRight);
    end;
    N := 0;
    for F in Files do
    begin
      Inc(N);
      Sb.AppendLine(Format('===== MENSAJE %d/%d  (%s) =====', [N, Length(Files),
        TPath.GetFileName(F)]));
      Sb.AppendLine(DecodeSourceBytes(TFile.ReadAllBytes(F)).TrimRight);
      Sb.AppendLine;
      // Leido = borrado, como una captura entregada (David, 25-sep-2026: "una
      // vez entregado se borra y punto, no acumulamos basura"). Nada se guarda
      // aparte y no hay purga: en el buzon solo queda lo que no se ha leido.
      try
        TFile.Delete(F);
      except
        // lo que no se puede borrar sigue pendiente: se entrega otra vez
      end;
    end;
    Sb.AppendLine(SN_MESSAGES_DELIVERED);
    Result := Sb.ToString.TrimRight;
  finally
    Sb.Free;
  end;
end;

initialization
  TMCPRegistry.RegisterTool('delphi_messages',
    function: IMCPTool begin Result := TDelphiMessagesTool.Create; end);

end.
