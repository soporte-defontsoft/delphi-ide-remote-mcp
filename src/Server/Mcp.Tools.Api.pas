unit Mcp.Tools.Api;

{ delphi_api (1.29): las APIs HTTP con nombre que define el operador
  (Lsp.Conexiones) y abre a cada workspace con ApiAllowedProjects= - un mini
  Postman GENERICO (David, 6-nov-2026: "una api conexion generica, no es
  solo para este proyecto nuestro"). Lo que compone el agente: el metodo (de
  los que permite la API), la ruta RELATIVA (ni host ni salir por ..), la
  query, sus cabeceras y el cuerpo (texto o formulario). Lo que fija el
  operador y nunca viaja del agente: la URL base, la credencial, las
  cabeceras fijas, el pin y los metodos. Lo que vuelve: estado, cabeceras,
  tiempo y cuerpo (el JSON como JSON), con la credencial tapada (una API
  que repite las cabeceras la ensenaria). El transporte, Lsp.ClienteHttp. }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Attributes, // JsonComoTexto, Contenido, RutaDelServidor
  Lsp.Texts;

type
  TDelphiApiParams = class
  private
    FCommand, FApi, FMethod, FPath, FQuery, FHeaders, FBody, FForm, FOut: string;
  public
    [SchemaDescription(SP_API_COMMAND)]
    property Command: string read FCommand write FCommand;
    [SchemaDescription(SP_API_API)]
    property Api: string read FApi write FApi;
    [SchemaDescription(SP_API_METHOD)]
    property Method: string read FMethod write FMethod;
    // lo que va a un programa de OTRA maquina es contenido: un srvd:\ del
    // agente no se expande a la letra del servidor (Lsp.Attributes)
    [SchemaDescription(SP_API_PATH)]
    [Contenido]
    property Path: string read FPath write FPath;
    [SchemaDescription(SP_API_QUERY)]
    [JsonComoTexto]
    [Contenido]
    property Query: string read FQuery write FQuery;
    [SchemaDescription(SP_API_HEADERS)]
    [JsonComoTexto]
    [Contenido]
    property Headers: string read FHeaders write FHeaders;
    [SchemaDescription(SP_API_BODY)]
    [Contenido]
    property Body: string read FBody write FBody;
    [SchemaDescription(SP_API_FORM)]
    [JsonComoTexto]
    [Contenido]
    property Form: string read FForm write FForm;
    // un FICHERO de la jaula, como el out= de delphi_adb: lo coloca EL
    // escritor (ColocaContenido)
    [SchemaDescription(SP_API_OUT)]
    [RutaDelServidor]
    property Out: string read FOut write FOut;
  end;

  TDelphiApiTool = class(TMCPToolBase<TDelphiApiParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiApiParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  System.JSON, System.StrUtils, System.NetEncoding,
  MCPServer.Registration,
  Lsp.Pascal, // SinMayusculas
  Lsp.Json, // ListaJson, ValorJson, TextoDeValor
  Lsp.Guard, // ParametroQueNoVa: lo que no es del comando se dice
  Lsp.Puertas, // ColocacionDenegada, ColocaContenido: EL escritor de un out=
  Lsp.Codificacion, // CodecDeCharset, DecodeBytes, HayByteAlto: los codecs de la casa
  Lsp.Deteccion, // DetectEnc: si unos bytes son UTF-8 lo dice EL detector
  Lsp.Listas, // PrincipioDeTexto: el corte que no parte un par
  Lsp.Conexiones,
  Lsp.ClienteHttp;

const
  // lo que cabe del cuerpo en una respuesta (caracteres), como en delphi_db
  PRESUPUESTO_CUERPO_API = 60000;
  CABECERA_TIPO = 'Content-Type';
  TIPO_JSON = 'application/json';
  TIPO_TEXTO = 'text/plain; charset=utf-8';
  TIPO_FORMULARIO = 'application/x-www-form-urlencoded';

{ Los pares de una lista de objetos con name y value (query, headers, form); la
  negativa si no lo es o a una entrada le falta el name. }
function ParesDe(const ATexto, AQue: string; out APares: TArray<TNombreValor>): string;
var
  Lista: TJSONArray;
  P: TNombreValor;
begin
  Result := '';
  APares := [];
  if ATexto.Trim = '' then
    Exit;
  Lista := ListaJson(ATexto);
  if Lista = nil then
    Exit(MsgFmt(SR_API_LISTA_FMT, [AQue]));
  try
    for var V in Lista do
    begin
      if not (V is TJSONObject) then
        Exit(MsgFmt(SR_API_LISTA_FMT, [AQue]));
      P := NombreValor(TextoDeValor(TJSONObject(V).GetValue('name')).Trim,
        TextoDeValor(TJSONObject(V).GetValue('value')));
      if P.Nombre = '' then
        Exit(MsgFmt(SR_API_LISTA_FMT, [AQue]));
      APares := APares + [P];
    end;
  finally
    Lista.Free;
  end;
end;

{ Si ATexto lleva un caracter de control (el tabulador, solo si se admite). }
function TieneControl(const ATexto: string; AAdmiteTab: Boolean): Boolean;
begin
  for var Ch in ATexto do
    if ((Ch < ' ') and not (AAdmiteTab and (Ch = #9))) or (Ch = #127) then
      Exit(True);
  Result := False;
end;

{ La ruta de la peticion: APath (texto del agente) codificada por segmentos
  con el juez de la RTL (TNetEncoding.URL.EncodePath, que respeta un %XX que
  ya viene), o False si sale de la API: un esquema, un host, ? o #, una barra
  invertida, un control, o un segmento que DECODIFICADO es . o .. o lleva una
  barra (un %2e%2e pasaria la codificacion y el servidor lo leeria como ..).
  Vacia = la URL base tal cual. }
function RutaDePeticion(const APath: string; out ARuta: string): Boolean;
var
  Seg: string;
begin
  Result := False;
  ARuta := '';
  if APath.Trim = '' then
    Exit(True);
  if APath.Contains('://') or APath.StartsWith('//') or (APath.IndexOfAny(['?', '#', '\']) >= 0) or
     TieneControl(APath, False) then
    Exit;
  for var S in APath.Split(['/']) do
  begin
    Seg := TNetEncoding.URL.URLDecode(S);
    if (Seg = '.') or (Seg = '..') or (Seg.IndexOfAny(['/', '\']) >= 0) or TieneControl(Seg, False) then
      Exit;
  end;
  ARuta := TNetEncoding.URL.EncodePath(APath);
  Result := True;
end;

{ Los pares como query (o cuerpo de formulario), cada nombre y valor
  codificado por la RTL (EncodeForm). }
function QueryDe(const APares: TArray<TNombreValor>): string;
begin
  Result := '';
  for var P in APares do
    Result := Result + IfThen(Result <> '', '&') + TNetEncoding.URL.EncodeForm(P.Nombre) + '=' +
      TNetEncoding.URL.EncodeForm(P.Valor);
end;

{ '' si el agente puede poner la cabecera A; si no, la negativa: un nombre o
  un valor que inyectaria otra cabecera, o una que pone el transporte o la
  conexion (sus fijas y las de su credencial). }
function CabeceraDelAgente(const C: TConexionApi; const A: TNombreValor): string;
begin
  if (A.Nombre.IndexOfAny([':', ' ']) >= 0) or TieneControl(A.Nombre, False) or TieneControl(A.Valor, True) then
    Exit(MsgFmt(SR_API_CABECERA_FMT, [A.Nombre, MsgText(SF_API_CABECERA_MAL)]));
  Result := MsgFmt(SR_API_CABECERA_FMT, [A.Nombre, MsgText(SF_API_CABECERA_DEL_OPERADOR)]);
  if MatchText(A.Nombre, CABECERAS_DEL_TRANSPORTE) then
    Exit;
  for var F in CabecerasDeLaConexion(C) do
    if SameText(F.Nombre, A.Nombre) then
      Exit;
  Result := '';
end;

{ El cuerpo como texto, si lo es: con el charset que declara su tipo (su
  codec, el de la casa: CodecDeCharset), o como lo lee EL detector si es
  UTF-8 (con o sin BOM), UTF-16/32 con BOM, o ASCII; sin charset, unos bytes
  con un nulo o que no son UTF-8 son binarios (un JSON es UTF-8, RFC 8259).
  False = binario. }
function TextoDelCuerpo(const ABytes: TArray<Byte>; const ATipo: string; out ATexto: string): Boolean;
var
  Charset: string;
  Enc: TEncoding;
  K: TEncKind;
  P: Integer;
begin
  ATexto := '';
  if Length(ABytes) = 0 then
    Exit(True);
  P := Pos('charset=', SinMayusculas(ATipo));
  if P > 0 then
  begin
    Charset := Copy(ATipo, P + Length('charset='), MaxInt);
    P := Pos(';', Charset);
    if P > 0 then
      Charset := Copy(Charset, 1, P - 1);
    // un charset que no conocen ni Windows ni la RTL: lo dicen los bytes
    Enc := CodecDeCharset(Charset.Trim([' ', '"', '''']));
    if Enc <> nil then
    begin
      // el codec es nuevo y es de quien lo pide: se perdia uno por respuesta
      // con charset (CH10 del revisor de la 1.29)
      try
        ATexto := Enc.GetString(ABytes);
      finally
        Enc.Free;
      end;
      Exit(True);
    end;
  end;
  K := DetectEnc(ABytes);
  if not (K in [ekUtf8Bom, ekUtf8, ekAnsi]) then
  begin
    // UTF-16 o UTF-32: solo con su BOM, que es como los da el detector
    ATexto := DecodeBytes(ABytes, K);
    Exit(True);
  end;
  for var B in ABytes do
    if B = 0 then
      Exit(False);
  // ANSI con un byte alto: no es UTF-8, y sin charset no hay pagina que valga
  Result := (K <> ekAnsi) or not HayByteAlto(ABytes);
  if Result then
    ATexto := DecodeBytes(ABytes, K);
end;

{ Las cabeceras de la respuesta como objeto (una repetida, unida por comas),
  con la direccion y la credencial de la conexion tapadas (un Location). }
function CabecerasEnJson(const C: TConexionApi; const ACabs: TArray<TNombreValor>): TJSONObject;
var
  Nombres, Valores: TArray<string>;
  I: Integer;
begin
  Nombres := [];
  Valores := [];
  for var H in ACabs do
  begin
    I := IndexText(H.Nombre, Nombres);
    if I < 0 then
    begin
      Nombres := Nombres + [H.Nombre];
      Valores := Valores + [EnmascaraApi(H.Valor, C, True)];
    end
    else
      Valores[I] := Valores[I] + ', ' + EnmascaraApi(H.Valor, C, True);
  end;
  Result := TJSONObject.Create;
  for I := 0 to High(Nombres) do
    Result.AddPair(Nombres[I], Valores[I]);
end;

function Connections: string;
var
  Neg: string;
  Lista: TArray<TConexionApi>;
  R: TJSONObject;
  Apis, Inutiles: TJSONArray;
begin
  Lista := ConexionesApiDeLaSesion(Neg);
  if Neg <> '' then
    Exit(Neg);
  R := TJSONObject.Create;
  try
    R.AddPair('note', MsgText(SN_API_CONNECTIONS));
    Apis := TJSONArray.Create;
    R.AddPair('apis', Apis);
    Inutiles := nil;
    for var C in Lista do
      if C.Defecto = '' then
      begin
        var A := TJSONObject.Create;
        Apis.AddElement(A);
        A.AddPair('api', NombreDeConexion(C));
        var M := TJSONArray.Create;
        A.AddPair('methods', M);
        for var X in C.Metodos do
          M.Add(X);
      end
      else
      begin
        if Inutiles = nil then
        begin
          Inutiles := TJSONArray.Create;
          R.AddPair('unusable', Inutiles);
        end;
        var U := TJSONObject.Create;
        Inutiles.AddElement(U);
        U.AddPair('api', NombreDeConexion(C));
        U.AddPair('why', C.Defecto);
      end;
    Result := R.ToJSON;
  finally
    R.Free;
  end;
end;

function Request(const P: TDelphiApiParams): string;
var
  C: TConexionApi;
  Neg, Metodo, Ruta, QA, Url, Tipo, Texto, Tapado, PinVisto, Detalle, Nombre: string;
  Query, Cabs, Form: TArray<TNombreValor>;
  Cuerpo: TArray<Byte>;
  Resp: TRespuestaHttp;
  Fallo: TFalloHttp;
  EsTexto, HayTipo, Recortado: Boolean;
  R: TJSONObject;
  V: TJSONValue;
begin
  if P.Api.Trim = '' then
    Exit(MsgFmt(SR_API_FALTA_FMT, ['request', 'api']));
  if not ConexionApiDeLaSesion(P.Api, C, Neg) then
    Exit(Neg);
  Nombre := NombreDeConexion(C);
  if C.Defecto <> '' then
    Exit(MsgFmt(SR_API_INUTILIZABLE_FMT, [Nombre, C.Defecto]));
  Metodo := MetodoDePeticion(P.Method);
  if not MatchStr(Metodo, C.Metodos) then
    Exit(MsgFmt(SR_API_METODO_FMT, [Metodo, Nombre, string.Join(', ', C.Metodos)]));
  if not RutaDePeticion(P.Path, Ruta) then
    Exit(MsgFmt(SR_API_RUTA_FMT, [P.Path]));
  Result := ParesDe(P.Query, 'query', Query);
  if Result <> '' then
    Exit;
  Result := ParesDe(P.Headers, 'headers', Cabs);
  if Result <> '' then
    Exit;
  Result := ParesDe(P.Form, 'form', Form);
  if Result <> '' then
    Exit;
  if (P.Body <> '') and (Length(Form) > 0) then
    Exit(MsgText(SR_API_CUERPO_Y_FORM));
  // el tipo del cuerpo, si ya lo pone alguien (el agente o la conexion): uno
  HayTipo := False;
  for var F in CabecerasDeLaConexion(C) do
    HayTipo := HayTipo or SameText(F.Nombre, CABECERA_TIPO);
  for var A in Cabs do
  begin
    Result := CabeceraDelAgente(C, A);
    if Result <> '' then
      Exit;
    HayTipo := HayTipo or SameText(A.Nombre, CABECERA_TIPO);
  end;
  // out= se juzga ANTES de llamar: lo que el escritor negaria al colocar
  if P.Out.Trim <> '' then
  begin
    Result := ColocacionDenegada(P.Out.Trim);
    if Result <> '' then
      Exit;
  end;
  Cuerpo := [];
  if Length(Form) > 0 then
  begin
    Cuerpo := TEncoding.UTF8.GetBytes(QueryDe(Form));
    if not HayTipo then
      Cabs := Cabs + [NombreValor(CABECERA_TIPO, TIPO_FORMULARIO)];
  end
  else if P.Body <> '' then
  begin
    Cuerpo := TEncoding.UTF8.GetBytes(P.Body);
    if not HayTipo then
    begin
      V := ValorJson(P.Body);
      if V <> nil then
        Cabs := Cabs + [NombreValor(CABECERA_TIPO, TIPO_JSON)]
      else
        Cabs := Cabs + [NombreValor(CABECERA_TIPO, TIPO_TEXTO)];
      V.Free;
    end;
  end;
  // la query del agente es lo que se le ensena; la de la credencial va solo
  // en la URL
  QA := QueryDe(Query);
  Url := C.UrlBase + Ruta;
  if Length(Query) + Length(QueryDeLaConexion(C)) > 0 then
    Url := Url + '?' + QueryDe(Query + QueryDeLaConexion(C));
  if not PeticionHttp(C, Metodo, Url, CabecerasDeLaConexion(C) + Cabs, Cuerpo, Resp, Fallo, Detalle,
    PinVisto) then
    case Fallo of
      fhCertificado:
        Exit(MsgFmt(SR_API_CERTIFICADO_FMT, [Nombre, PinVisto]));
      fhPin:
        Exit(MsgFmt(SR_API_PIN_FMT, [Nombre, IfThen(PinVisto <> '', PinVisto, MsgText(SF_API_PIN_NO_VISTO))]));
      fhPlazo:
        Exit(MsgFmt(SR_API_NO_RESPONDE_FMT, [Nombre, MsgFmt(SF_API_PLAZO_FMT, [C.Plazo])]));
      fhInterno:
        // 'Clase: mensaje' (Lsp.ClienteHttp): el criterio de toda excepcion inesperada
        Exit(MsgExcepcion(Copy(Detalle, 1, Pos(': ', Detalle) - 1),
          EnmascaraApi(Copy(Detalle, Pos(': ', Detalle) + 2, MaxInt), C, True)));
    else
      Exit(MsgFmt(SR_API_NO_RESPONDE_FMT, [Nombre, EnmascaraApi(Detalle.Trim.TrimRight(['.']), C, True)]));
    end;
  Tipo := '';
  for var H in Resp.Cabeceras do
    if SameText(H.Nombre, CABECERA_TIPO) then
      Tipo := H.Valor;
  EsTexto := TextoDelCuerpo(Resp.Cuerpo, Tipo, Texto);
  Tapado := EnmascaraApi(Texto, C, False);
  if P.Out.Trim <> '' then
  try
    // lo que se guarda tampoco lleva la credencial: si el texto la traia, va
    // el texto tapado en UTF-8; si no, los bytes tal cual
    if EsTexto and (Tapado <> Texto) then
      ColocaContenido(P.Out.Trim, TEncoding.UTF8.GetBytes(Tapado))
    else
      ColocaContenido(P.Out.Trim, Resp.Cuerpo);
  except
    on E: Exception do
      Exit(MsgExcepcion(E.ClassName, E.Message));
  end;
  Recortado := Resp.Recortado;
  R := TJSONObject.Create;
  try
    R.AddPair('api', Nombre);
    R.AddPair('method', Metodo);
    R.AddPair('path', Ruta + IfThen(QA <> '', '?' + QA));
    R.AddPair('status', TJSONNumber.Create(Resp.Estado));
    R.AddPair('statusText', EnmascaraApi(Resp.TextoDeEstado, C, True));
    R.AddPair('ms', TJSONNumber.Create(Resp.Milisegundos));
    R.AddPair('headers', CabecerasEnJson(C, Resp.Cabeceras));
    R.AddPair('bytes', TJSONNumber.Create(Length(Resp.Cuerpo)));
    if not EsTexto then
      R.AddPair('note', MsgFmt(SN_API_BINARIO_FMT, [Length(Resp.Cuerpo), Tipo]))
    else if Length(Tapado) > PRESUPUESTO_CUERPO_API then
    begin
      Recortado := True;
      R.AddPair('body', PrincipioDeTexto(Tapado, PRESUPUESTO_CUERPO_API));
    end
    else
    begin
      V := nil;
      if SinMayusculas(Tipo).Contains('json') then
        V := ValorJson(Tapado);
      if V <> nil then
        R.AddPair('body', V)
      else if Tapado <> '' then
        R.AddPair('body', Tapado);
    end;
    if Recortado then
    begin
      R.AddPair('truncated', TJSONBool.Create(True));
      // un binario ya lleva su nota, que dice lo mismo: out= lo guarda
      if EsTexto then
        R.AddPair('note', MsgText(SN_API_RECORTADO));
    end;
    if P.Out.Trim <> '' then
      R.AddPair('out', P.Out.Trim);
    Result := R.ToJSON;
  finally
    R.Free;
  end;
end;

{ TDelphiApiTool }

constructor TDelphiApiTool.Create;
begin
  inherited;
  FName := 'delphi_api';
  FDescription := SD_API;
end;

function TDelphiApiTool.ExecuteWithParams(const Params: TDelphiApiParams): string;
var
  Cmd, Suyos, VaCon, Sobra: string;
begin
  Cmd := SinMayusculas(Params.Command.Trim);
  if Cmd = '' then
    Cmd := 'connections';
  // lo que no es del comando se dice (Lsp.Guard.ParametroQueNoVa)
  Sobra := ParametroQueNoVa(Cmd, [
      'connections', '',
      'request', 'api method path query headers body form out'],
    ['api', Params.Api, '', 'method', Params.Method, '', 'path', Params.Path, '',
     'query', Params.Query, '', 'headers', Params.Headers, '', 'body', Params.Body, '',
     'form', Params.Form, '', 'out', Params.Out, ''], Suyos, VaCon);
  if Sobra <> '' then
    Exit(MsgFmt(SR_API_NO_VA_CON_COMANDO_FMT, [Sobra, Cmd, Cmd, Suyos]) + VaCon);
  case IndexText(Cmd, ['connections', 'request']) of
    0: Result := Connections;
    1: Result := Request(Params);
  else
    Result := MsgText(SR_API_COMANDO);
  end;
end;

initialization
  TMCPRegistry.RegisterTool('delphi_api',
    function: IMCPTool begin Result := TDelphiApiTool.Create; end);

end.
