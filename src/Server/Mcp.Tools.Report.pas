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
  exist, the folder should derive from the credential instead.

  Y por workspace (David, 10-oct-2026, la via de operador de los informes):
  reports\<workspace>\<agent>\, la carpeta del workspace la pone el token
  (BuzonDeInformes, Lsp.Casa). command=list y command=read ensenan los del
  workspace de la sesion y nada mas, y no mueven ni borran nada: lo que se
  lee, se queda. }

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
    FCommand: string;
    FName: string;
  public
    // sin [Required]: list y read no lo llevan; report lo exige (REPORT-002)
    [SchemaDescription(SP_REPORT_MESSAGE)]
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
    [SchemaDescription(SP_REPORT_COMMAND)]
    property Command: string read FCommand write FCommand;
    [SchemaDescription(SP_REPORT_NAME)]
    property Name: string read FName write FName;
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
  System.JSON,
  System.RegularExpressions,
  System.Generics.Collections,
  Winapi.Windows,
  MCPServer.Registration,
  MCPServer.Logger,
  Lsp.Guard,      // CrearCarpeta: crear la carpeta tolerando la carrera
  Lsp.Patch,      // EscribeTexto: la puerta de escribir, con la casa como lugar
  Lsp.Codificacion, // ekUtf8Bom
  System.Character,
  Lsp.Listas,     // TListaDeFicheros: el organizador de las listas de ficheros
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
  // los tipos: los que acepta la tool y los que reconoce el lector del nombre
  REPORT_KINDS: array[0..3] of string = ('bug', 'limitation', 'suggestion', 'question');

{ EL nombre de un informe: '<fecha>-<hora>-<tipo>', el titulo por Slug si
  lo hay y, del segundo intento en adelante, '-N'; '.md'. EsNombreDeInforme
  es su inversa: lo que list ensena y read acepta. }
function BaseDeInforme(AStamp: TDateTime; const AKind, ATitle: string): string;
begin
  Result := FormatDateTime('yyyymmdd-hhnnss', AStamp) + '-' + AKind;
  if Slug(ATitle) <> '' then
    Result := Result + '-' + Slug(ATitle);
end;

function NombreDeInforme(const ABase: string; AIntento: Integer): string;
begin
  if AIntento > 1 then
    Result := Format('%s-%d.md', [ABase, AIntento])
  else
    Result := ABase + '.md';
end;

function EsNombreDeInforme(const ANombre: string): Boolean;
begin
  Result := TRegEx.IsMatch(ANombre, '^[0-9]{8}-[0-9]{6}-(' +
    string.Join('|', REPORT_KINDS) + ')(-[a-z0-9]+)*\.md$', [roIgnoreCase]);
end;

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

{ Los informes del buzon de la sesion que se pueden leer, por su ruta
  relativa al buzon ('.\x.md' los de sin agente, '.\<agente>\x.md'): la
  raiz y una carpeta por agente, un nivel, la estructura que escribe la tool.
  Solo lo que read aceptaria: un nombre de informe que la puerta de leer
  admite (por la ruta real: una carpeta de agente que es una union hacia
  fuera no ensena nada). Las carpetas por nombre; dentro, el mas nuevo
  primero (el nombre empieza por la fecha). }
function InformesDelBuzon: TArray<string>;
var
  Box: string;

  procedure Anade(const ADir, ARel: string);
  var
    Nombres: TArray<string>;
  begin
    Nombres := [];
    try
      for var F in TDirectory.GetFiles(ADir, '*.md') do
        if EsNombreDeInforme(TPath.GetFileName(F)) and
           (LugarDeLecturaDenegado(F, [ltCasa]) = '') then
          Nombres := Nombres + [TPath.GetFileName(F)];
    except
      // una carpeta que no se deja recorrer (una union rota, sin permiso) no
      // ensena nada y no tumba la lista de las demas
      Nombres := [];
    end;
    TArray.Sort<string>(Nombres);
    for var I := High(Nombres) downto 0 do
      Result := Result + [TPath.Combine(ARel, Nombres[I])];
  end;

begin
  Result := [];
  Box := BuzonDeInformes;
  if not TDirectory.Exists(Box) then
    Exit;
  Anade(Box, '.');
  var Dirs := TDirectory.GetDirectories(Box);
  TArray.Sort<string>(Dirs);
  for var D in Dirs do
    // la carpeta de un agente es su Slug: otra cosa no la escribe la tool
    if Slug(TPath.GetFileName(D)) = LowerCase(TPath.GetFileName(D)) then
      Anade(D, TPath.Combine('.', TPath.GetFileName(D)));
end;

function ListaDeInformes: string;
var
  Return: TJSONObject;
  Lista: TListaDeFicheros;
  Rels: TArray<string>;
begin
  Rels := InformesDelBuzon;
  Return := TJSONObject.Create;
  Lista := TListaDeFicheros.Create;
  try
    Return.AddPair('total', TJSONNumber.Create(Length(Rels)));
    for var R in Rels do
    begin
      var E := Lista.Add(R);
      try
        E.AddPair('size', TJSONNumber.Create(
          TFile.GetSize(TPath.Combine(BuzonDeInformes, R))));
      except
        // se borro mientras se listaba: el nombre sigue saliendo
      end;
    end;
    if Length(Rels) = 0 then
      Return.AddPair('note', MsgText(SN_REPORT_LISTA_VACIA))
    else
      Return.AddPair('note', MsgText(SN_REPORT_LISTA));
    Lista.Cuelga(Return);
    Result := Return.ToJSON;
  finally
    Lista.Free;
    Return.Free;
  end;
end;

{ La ruta del informe AName (como lo ensena list: '<dir>\<nombre>', con o
  sin el '.\' delante, '/' vale por '\') en el buzon de la sesion, o '' si
  no tiene la forma: un nombre de informe, solo o debajo de UNA carpeta de
  agente (su Slug). Nada del valor crudo llega al disco sin esa forma. }
function RutaDeInforme(const AName: string): string;
var
  N: string;
  Partes: TArray<string>;
begin
  Result := '';
  N := AName.Trim.Replace('/', '\');
  if N.StartsWith('.\') then
    N := N.Substring(2);
  Partes := N.Split(['\']);
  if (Length(Partes) = 1) and EsNombreDeInforme(Partes[0]) then
    Result := TPath.Combine(BuzonDeInformes, Partes[0])
  else if (Length(Partes) = 2) and (Partes[0] <> '') and
     (Slug(Partes[0]) = LowerCase(Partes[0])) and EsNombreDeInforme(Partes[1]) then
    Result := TPath.Combine(BuzonDeInformes(Partes[0]), Partes[1]);
end;

function InformeLeido(const AName: string): string;
var
  Ruta, Texto: string;
begin
  if AName.Trim = '' then
    Exit(MsgText(SR_REPORT_READ_SIN_NAME));
  Ruta := RutaDeInforme(AName);
  // lo que no tiene la forma, no esta o la puerta no admite (una union hacia
  // fuera) es lo mismo para quien pregunta: no es un informe de su workspace,
  // y la negativa no ensena donde vive la casa
  if (Ruta = '') or not TFile.Exists(Ruta) or
     (LugarDeLecturaDenegado(Ruta, [ltCasa]) <> '') then
    Exit(MsgFmt(SR_REPORT_NO_ESTA_FMT, [AName.Trim]));
  Texto := LeeTexto(Ruta, [ltCasa]);
  Result := MsgFmt(SN_REPORT_LEIDO_FMT, [AName.Trim, Length(Texto), Texto.TrimRight]);
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
  // leer lo del propio workspace (la via de operador): ni mueve ni borra
  var Cmd := Params.Command.Trim.ToLower;
  if Cmd = 'list' then
    Exit(ListaDeInformes);
  if Cmd = 'read' then
    Exit(InformeLeido(Params.Name));
  if (Cmd <> '') and (Cmd <> 'report') then
    Exit(MsgText(SR_REPORT_COMMAND));
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
  if not MatchText(Kind, REPORT_KINDS) then
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

  // el buzon del workspace de la sesion, y dentro el del agente
  Dir := BuzonDeInformes(Agent);

  Stamp := Now;
  FileName := BaseDeInforme(Stamp, Kind, Title);
  // la puerta de escribir ANTES de crear nada: la carpeta y la reserva del
  // nombre ya escriben, y por una union en reports\ se escribian fuera. Con
  // el nombre MAS LARGO que se puede llegar a probar: la medida del escritor
  // atomico es por longitud, y con el corto pasaba, se reservaba un -N mas
  // largo y la escritura lo negaba dejando la reserva vacia (revisor de P3)
  var Motivo := LugarDeEscrituraDenegado(TPath.Combine(Dir,
    NombreDeInforme(FileName, MAX_REPORT_NAME_TRIES)), ltCasa);
  if Motivo <> '' then
    Exit(Motivo);
  CrearCarpeta(Dir);
  // Never overwrite a previous report, even within the same second - and
  // "existe? pues el siguiente" NO basta: dos informes simultaneos contestan
  // que no a la vez, eligen el mismo nombre y uno pisa al otro (medido
  // 2026-09-20: de 8 informes a la vez llegaban 6). El nombre se RESERVA
  // creando el fichero en exclusiva, que es una sola operacion del sistema.
  Path := TPath.Combine(Dir, NombreDeInforme(FileName, 1));
  I := 1;
  while not ReservarNombre(Path) do
  begin
    Inc(I);
    if I > MAX_REPORT_NAME_TRIES then // absurdo, pero nunca un bucle infinito
      Exit(MsgText(SR_REPORT_NO_NAME));
    Path := TPath.Combine(Dir, NombreDeInforme(FileName, I));
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
