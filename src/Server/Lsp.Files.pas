unit Lsp.Files;

{ The direct download route: GET /files?path=srvd:\...\file on the SAME HTTP
  host that serves /mcp, behind the SAME Bearer gate, vetted by the SAME read
  jail as delphi_read / delphi_fetch.

  Why it exists (field 2026-08-21): delphi_fetch moves bytes as base64 chunks
  INSIDE tool results - i.e. through the model's context window. Fine for a
  1 MB exe; absurd for the 72 MB PAServer installer (nine 11 MB chunks, ~24M
  tokens against a 262K context). The field agent only survived by abusing a
  client-side quirk. Big binaries are HTTP's job: the agent curls this route
  with its same token and nothing enters its context. Still "MCP only": same
  exe, same port, same credential, same jail - no SMB, no SSH, no side door.

  The vendor host only routes here; every decision (path expansion, jail,
  existence, streaming) is ours. }

interface

uses
  IdCustomHTTPServer;

const
  FILES_ROUTE = '/files';

var
  // Set by the HTTP host when the route is live; stdio/console-without-http
  // leave it False, and delphi_fetch then omits the download link it could
  // not honour.
  GFilesServed: Boolean = False;

procedure ServeFile(RequestInfo: TIdHTTPRequestInfo;
  ResponseInfo: TIdHTTPResponseInfo);

{ EL enlace de descarga de un fichero del servidor, el mismo para toda tool
  que entregue uno (delphi_fetch, delphi_desktop): relativo a proposito (el
  cliente ya sabe a que host:port habla), la ruta en su forma VIRTUAL y
  URL-encoded - ninguna letra de unidad real sale, codificada o no. Vacio
  cuando la ruta /files no esta servida (stdio). Un agente pequeno que
  recompone la ruta a mano se equivoca (hermes, 25-sep-2026: metio su
  carpeta en medio y pidio un fichero que nunca existio); un enlace se copia. }
function DownloadLinkFor(const AToolName, AFullPath: string): string;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Hash,
  System.JSON,
  MCPServer.Logger,
  System.NetEncoding,
  Lsp.Guard,
  Lsp.Texts,
  Lsp.ShaCache;

function DownloadLinkFor(const AToolName, AFullPath: string): string;
begin
  if not GFilesServed then
    Exit('');
  Result := FILES_ROUTE + '?path=' +
    TNetEncoding.URL.Encode(MaskDriveText(AToolName, AFullPath));
end;

procedure Answer(ResponseInfo: TIdHTTPResponseInfo; ACode: Integer;
  const AMessage: string);
var
  O: TJSONObject;
begin
  ResponseInfo.ResponseNo := ACode;
  ResponseInfo.ContentType := 'application/json; charset=utf-8';
  O := TJSONObject.Create;
  try
    // The message may quote a path: it leaves masked, like every tool answer.
    O.AddPair('error', MaskDriveText('files', AMessage));
    ResponseInfo.ContentText := O.ToJSON;
  finally
    O.Free;
  end;
end;

procedure ServeFile(RequestInfo: TIdHTTPRequestInfo;
  ResponseInfo: TIdHTTPResponseInfo);
var
  P, Full, Denied, Sha: string;
  Stream: TStream;
begin
  try
    P := RequestInfo.Params.Values['path'].Trim;
    if P = '' then
    begin
      Answer(ResponseInfo, 400, MsgText(SR_FILES_NEED_PATH));
      Exit;
    end;
    // Same door as a tools/call argument: srvX: expands only for served
    // letters; an unserved one stays literal and is refused BY NAME here -
    // never composed with the process directory by GetFullPath (measured:
    // that composition put the server's own folder into the rejection text).
    P := ExpandDriveValue(P);
    if VirtualUnitLetter(P) <> #0 then
    begin
      Answer(ResponseInfo, 403, MsgFmt(SR_FILES_UNIDAD_VIRTUAL_NO_SERVIDA_FMT, [Copy(P, 1, 5)]));
      Exit;
    end;
    // Absolute server paths only (X:\...): a relative value would resolve
    // against the server process' working directory - not the client's.
    // LA regla de ruta completa (Lsp.Guard.EsRutaAbsoluta): aqui estaba a
    // mano, sin UNC y sin mirar la letra (sexta revision)
    if not EsRutaAbsoluta(P) then
    begin
      Answer(ResponseInfo, 400, MsgText(SR_FILES_RUTA_ABSOLUTA));
      Exit;
    end;
    try
      Full := TPath.GetFullPath(P);
    except
      on E: Exception do
      begin
        Answer(ResponseInfo, 400, MsgFmt(SR_FILES_RUTA_INVALIDA_FMT, [E.Message]));
        Exit;
      end;
    end;
    Denied := ReadPathDenied(Full); // downloading is reading
    if Denied <> '' then
    begin
      Answer(ResponseInfo, 403, Denied);
      Exit;
    end;
    if TDirectory.Exists(Full) then
    begin
      Answer(ResponseInfo, 403, MsgText(SR_FILES_DIR));
      Exit;
    end;
    if not TFile.Exists(Full) then
    begin
      Answer(ResponseInfo, 404, MsgText(SR_FILES_MISSING));
      Exit;
    end;

    // Whole-file hash in a header: the client verifies with sha256sum, the
    // same contract delphi_fetch offers on its offset=0 answer.
    Sha := CachedFileSha256(Full); // shared with delphi_fetch: hashed once per (path, mtime, size)
    if IsAgentCapture(Full) then
    begin
      // Una captura del escritorio se consume al recogerla (David,
      // 25-sep-2026): entera en memoria (unos MB), fuera del disco, y se
      // sirve desde memoria. Una segunda peticion es un 404 honesto.
      Stream := TMemoryStream.Create;
      TMemoryStream(Stream).LoadFromFile(Full);
      Stream.Position := 0;
      ConsumeAgentCapture(Full);
    end
    else
      Stream := TFileStream.Create(Full, fmOpenRead or fmShareDenyWrite);
    ResponseInfo.ResponseNo := 200;
    ResponseInfo.ContentType := 'application/octet-stream';
    ResponseInfo.ContentDisposition := 'attachment; filename="' +
      TPath.GetFileName(Full) + '"';
    ResponseInfo.CustomHeaders.Values['X-File-SHA256'] := Sha;
    ResponseInfo.ContentLength := Stream.Size;
    ResponseInfo.ContentStream := Stream; // streamed, never loaded whole
    ResponseInfo.FreeContentStream := True;
    // The server log is the operator's own: the real path is fine here.
    TLogger.Info(MsgFmt(SL_FILES_GET_FMT, [Full, Stream.Size]));
  except
    on E: Exception do
      Answer(ResponseInfo, 500, MsgExcepcion(E.ClassName, E.Message));
  end;
end;

end.
