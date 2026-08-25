unit Mcp.Tools.Messages;

{ delphi_messages: the operator's mailbox for the agents - the way back of
  delphi_report. The operator (a person, or the assistant working next to
  them) drops a Markdown file in a "messages" folder next to the server
  executable; the agent reads its mail with this tool. A message is delivered
  ONCE: reading moves it to messages\_entregados (kept, never hard-deleted).

    messages\<agent>\*.md   for one agent (the same id it gives delphi_report)
    messages\*.md           for every agent

  There is no reliable push in MCP clients (a server notification never
  reaches the model), so the push is the tool result itself: while a message
  waits, EVERY tool answer ends with a one-line notice (hooked in the host's
  result filter through PendingMessagesNote). }

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
    [SchemaDescription('read (default: deliver every pending message for this agent, then mark it delivered) | check (titles and dates of what is pending, nothing consumed)')]
    property Command: string read FCommand write FCommand;
    [SchemaDescription('Your agent id - the same value you give delphi_report as "agent" (e.g. dsh, hermes). Messages addressed to everyone are delivered too')]
    property Agent: string read FAgent write FAgent;
  end;

  TDelphiMessagesTool = class(TMCPToolBase<TDelphiMessagesParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiMessagesParams): string; override;
  public
    constructor Create; override;
  end;

{ One line for the end of any tool result while mail waits ('' when none).
  Counts the broadcast folder plus every agent folder - the answering tool
  does not know who is asking, the line names the folders with mail. }
function PendingMessagesNote: string;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.Generics.Collections,
  MCPServer.Registration,
  Lsp.Texts;

const
  MESSAGES_DIR = 'messages';
  DELIVERED_DIR = '_entregados';

function Slug(const S: string): string;
var
  C, Prev: Char;
begin
  Result := '';
  Prev := '-';
  for C in S do
  begin
    if CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9']) then
    begin
      Result := Result + C;
      Prev := C;
    end
    else if Prev <> '-' then
    begin
      Result := Result + '-';
      Prev := '-';
    end;
    if Length(Result) >= 40 then
      Break;
  end;
  Result := Result.Trim(['-']).ToLower;
end;

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
  Root, D: string;
  Broadcast, Directed: Integer;
begin
  Result := '';
  Root := MessagesRoot;
  if not TDirectory.Exists(Root) then
    Exit;
  // MCP has no session identity here, so this notice cannot know WHO is
  // asking. It used to name every box with mail waiting - which meant an
  // agent read "MENSAJES PENDIENTES (buzon: dsh)" on nearly every answer,
  // could do nothing about it, and learned another agent's id for free
  // (three agents reported it; measured field round 8). So now:
  // - mail addressed to "todos" IS for whoever is reading: announced, and it
  //   is the only thing that names itself.
  // - mail addressed to a named agent is only COUNTED, never named. Whoever
  //   is waiting for post checks their own box; nobody else learns anything.
  Broadcast := Length(PendingIn(Root));
  Directed := 0;
  for D in TDirectory.GetDirectories(Root) do
  begin
    if SameText(TPath.GetFileName(D), DELIVERED_DIR) then
      Continue;
    Inc(Directed, Length(PendingIn(D)));
  end;
  if Broadcast > 0 then
    Result := Format(SN_MESSAGES_PENDING_ALL_FMT, [Broadcast]);
  if Directed > 0 then
    Result := Result + Format(SN_MESSAGES_PENDING_SOME_FMT, [Directed]);
end;

function FirstLine(const APath: string): string;
var
  L: TStringList;
  I: Integer;
begin
  Result := '';
  L := TStringList.Create;
  try
    L.LoadFromFile(APath, TEncoding.UTF8);
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
  Cmd, Agent, Root, AgentDir, F, Dest, DestDir: string;
  Files: TArray<string>;
  Sb: TStringBuilder;
  N: Integer;
begin
  Cmd := Params.Command.Trim.ToLower;
  if Cmd = '' then
    Cmd := 'read';
  if not MatchText(Cmd, ['read', 'check']) then
    Exit('error: command debe ser read | check');
  Agent := Slug(Params.Agent);
  Root := MessagesRoot;
  Files := PendingIn(Root);
  if Agent <> '' then
  begin
    AgentDir := TPath.Combine(Root, Agent);
    Files := PendingIn(AgentDir) + Files; // the agent's own mail first
  end;
  if Length(Files) = 0 then
  begin
    if Agent = '' then
      Exit(SN_MESSAGES_NONE_NO_AGENT)
    else
      Exit(Format(SN_MESSAGES_NONE_FMT, [Agent]));
  end;
  Sb := TStringBuilder.Create;
  try
    if Cmd = 'check' then
    begin
      Sb.AppendLine(Format(SN_MESSAGES_CHECK_FMT, [Length(Files)]));
      for F in Files do
        Sb.AppendLine(Format('  - %s  (%s%s)', [FirstLine(F), TPath.GetFileName(F),
          IfThen(SameText(TPath.GetDirectoryName(F), Root), ', para todos', '')]));
      Exit(Sb.ToString.TrimRight);
    end;
    N := 0;
    for F in Files do
    begin
      Inc(N);
      Sb.AppendLine(Format('===== MENSAJE %d/%d  (%s%s) =====', [N, Length(Files),
        TPath.GetFileName(F), IfThen(SameText(TPath.GetDirectoryName(F), Root), ', para todos', '')]));
      Sb.AppendLine(TFile.ReadAllText(F, TEncoding.UTF8).TrimRight);
      Sb.AppendLine;
      // delivered once: park it where the operator can still read it
      DestDir := TPath.Combine(Root, DELIVERED_DIR);
      if not SameText(TPath.GetDirectoryName(F), Root) then
        DestDir := TPath.Combine(DestDir, TPath.GetFileName(TPath.GetDirectoryName(F)))
      else if Agent <> '' then
        DestDir := TPath.Combine(DestDir, Agent); // who collected the broadcast
      TDirectory.CreateDirectory(DestDir);
      Dest := TPath.Combine(DestDir, TPath.GetFileName(F));
      if TFile.Exists(Dest) then
        Dest := TPath.Combine(DestDir, FormatDateTime('hhnnss', Now) + '-' + TPath.GetFileName(F));
      try
        TFile.Move(F, Dest);
      except
        // a message that cannot be parked stays pending (delivered again later)
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
