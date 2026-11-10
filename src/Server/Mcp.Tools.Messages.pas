unit Mcp.Tools.Messages;

{ delphi_messages: the operator's mailbox for the agents - the way back of
  delphi_report. The operator (a person, or the assistant working next to
  them) drops a Markdown file in the agent's own folder,
  messages\<workspace>\<agent>\, next to the server executable; the agent
  reads its mail with this tool. La carpeta del workspace la pone el token
  de la sesion (BuzonDeMensajes, Lsp.Casa): un workspace no ve el correo de
  otro (David, 10-oct-2026).
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
  MCPServer.Types,
  Lsp.Texts;

type
  TDelphiMessagesParams = class
  private
    FCommand: string;
    FAgent: string;
  public
    [SchemaDescription(SP_MSGS_COMMAND)]
    property Command: string read FCommand write FCommand;
    [SchemaDescription(SP_MSGS_AGENT)]
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

const
  { La clave de la nota del buzon en una respuesta JSON: la pone
    Lsp.Host.WithMailboxNote y la quita SinNotaDelBuzon. }
  CLAVE_NOTA_DEL_BUZON = 'mailbox';

{ La inversa de WithMailboxNote (Lsp.Host) con PendingMessagesNote: el texto
  de una respuesta sin la nota del buzon, sea un campo de su JSON o la linea
  de detras de una prosa. Para la respuesta que se deja EN el buzon
  (Lsp.Progreso.DejaLaRespuestaEnElBuzon): quien la lee recibe de una vez
  todo lo que espera, y la cuenta de cuando acabo la llamada ya no es verdad
  (medido el 10-nov en la VM: la respuesta de un delphi_test cortado decia
  "PENDING MESSAGES: 1", la de otro cortado antes, entregada con ella). }
function SinNotaDelBuzon(const AText: string): string;

{ How many messages wait in NAMED agent boxes of the caller's workspace.
  For delphi_workspace only: it is server state, not a message for the
  caller. }
function DirectedMessagesPending: Integer;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.Generics.Collections,
  MCPServer.Registration,
  Lsp.Guard, // SinNota: la inversa de ConNota, junto a ella
  Lsp.Puertas, // LeeTexto: la puerta de leer, con la casa como lugar
  Lsp.Casa,
  Lsp.Pascal, // SinMayusculas: EL pliegue de lo que no es una ruta
  Lsp.Identidad;

// Slug: EL normalizador de nombres de cliente vive en Lsp.Casa (uno solo).

{ Pending .md files of one folder, oldest first (by name: the operator's
  files are named by date, and sorting by name is deterministic). }
function PendingIn(const ADir: string): TArray<string>;
var
  L: TList<string>;
  F: string;
begin
  L := TList<string>.Create;
  try
    // uno VACIO es un nombre reservado cuyo texto aun se escribe
    // (EscribeDocumentoNuevo): entregarlo daba un mensaje vacio, y el texto
    // llegaba otra vez despues (hallazgo 10 del revisor de la 1.29.1)
    if TDirectory.Exists(ADir) then
      for F in TDirectory.GetFiles(ADir, '*.md') do
        try
          if TFile.GetSize(F) > 0 then
            L.Add(F);
        except
          // lo acaba de entregar (y borrar) otra lectura: ya no esta
        end;
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
  Agent := AgenteDeLaLlamada('');
  if Agent = '' then
    Exit;
  N := Length(PendingIn(BuzonDeMensajes(Agent)));
  if N > 0 then
    Result := MsgFmt(SN_MESSAGES_PENDING_FMT, [N, Agent, Agent]);
end;

function SinNotaDelBuzon(const AText: string): string;
var
  F: string;
begin
  // la nota entera, por el mismo mensaje del catalogo que la compone: su
  // comienzo (hasta el primer argumento) y su final (tras el ultimo)
  F := MsgText(SN_MESSAGES_PENDING_FMT);
  Result := SinNota(AText, CLAVE_NOTA_DEL_BUZON, Copy(F, 1, Pos('%', F) - 1),
    F.Substring(F.LastIndexOf('%s') + 2));
end;

function DirectedMessagesPending: Integer;
var
  Root, D: string;
begin
  Result := 0;
  Root := BuzonDeMensajes;
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
    // la puerta, SU negativa (un buzon que es una union: GUARD-034); lo que
    // pase despues de ella (bloqueado, recien consumido por otro lector) se
    // lista por su nombre (V200 de la 1.23.1)
    var Neg := LugarDeLecturaDenegado(APath, [ltCasa]);
    if Neg <> '' then
      raise Exception.Create(Neg);
    try
      L.Text := LeeTexto(APath, [ltCasa]);
    except
      Exit;
    end;
    for I := 0 to L.Count - 1 do
      if L[I].Trim <> '' then
        Exit(L[I].Trim.TrimLeft(['#', ' ']));
  finally
    L.Free;
  end;
end;

{ check o read del buzon de AAgent: la lista de lo que espera, o todo entregado
  y borrado. }
function LeeElBuzon(const ACmd, AAgent: string): string;
var
  F: string;
  Files: TArray<string>;
  Sb: TStringBuilder;
  N: Integer;
begin
  // UN buzon por agente y ninguno "para todos" (David, 25-sep-2026): un aviso
  // general se deja en la carpeta de cada uno.
  Files := PendingIn(BuzonDeMensajes(AAgent));
  if Length(Files) = 0 then
    Exit(MsgFmt(SN_MESSAGES_NONE_FMT, [AAgent]));
  Sb := TStringBuilder.Create;
  try
    if ACmd = 'check' then
    begin
      Sb.AppendLine(MsgFmt(SN_MESSAGES_CHECK_FMT, [Length(Files)]));
      for F in Files do
        Sb.AppendLine(Format('  - %s  (%s)', [FirstLine(F), TPath.GetFileName(F)]));
      Exit(Sb.ToString.TrimRight);
    end;
    // Todos leidos ANTES de borrar ninguno: uno que no se deja leer (otro
    // lector lo consumio entre medias, o esta bloqueado) tumbaba la respuesta
    // con los anteriores ya borrados, y se perdian (V200 de la 1.23.1)
    var Entregados: TArray<string> := [];
    N := 0;
    for F in Files do
    begin
      Inc(N);
      // la puerta primero, con SU negativa: un buzon que es una union no
      // entrega ni borra nada (GUARD-034); solo se salta lo ilegible despues
      var Neg := LugarDeLecturaDenegado(F, [ltCasa]);
      if Neg <> '' then
        raise Exception.Create(Neg);
      var Texto: string;
      try
        Texto := LeeTexto(F, [ltCasa]).TrimRight;
      except
        Sb.AppendLine(MsgFmt(SN_MESSAGES_ILEGIBLE_FMT, [TPath.GetFileName(F)]));
        Sb.AppendLine;
        Continue;
      end;
      Sb.AppendLine(MsgFmt(SF_MSGS_CABECERA_FMT, [N, Length(Files),
        TPath.GetFileName(F)]));
      Sb.AppendLine(Texto);
      Sb.AppendLine;
      Entregados := Entregados + [F];
    end;
    Sb.AppendLine(MsgText(SN_MESSAGES_DELIVERED));
    Result := Sb.ToString.TrimRight;
    // Leido = borrado, como una captura entregada (David, 25-sep-2026: "una
    // vez entregado se borra y punto, no acumulamos basura"). Nada se guarda
    // aparte y no hay purga: en el buzon solo queda lo que no se ha leido.
    for F in Entregados do
      try
        BorraFichero(F, ltCasa); // por la puerta de borrar: un buzon que es una union no borra detras
      except
        // lo que no se puede borrar sigue pendiente: se entrega otra vez
      end;
  finally
    Sb.Free;
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
  Cmd, Agent: string;
begin
  Cmd := SinMayusculas(Params.Command.Trim);
  if Cmd = '' then
    Cmd := 'read';
  if not MatchText(Cmd, ['read', 'check']) then
    Exit(MsgText(SR_MSGS_COMMAND_READ_CHECK));
  // Your id, without typing it: the handshake bound clientInfo.name to this
  // session, so the box knows who is asking. An explicit agent= still wins
  // (an operator reading a specific box, an agent whose name differs from its
  // id), but the common case - "read my mail" - needs no argument now.
  Agent := AgenteDeLaLlamada(Params.Agent);
  if Agent = '' then
    Exit(MsgText(SN_MESSAGES_NONE_NO_AGENT));
  Result := LeeElBuzon(Cmd, Agent);
  // Otro buzon que el del saludo: el correo de ESTE agente espera alli (las
  // respuestas que su cliente no recibio van al del saludo, SYS-041), y su
  // nota, la de todas las demas tools, se dice tambien aqui. Quien pasaba su
  // propio agent= leia "No messages" con el correo en el otro (sonda del
  // 10-nov-2026, test completo de Hermes de la 1.29.1)
  if not SameText(Agent, AgenteDeLaLlamada('')) then
    Result := ConNota(Result, CLAVE_NOTA_DEL_BUZON, PendingMessagesNote, '');
end;

initialization
  TMCPRegistry.RegisterTool('delphi_messages',
    function: IMCPTool begin Result := TDelphiMessagesTool.Create; end);

end.
