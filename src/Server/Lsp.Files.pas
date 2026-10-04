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
function DownloadLinkFor(const AFullPath: string): string;

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

function DownloadLinkFor(const AFullPath: string): string;
begin
  if not GFilesServed then
    Exit('');
  // un trozo, con '' (MaskDriveText con nombre de tool es el filtro de salida
  // y gasta lo que la llamada dejo anotado: las citas del disco)
  Result := FILES_ROUTE + '?path=' +
    TNetEncoding.URL.Encode(MaskDriveText('', AFullPath));
end;

{ El codigo HTTP de una negativa, por el RESULTADO que declara su etiqueta:
  INVALID_PARAM 400, NOT_FOUND 404, INTERNAL 500, DENIED (y lo demas) 403.
  Se decidia por rama y GUARD-009/010/022 o FILE-001 (INVALID_PARAM)
  salian 403 (septima revision). }
function CodigoHttp(const AMensaje: string): Integer;
begin
  Result := 403;
  if MsgOutcome(AMensaje) = 'INVALID_PARAM' then
    Result := 400
  else if MsgOutcome(AMensaje) = 'NOT_FOUND' then
    Result := 404
  else if MsgOutcome(AMensaje) = 'INTERNAL' then
    Result := 500;
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
    O.AddPair('error', MaskDriveText('', AMessage));
    ResponseInfo.ContentText := O.ToJSON;
  finally
    O.Free;
  end;
end;

{ El nombre de la descarga en Content-Disposition: en ASCII para quien solo
  lee filename, y el de verdad en filename* (RFC 6266 / 5987, UTF-8 en
  %XX): "cancion" con tilde llegaba "canci?n" (octava revision). }
function DisposicionDeDescarga(const ANombre: string): string;
const
  ATTR_CHAR = ['A'..'Z', 'a'..'z', '0'..'9', '!', '#', '$', '&', '+', '-',
    '.', '^', '_', '`', '|', '~'];
var
  Ascii, Codificado: string;
  C: Char;
  B: Byte;
begin
  Ascii := '';
  for C in ANombre do
    if (Ord(C) >= 32) and (Ord(C) < 127) and (C <> '"') and (C <> '\') then
      Ascii := Ascii + C
    else
      Ascii := Ascii + '_';
  Codificado := '';
  for B in TEncoding.UTF8.GetBytes(ANombre) do
    if (B < 128) and CharInSet(Char(B), ATTR_CHAR) then
      Codificado := Codificado + Char(B)
    else
      Codificado := Codificado + '%' + IntToHex(B, 2);
  Result := 'attachment; filename="' + Ascii + '"; filename*=UTF-8' + '''''' +
    Codificado;
end;

procedure ServeFile(RequestInfo: TIdHTTPRequestInfo;
  ResponseInfo: TIdHTTPResponseInfo);
var
  P, Full, Denied, Sha: string;
  Stream: TStream;
begin
  try
    // la ruta TAL CUAL a las reglas, como la de una tool: "a b.txt " servia
    // "a b.txt" y las tools daban GUARD-010 (octava revision)
    P := RequestInfo.Params.Values['path'];
    if P.Trim = '' then
    begin
      Answer(ResponseInfo, CodigoHttp(MsgText(SR_FILES_NEED_PATH)), MsgText(SR_FILES_NEED_PATH));
      Exit;
    end;
    // Same door as a tools/call argument: srvX: expands only for served
    // letters; an unserved one stays literal and is refused BY NAME here -
    // never composed with the process directory by GetFullPath (measured:
    // that composition put the server's own folder into the rejection text).
    P := ExpandDriveValue(P);
    if VirtualUnitLetter(P) <> #0 then
    begin
      var MUnidad := MsgFmt(SR_FILES_UNIDAD_VIRTUAL_NO_SERVIDA_FMT, [Copy(P, 1, 5)]);
      Answer(ResponseInfo, CodigoHttp(MUnidad), MUnidad);
      Exit;
    end;
    // Una ruta RELATIVA la niega la puerta de lectura como a toda tool
    // (GUARD-021, RutaRelativaDenegada a la entrada de PathDenied): aqui
    // habia un segundo lector de la misma regla con su propio texto
    // (FILE-030; novena revision, M6)
    // las reglas ven la ruta COMO LLEGA (downloading is reading): con
    // GetFullPath delante, "a.txt." era "a.txt" y la anomalia no se veia
    Denied := ReadPathDenied(P);
    if Denied <> '' then
    begin
      Answer(ResponseInfo, CodigoHttp(Denied), Denied);
      Exit;
    end;
    try
      Full := TPath.GetFullPath(P);
    except
      on E: Exception do
      begin
        // el codigo por el resultado de la etiqueta, como en las demas
        // negativas de esta ruta (se elegia de dos formas; novena, M4)
        var M := MsgFmt(SR_FILES_RUTA_INVALIDA_FMT, [E.Message]);
        Answer(ResponseInfo, CodigoHttp(M), M);
        Exit;
      end;
    end;
    if TDirectory.Exists(Full) then
    begin
      Answer(ResponseInfo, CodigoHttp(MsgText(SR_FILES_DIR)), MsgText(SR_FILES_DIR));
      Exit;
    end;
    if not TFile.Exists(Full) then
    begin
      Answer(ResponseInfo, CodigoHttp(MsgText(SR_FILES_MISSING)), MsgText(SR_FILES_MISSING));
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
    ResponseInfo.ContentDisposition := DisposicionDeDescarga(TPath.GetFileName(Full));
    ResponseInfo.CustomHeaders.Values['X-File-SHA256'] := Sha;
    ResponseInfo.ContentLength := Stream.Size;
    ResponseInfo.ContentStream := Stream; // streamed, never loaded whole
    ResponseInfo.FreeContentStream := True;
    // The server log is the operator's own: the real path is fine here.
    TLogger.Info(MsgFmt(SL_FILES_GET_FMT, [Full, Stream.Size]));
  except
    on E: Exception do
    begin
      // el codigo por el resultado, tambien aqui: un fichero que otro tiene
      // abierto (SYS-027 DENIED) salia 500 "el servidor se rompio" (octava)
      var M := MsgExcepcion(E.ClassName, E.Message);
      Answer(ResponseInfo, CodigoHttp(M), M);
    end;
  end;
end;

end.
