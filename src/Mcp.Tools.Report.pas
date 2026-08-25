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
    [SchemaDescription('The report itself: what you tried, what happened, what you expected. Markdown welcome, several paragraphs are fine')]
    [Required]
    property Message: string read FMessage write FMessage;
    [SchemaDescription('Optional one-line summary (becomes part of the file name)')]
    property Title: string read FTitle write FTitle;
    [SchemaDescription('Optional: bug | limitation | suggestion | question (default: bug)')]
    property Kind: string read FKind write FKind;
    [SchemaDescription('Optional: who is reporting (agent/model name, project) - helps us read the history later')]
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
  MCPServer.Registration,
  MCPServer.Logger;

const
  REPORTS_DIR = 'reports';
  // delphi_report is the ONE write a read-only (even anonymous) credential may
  // perform, so it is also the only way such a client could grow the server's
  // disk. Generous on purpose - the field audit's longest genuine report was
  // 45 KB - so no honest reporter ever meets it, while "fill the disk in a
  // single call" stops being free. Bounded HERE, next to the empty-message
  // check: it is this tool's own input contract, not an access decision.
  MAX_REPORT_BYTES = 256 * 1024;

{ File-name-safe slug of the title (ASCII letters/digits/dashes, capped). }
function Slug(const S: string): string;
var
  C: Char;
  Prev: Char;
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

{ TDelphiReportTool }

constructor TDelphiReportTool.Create;
begin
  inherited;
  FName := 'delphi_report';
  FDescription := SD_REPORT;
end;

function TDelphiReportTool.ExecuteWithParams(const Params: TDelphiReportParams): string;
var
  Dir, FileName, Path, Kind, Title, Agent, Body: string;
  Stamp: TDateTime;
  Sb: TStringBuilder;
  I, Size: Integer;
begin
  if Params.Message.Trim = '' then
    Exit(SR_REPORT_EMPTY);

  // Measured on the WHOLE payload the client controls (title, from and agent
  // travel into the body too), in bytes of the encoding written to disk.
  Size := TEncoding.UTF8.GetByteCount(
    Params.Message + Params.Title + Params.From + Params.Agent);
  if Size > MAX_REPORT_BYTES then
    Exit(Format(SR_REPORT_TOO_BIG_FMT,
      [Size div 1024, MAX_REPORT_BYTES div 1024]));

  Kind := Params.Kind.Trim.ToLower;
  if not MatchText(Kind, ['bug', 'limitation', 'suggestion', 'question']) then
    Kind := 'bug';
  Title := Params.Title.Trim;
  // One subfolder per emitter. Slug() - the same normalizer as the title -
  // is what keeps this a server-generated path: nothing of the raw client
  // value reaches the filesystem. Empty (or slugged-to-empty) = the root
  // reports folder, exactly as before the parameter existed.
  Agent := Slug(Params.Agent);

  Dir := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), REPORTS_DIR);
  if Agent <> '' then
    Dir := TPath.Combine(Dir, Agent);
  TDirectory.CreateDirectory(Dir);

  Stamp := Now;
  FileName := FormatDateTime('yyyymmdd-hhnnss', Stamp) + '-' + Kind;
  if Slug(Title) <> '' then
    FileName := FileName + '-' + Slug(Title);
  // never overwrite a previous report, even within the same second
  Path := TPath.Combine(Dir, FileName + '.md');
  I := 1;
  while TFile.Exists(Path) do
  begin
    Inc(I);
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

  // UTF-8 with BOM: these are documents for humans, not Delphi sources.
  TFile.WriteAllText(Path, Body, TEncoding.UTF8);
  TLogger.Info(Format('delphi_report: %s (%s) from "%s"',
    [IfThen(Agent <> '', Agent + '/', '') + TPath.GetFileName(Path), Kind,
     Params.From.Trim]));

  // The confirmation names the folder too, so the agent knows where its
  // history accumulates.
  Result := Format(SN_REPORT_OK_FMT,
    [IfThen(Agent <> '', Agent + '/', '') + TPath.GetFileName(Path),
     SERVER_VERSION]);
end;

initialization
  TMCPRegistry.RegisterTool('delphi_report',
    function: IMCPTool begin Result := TDelphiReportTool.Create; end);

end.
