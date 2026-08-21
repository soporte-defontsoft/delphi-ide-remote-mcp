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

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Hash,
  System.JSON,
  MCPServer.Logger,
  Lsp.Guard,
  Lsp.Texts;

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
  Stream: TFileStream;
begin
  try
    P := RequestInfo.Params.Values['path'].Trim;
    if P = '' then
    begin
      Answer(ResponseInfo, 400, SR_FILES_NEED_PATH);
      Exit;
    end;
    // Same door as a tools/call argument: srvX: expands only for served
    // letters; an unserved one stays literal and is refused BY NAME here -
    // never composed with the process directory by GetFullPath (measured:
    // that composition put the server's own folder into the rejection text).
    P := ExpandDriveValue(P);
    if VirtualUnitLetter(P) <> #0 then
    begin
      Answer(ResponseInfo, 403, 'RECHAZADO: unidad virtual no servida: ' +
        Copy(P, 1, 5) + ' (delphi_workspace dice cuales existen)');
      Exit;
    end;
    // Absolute server paths only (X:\...): a relative value would resolve
    // against the server process' working directory - not the client's.
    if (Length(P) < 3) or (P[2] <> ':') or not CharInSet(P[3], ['\', '/']) then
    begin
      Answer(ResponseInfo, 400, 'RECHAZADO: la ruta debe ser absoluta, en la ' +
        'forma srvd:\carpeta\fichero');
      Exit;
    end;
    try
      Full := TPath.GetFullPath(P);
    except
      on E: Exception do
      begin
        Answer(ResponseInfo, 400, 'RECHAZADO: ruta invalida (' + E.Message + ')');
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
      Answer(ResponseInfo, 403, SR_FILES_DIR);
      Exit;
    end;
    if not TFile.Exists(Full) then
    begin
      Answer(ResponseInfo, 404, SR_FILES_MISSING);
      Exit;
    end;

    // Whole-file hash in a header: the client verifies with sha256sum, the
    // same contract delphi_fetch offers on its offset=0 answer.
    Sha := THashSHA2.GetHashStringFromFile(Full, THashSHA2.TSHA2Version.SHA256);
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
    TLogger.Info(Format('files: GET %s (%d bytes)', [Full, Stream.Size]));
  except
    on E: Exception do
      Answer(ResponseInfo, 500, 'error: ' + E.Message);
  end;
end;

end.
