unit Mcp.Tools.Report;

{ delphi_report: the feedback channel of this server. A client (usually an AI
  agent) reports a problem, a limitation or a suggestion, and the server
  stores it as ONE markdown file per report - version, date, origin and the
  message - inside a "reports" folder next to the executable, so the whole
  history can be read later and worked through.

  Deliberately available at EVERY access level, read-only included: the
  agents most likely to hit a wall are precisely the restricted ones. It is
  safe by construction - the client never supplies a path: the folder is
  fixed and the file name is generated here. The optional "agent" id groups
  reports in one subfolder per emitter (several agents share one server);
  it is SLUGGED before touching the filesystem, so the path stays
  server-generated. Self-declared for now - if per-agent credentials ever
  exist, the folder should derive from the credential instead. }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Attributes, // [Contenido]: el mensaje es texto, no rutas
  Lsp.Texts;

type
  TDelphiReportParams = class
  private
    FMessage: string;
    FTitle: string;
    FKind: string;
    FFrom: string;
    FAgent: string;
  public
    [SchemaDescription(SP_REPORT_MESSAGE)]
    [Required]
    [Contenido]
    property Message: string read FMessage write FMessage;
    [SchemaDescription(SP_REPORT_TITLE)]
    [Contenido] // va dentro del informe, como el mensaje (revisor de B-9)
    property Title: string read FTitle write FTitle;
    [SchemaDescription(SP_REPORT_KIND)]
    property Kind: string read FKind write FKind;
    [SchemaDescription(SP_REPORT_FROM)]
    property From: string read FFrom write FFrom;
    [SchemaDescription(SP_REPORT_AGENT)]
    property Agent: string read FAgent write FAgent;
  end;

  TDelphiReportTool = class(TMCPToolBase<TDelphiReportParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiReportParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  System.IOUtils,
  System.Classes,
  System.StrUtils,
  Winapi.Windows,
  MCPServer.Registration,
  MCPServer.Logger,
  Lsp.Guard,      // CrearCarpeta: crear la carpeta tolerando la carrera
  Lsp.Patch,      // EscribeTexto: la puerta de escribir, con la casa como lugar
  Lsp.Codificacion, // ekUtf8Bom
  System.Character,
  Lsp.Casa;

const
  // delphi_report is the ONE write a read-only (even anonymous) credential may
  // perform, so it is also the only way such a client could grow the server's
  // disk. Generous on purpose - the field audit's longest genuine report was
  // 45 KB - so no honest reporter ever meets it, while "fill the disk in a
  // single call" stops being free. Bounded HERE, next to the empty-message
  // check: it is this tool's own input contract, not an access decision.
  MAX_REPORT_BYTES = 256 * 1024;
  // the names a report may try in one folder before giving up (-2 .. -500)
  MAX_REPORT_NAME_TRIES = 500;

// Slug: EL normalizador de nombres de cliente vive en Lsp.Casa (uno solo).

{ Reserva el nombre creando el fichero VACIO en exclusiva: si ya existe (o lo
  acaba de crear otro hilo en este mismo instante) devuelve False y el llamante
  prueba el siguiente. CREATE_NEW es atomico en el sistema de ficheros, que es
  justo lo que "if not FileExists then escribir" no es. }
function ReservarNombre(const APath: string): Boolean;
var
  H: THandle;
begin
  H := CreateFile(PChar(APath), GENERIC_WRITE, 0, nil, CREATE_NEW,
    FILE_ATTRIBUTE_NORMAL, 0);
  Result := H <> INVALID_HANDLE_VALUE;
  if Result then
    CloseHandle(H);
end;

{ TDelphiReportTool }

constructor TDelphiReportTool.Create;
begin
  inherited;
  FName := 'delphi_report';
  FDescription := SD_REPORT;
end;

function TDelphiReportTool.ExecuteWithParams(const Params: TDelphiReportParams): string;
var
  Dir, FileName, Path, Kind, Title, Agent, Body, KindNote: string;
  Stamp: TDateTime;
  Sb: TStringBuilder;
  I, Size: Integer;
begin
  if Params.Message.Trim = '' then
    Exit(MsgText(SR_REPORT_EMPTY));

  // Measured on the WHOLE payload the client controls (title, from and agent
  // travel into the body too), in bytes of the encoding written to disk.
  Size := TEncoding.UTF8.GetByteCount(
    Params.Message + Params.Title + Params.From + Params.Agent);
  if Size > MAX_REPORT_BYTES then
    Exit(MsgFmt(SR_REPORT_TOO_BIG_FMT,
      [Size div 1024, MAX_REPORT_BYTES div 1024]));

  Kind := Params.Kind.Trim.ToLower;
  // A kind nobody recognises used to become "bug" in silence, so a report
  // filed as something else was quietly refiled and the sender never knew
  // (measured 2026-08-25). It still goes through - losing a report over a
  // typo would be worse - but the answer says what it did.
  KindNote := '';
  if not MatchText(Kind, ['bug', 'limitation', 'suggestion', 'question']) then
  begin
    if Kind <> '' then
      KindNote := MsgFmt(SN_REPORT_KIND_FMT, [Params.Kind.Trim]);
    Kind := 'bug';
  end;
  Title := Params.Title.Trim;
  // One subfolder per emitter. Slug() - the same normalizer as the title -
  // is what keeps this a server-generated path: nothing of the raw client
  // value reaches the filesystem. Empty (or slugged-to-empty) = the root
  // reports folder, exactly as before the parameter existed.
  Agent := Slug(Params.Agent);

  Dir := CarpetaDeInformes;
  if Agent <> '' then
    Dir := TPath.Combine(Dir, Agent);

  Stamp := Now;
  FileName := FormatDateTime('yyyymmdd-hhnnss', Stamp) + '-' + Kind;
  if Slug(Title) <> '' then
    FileName := FileName + '-' + Slug(Title);
  // la puerta de escribir ANTES de crear nada: la carpeta y la reserva del
  // nombre ya escriben, y por una union en reports\ se escribian fuera. Con
  // el nombre MAS LARGO que se puede llegar a probar: la medida del escritor
  // atomico es por longitud, y con el corto pasaba, se reservaba un -N mas
  // largo y la escritura lo negaba dejando la reserva vacia (revisor de P3)
  var Motivo := LugarDeEscrituraDenegado(TPath.Combine(Dir,
    Format('%s-%d.md', [FileName, MAX_REPORT_NAME_TRIES])), ltCasa);
  if Motivo <> '' then
    Exit(Motivo);
  CrearCarpeta(Dir);
  // Never overwrite a previous report, even within the same second - and
  // "existe? pues el siguiente" NO basta: dos informes simultaneos contestan
  // que no a la vez, eligen el mismo nombre y uno pisa al otro (medido
  // 2026-09-20: de 8 informes a la vez llegaban 6). El nombre se RESERVA
  // creando el fichero en exclusiva, que es una sola operacion del sistema.
  Path := TPath.Combine(Dir, FileName + '.md');
  I := 1;
  while not ReservarNombre(Path) do
  begin
    Inc(I);
    if I > MAX_REPORT_NAME_TRIES then // absurdo, pero nunca un bucle infinito
      Exit(MsgText(SR_REPORT_NO_NAME));
    Path := TPath.Combine(Dir, Format('%s-%d.md', [FileName, I]));
  end;

  Sb := TStringBuilder.Create;
  try
    if Title <> '' then
      Sb.AppendLine('# ' + Title)
    else
      Sb.AppendLine('# ' + Kind + ' report');
    Sb.AppendLine;
    Sb.AppendLine('- **Date**: ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Stamp));
    Sb.AppendLine('- **Server version**: ' + SERVER_VERSION);
    Sb.AppendLine('- **Kind**: ' + Kind);
    if Agent <> '' then
      Sb.AppendLine('- **Agent**: ' + Agent);
    if Params.From.Trim <> '' then
      Sb.AppendLine('- **From**: ' + Params.From.Trim);
    Sb.AppendLine;
    Sb.AppendLine('---');
    Sb.AppendLine;
    Sb.AppendLine(Params.Message.TrimRight);
    Body := Sb.ToString;
  finally
    Sb.Free;
  end;

  // UTF-8 with BOM: these are documents for humans, not Delphi sources. Por
  // la puerta de escribir, entero o nada, sobre el nombre ya reservado
  try
    EscribeTexto(Path, Body, ltCasa, ekUtf8Bom);
  except
    // la reserva vacia no se queda: un informe sin cuerpo no es de nadie
    try
      BorraFichero(Path, ltCasa);
    except
    end;
    raise;
  end;
  TLogger.Info(MsgFmt(SL_REPORT_DELPHI_REPORT_FROM_FMT,
    [IfThen(Agent <> '', Agent + '/', '') + TPath.GetFileName(Path), Kind,
     Params.From.Trim]));

  // The confirmation names the folder too, so the agent knows where its
  // history accumulates.
  // Y dice cuanto guardo y como acaba: el informe final de Hermes llego
  // cortado a 4.000 caracteres por SU lado (validacion de la 1.16.0) y la
  // respuesta solo decia "guardado"; viendo el final, el corte se ve.
  var Guardado := Params.Message.TrimRight;
  var Cola := Guardado;
  if Length(Cola) > 60 then
  begin
    Cola := Copy(Cola, Length(Cola) - 59, 60);
    if (Cola <> '') and Cola[1].IsLowSurrogate then // no partir un par UTF-16
      Delete(Cola, 1, 1);
    Cola := '...' + Cola;
  end;
  Cola := Cola.Replace(#13, ' ').Replace(#10, ' ');
  Result := MsgFmt(SN_REPORT_OK_FMT,
    [IfThen(Agent <> '', Agent + '/', '') + TPath.GetFileName(Path),
     SERVER_VERSION, Length(Guardado), Cola]) + KindNote;
end;

initialization
  TMCPRegistry.RegisterTool('delphi_report',
    function: IMCPTool begin Result := TDelphiReportTool.Create; end);

end.
