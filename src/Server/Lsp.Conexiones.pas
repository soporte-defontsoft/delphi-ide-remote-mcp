unit Lsp.Conexiones;

{ LAS BASES DE DATOS CON NOMBRE (1.29, delphi_db): el lector de las que
  define el operador en el fichero de conexiones de la casa
  (FicheroDeConexiones, Lsp.Casa) y que abre a cada workspace con
  DbAllowedProjects= (ProyectosDeConexionDeLaSesion, Lsp.Settings). UN
  lector, como settings.ini tiene el suyo: lleva credenciales, no es lugar
  de ninguna puerta y el agente no lo ve. Se lee en cada llamada: lo que el
  operador cambia vale sin reiniciar.

  El agente nombra una base por <proyecto>/<alias> (NombreDeConexion: EL
  nombrador; se busca por el nombre compuesto, sin trocear el del agente) y
  ve su motor y si es de solo lectura; nunca el servidor, la base real, el
  usuario, el puerto ni la contrasena, que EnmascaraConexion cambia por el
  nombre en lo que vuelve de la base.

  Lo decidido por David (5 y 6-nov-2026): las credenciales en claro en el
  servidor; se conecta SOLO con lo que dice el json; escribir o no lo dice
  el "readonly" del json, no los permisos del login. Sin "readonly", o con
  algo que no es true/false, la entrada no se usa (falla cerrado).

  LAS APIS CON NOMBRE (1.29, delphi_api): el mismo lector y el mismo
  recorrido (RecorreConexiones) sobre su propio fichero, abierto a cada
  workspace con ApiAllowedProjects=. El agente ve <proyecto>/<alias> y sus
  metodos; la URL base, la credencial y el pin se quedan con el operador, y
  EnmascaraApi los tapa en lo que vuelve. Sin "methods" la entrada no se usa
  (falla cerrado, como sin "readonly"). }

interface

type
  TConexionDb = record
    Proyecto: string;     // la clave del proyecto en el json
    Alias: string;        // la clave de la base dentro de su proyecto
    Motor: string;        // "engine": el DriverID de FireDAC (MSSQL, PG...)
    SoloLectura: Boolean; // "readonly"
    Servidor: string;     // "server"
    Base: string;         // "database": la base REAL
    Usuario: string;      // "user"
    Clave: string;        // "password"
    Puerto: string;       // "port"
    Defecto: string;      // por que no se puede usar tal como esta ('' = se puede)
  end;

  TNombreValor = record
    Nombre: string;
    Valor: string;
  end;

  { Una credencial de una API: basic (Usuario, Clave), bearer (Valor = el
    token), header o query (Nombre, Valor = la clave). }
  TAutenticacionApi = record
    Tipo: string;
    Usuario: string;
    Clave: string;
    Nombre: string;
    Valor: string;
  end;

  TConexionApi = record
    Proyecto: string;
    Alias: string;
    UrlBase: string;                     // "baseUrl", sin la barra final
    Auth: TArray<TAutenticacionApi>;     // "auth": un objeto o una lista
    Cabeceras: TArray<TNombreValor>;     // "headers": las fijas del operador
    Pin: string;                         // "pin": sha256/<base64 del SPKI>
    Metodos: TArray<string>;             // "methods", en mayusculas
    Plazo: Integer;                      // "timeout", en segundos
    Defecto: string;
  end;

const
  // los metodos que una API puede declarar; los tres primeros LEEN
  METODOS_HTTP: array [0 .. 6] of string = ('GET', 'HEAD', 'OPTIONS', 'POST', 'PUT', 'PATCH',
    'DELETE');

{ <proyecto>/<alias>: EL nombre de una base o una API para el agente. }
function NombreDeConexion(const AConexion: TConexionDb): string; overload;
function NombreDeConexion(const AConexion: TConexionApi): string; overload;

{ Las bases de los proyectos que ESTA sesion puede usar, en el orden del
  json, con su Defecto si lo tienen. ANegativa (un SR_DB_*) si el workspace
  no tiene proyectos o el fichero no se lee; un proyecto declarado que no
  esta en el json no da nada (su nombre es del operador). }
function ConexionesDbDeLaSesion(out ANegativa: string): TArray<TConexionDb>;

{ La base que nombra ANombre, de ESTA sesion; False con ANegativa: la del
  fichero, la de un workspace sin proyectos, o DB-003, la misma para una que
  no existe que para una de otro workspace. Una con Defecto se devuelve:
  quien la use dice DB-004. }
function ConexionDbDeLaSesion(const ANombre: string; out AConexion: TConexionDb;
  out ANegativa: string): Boolean;

{ ATexto con lo que el json sabe y el agente no (servidor, base real,
  usuario, puerto, contrasena) cambiado por <nombre de la conexion>: lo que
  vuelve de la base. Un error de FireDAC trae el usuario, y en PG el host y
  el puerto (medido el 6-nov-2026); y cualquier direccion IP: la que
  resolvio libpq para un servidor dado por nombre y la de este servidor
  (TapaDireccionesIp, 7-nov). }
function EnmascaraConexion(const ATexto: string; const AConexion: TConexionDb): string;

{ Las APIs de los proyectos que ESTA sesion puede usar, como las bases; la
  negativa, un SR_API_*. }
function ConexionesApiDeLaSesion(out ANegativa: string): TArray<TConexionApi>;
function ConexionApiDeLaSesion(const ANombre: string; out AConexion: TConexionApi;
  out ANegativa: string): Boolean;

{ ATexto con las credenciales de la API (contrasena, token, clave y el
  basic codificado) cambiadas por <nombre>; con ADireccion, tambien la URL
  base, su host, su puerto y el usuario: un error del cliente o una
  cabecera Location. Un cuerpo, solo las credenciales (un 8089 o un nombre
  en los datos son datos). }
function EnmascaraApi(const ATexto: string; const AConexion: TConexionApi; ADireccion: Boolean): string;

{ EL valor de la cabecera Authorization de una credencial basic: lo compone
  quien la envia y lo tapa el enmascarador. }
function CredencialBasica(const A: TAutenticacionApi): string;

{ El metodo de una peticion: el dado en mayusculas, GET si no hay. Y si
  LEE (GET, HEAD, OPTIONS): lo pregunta la puerta de solo lectura. }
function MetodoDePeticion(const AMetodo: string): string;
function MetodoQueLee(const AMetodo: string): Boolean;

{ Un par nombre/valor. }
function NombreValor(const ANombre, AValor: string): TNombreValor;

{ Lo que la conexion pone en cada peticion y el agente no: sus cabeceras
  fijas y las de su credencial (Authorization: Basic o Bearer, o la cabecera
  de su clave); y los pares de query de una clave por query. }
function CabecerasDeLaConexion(const AConexion: TConexionApi): TArray<TNombreValor>;
function QueryDeLaConexion(const AConexion: TConexionApi): TArray<TNombreValor>;

{ EL pin de una clave publica: sha256/ y el base64 del SHA-256 de su
  SubjectPublicKeyInfo en DER (el formato de --pinnedpubkey). Lo compone el
  transporte con el certificado de la conexion (Lsp.ClienteHttp) y lo lee
  el lector del json. }
function PinDeSpki(const ADer: TArray<Byte>): string;

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON, System.StrUtils, System.NetEncoding, System.Character,
  Lsp.ShaCache, // Sha256CrudoDeBytes: el SHA-256, en su casa
  System.Net.URLClient, // TURI: el juez de una URL base
  Lsp.Texts, Lsp.Casa, Lsp.Settings, Lsp.Json,
  Lsp.Pascal, // SinMayusculas
  Lsp.Codificacion, // BomUtf8En: el BOM lo lee el de la casa
  Winapi.Winsock2; // inet_pton: el juez de que es una direccion IP

const
  // el proveedor por el que conecta el servidor; ausente = este
  PROVEEDOR_FIREDAC = 'FIREDAC';
  SEPARADOR_DE_NOMBRE = '/';
  // una contrasena de al menos tanto se tapa donde aparezca; una mas corta,
  // solo como palabra entera (una 'x' no se come el texto)
  CLAVE_LARGA = 6;
  // cada fichero, su raiz y el grupo de cada proyecto (False = bases, True = APIs)
  RAIZ_DE_CONEXIONES: array [Boolean] of string = ('db-connections', 'api-connections');
  GRUPO_DE_CONEXIONES: array [Boolean] of string = ('databases', 'apis');
  PLAZO_API_POR_DEFECTO = 30;
  PLAZO_API_MAXIMO = 300;
  PREFIJO_PIN = 'sha256/';
  BYTES_DEL_PIN = 32;
  // los tipos de credencial del json
  AUTH_BASIC = 'basic';
  AUTH_BEARER = 'bearer';
  AUTH_HEADER = 'header';
  AUTH_QUERY = 'query';
  AUTH_NINGUNA = 'none';
  CABECERA_AUTORIZACION = 'Authorization';

function NombreCompuesto(const AProyecto, AAlias: string): string;
begin
  Result := AProyecto + SEPARADOR_DE_NOMBRE + AAlias;
end;

function NombreDeConexion(const AConexion: TConexionDb): string;
begin
  Result := NombreCompuesto(AConexion.Proyecto, AConexion.Alias);
end;

function NombreDeConexion(const AConexion: TConexionApi): string;
begin
  Result := NombreCompuesto(AConexion.Proyecto, AConexion.Alias);
end;

{ La negativa de un fichero de conexiones que no se lee: el de APIs con AApi. }
function NegativaDelFichero(AApi: Boolean; const APorque: string): string;
begin
  if AApi then
    Result := MsgFmt(SR_API_FICHERO_FMT, [APorque])
  else
    Result := MsgFmt(SR_DB_FICHERO_FMT, [APorque]);
end;

{ El texto del fichero de conexiones (el de APIs con AApi), o la negativa.
  Su lector y no una puerta: lleva credenciales y no es lugar de ninguna,
  como settings.ini. UTF-8 con o sin BOM. }
function TextoDeConexiones(AApi: Boolean; out ATexto, ANegativa: string): Boolean;
var
  Ruta, Motivo: string;
  B: TBytes;
  Ini: Integer;
begin
  ATexto := '';
  ANegativa := '';
  Ruta := FicheroDeConexiones(AApi);
  if not TFile.Exists(Ruta) then
  begin
    ANegativa := NegativaDelFichero(AApi, MsgText(SF_CONEXIONES_NO_HAY));
    Exit(False);
  end;
  // EL lector de la configuracion del servidor: ReadAllBytes negaba la
  // escritura a otro y, con el fichero abierto en un editor, subia una
  // excepcion (CH9 del revisor del paisaje de la 1.29)
  if not BytesDelIni(Ruta, B, Motivo) then
  begin
    ANegativa := NegativaDelFichero(AApi, Motivo);
    Exit(False);
  end;
  Ini := 0;
  if BomUtf8En(B, 0) then
    Ini := 3;
  ATexto := TEncoding.UTF8.GetString(B, Ini, Length(B) - Ini);
  Result := True;
end;

{ El valor de AClave como texto (Lsp.Json.TextoDeValor: "port": 5432 vale
  como lo escribe el JSON); '' si no esta. }
function Campo(const AObj: TJSONObject; const AClave: string): string;
begin
  Result := TextoDeValor(AObj.GetValue(AClave));
end;

function ConexionDe(const AProyecto, AAlias: string; const AObj: TJSONObject): TConexionDb;
var
  Ro: TJSONValue;
  Prov: string;
begin
  Result := Default(TConexionDb);
  Result.Proyecto := AProyecto;
  Result.Alias := AAlias;
  Result.SoloLectura := True; // falla cerrado
  if AObj = nil then
  begin
    Result.Defecto := MsgText(SF_DB_DEF_SIN_MOTOR);
    Exit;
  end;
  Result.Motor := Campo(AObj, 'engine').Trim;
  Result.Servidor := Campo(AObj, 'server').Trim;
  Result.Base := Campo(AObj, 'database').Trim;
  Result.Usuario := Campo(AObj, 'user');
  Result.Clave := Campo(AObj, 'password');
  Result.Puerto := Campo(AObj, 'port').Trim;
  Prov := Campo(AObj, 'provider').Trim;
  Ro := AObj.GetValue('readonly');
  if Ro is TJSONBool then
    Result.SoloLectura := TJSONBool(Ro).AsBoolean
  else
    Result.Defecto := MsgText(SF_DB_DEF_SOLO_LECTURA);
  if Result.Motor = '' then
    Result.Defecto := MsgText(SF_DB_DEF_SIN_MOTOR)
  else if (Prov <> '') and not SameText(Prov, PROVEEDOR_FIREDAC) then
    Result.Defecto := MsgFmt(SF_DB_DEF_PROVEEDOR_FMT, [Prov]);
end;

{ El objeto AClave de AObj, o nil si no esta o no es un objeto. }
function ObjetoDe(const AObj: TJSONObject; const AClave: string): TJSONObject;
var
  V: TJSONValue;
begin
  Result := nil;
  if AObj = nil then
    Exit;
  V := AObj.GetValue(AClave);
  if V is TJSONObject then
    Result := TJSONObject(V);
end;

type
  TCadaConexion = reference to procedure(const AProyecto, AAlias: string; AObj: TJSONObject);

{ EL recorrido de un fichero de conexiones (el de APIs con AApi): cada
  entrada de los proyectos que ESTA sesion puede usar, en el orden del json,
  con su objeto (nil si no lo es). '' o la negativa: un workspace sin
  proyectos, un fichero que no se lee. Un proyecto declarado que no esta en
  el json no da nada (su nombre es del operador). }
function RecorreConexiones(AApi: Boolean; const ACada: TCadaConexion): string;
var
  Proyectos: TArray<string>;
  Texto: string;
  Raiz, Lista, Grupo: TJSONObject;
  P, B: TJSONPair;
begin
  Result := '';
  Proyectos := ProyectosDeConexionDeLaSesion(AApi);
  if Length(Proyectos) = 0 then
  begin
    if AApi then
      Exit(MsgText(SR_API_SIN_PROYECTOS));
    Exit(MsgText(SR_DB_SIN_PROYECTOS));
  end;
  if not TextoDeConexiones(AApi, Texto, Result) then
    Exit;
  Raiz := ObjetoJson(Texto);
  if Raiz = nil then
    Exit(NegativaDelFichero(AApi, MsgText(SF_CONEXIONES_NO_JSON)));
  try
    Lista := ObjetoDe(ObjetoDe(Raiz, RAIZ_DE_CONEXIONES[AApi]), 'projects');
    if Lista = nil then
      Exit(NegativaDelFichero(AApi, MsgFmt(SF_CONEXIONES_SIN_RAIZ_FMT, [RAIZ_DE_CONEXIONES[AApi]])));
    for P in Lista do
    begin
      if not NombreEnLaLista(P.JsonString.Value, Proyectos) or not (P.JsonValue is TJSONObject) then
        Continue;
      Grupo := ObjetoDe(TJSONObject(P.JsonValue), GRUPO_DE_CONEXIONES[AApi]);
      if Grupo = nil then
        Continue;
      for B in Grupo do
        if B.JsonValue is TJSONObject then
          ACada(P.JsonString.Value, B.JsonString.Value, TJSONObject(B.JsonValue))
        else
          ACada(P.JsonString.Value, B.JsonString.Value, nil);
    end;
  finally
    Raiz.Free;
  end;
end;

{ La posicion de ANombre (como lo da el agente) entre ANombres, o -1: EL
  lector del nombre de una conexion, el inverso de NombreCompuesto. }
function PosicionDelNombre(const ANombres: TArray<string>; const ANombre: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(ANombres) do
    if SameText(ANombres[I], ANombre.Trim) then
      Exit(I);
  Result := -1;
end;

function ConexionesDbDeLaSesion(out ANegativa: string): TArray<TConexionDb>;
var
  L: TArray<TConexionDb>;
begin
  L := [];
  ANegativa := RecorreConexiones(False,
    procedure(const AProyecto, AAlias: string; AObj: TJSONObject)
    begin
      L := L + [ConexionDe(AProyecto, AAlias, AObj)];
    end);
  Result := L;
end;

function ConexionDbDeLaSesion(const ANombre: string; out AConexion: TConexionDb;
  out ANegativa: string): Boolean;
var
  L: TArray<TConexionDb>;
  Nombres: TArray<string>;
  I: Integer;
begin
  AConexion := Default(TConexionDb);
  L := ConexionesDbDeLaSesion(ANegativa);
  Nombres := [];
  for var C in L do
    Nombres := Nombres + [NombreDeConexion(C)];
  I := PosicionDelNombre(Nombres, ANombre);
  Result := I >= 0;
  if Result then
    AConexion := L[I]
  else if ANegativa = '' then
    ANegativa := MsgFmt(SR_DB_DESCONOCIDA_FMT, [ANombre.Trim]);
end;

{ ATexto como URL base de una API (http o https, con su host, sin ? ni #) y
  sin sus barras finales en AUrl; False si no lo es. El juez de la URL, TURI. }
function UrlBaseDe(const ATexto: string; out AUrl: string): Boolean;
var
  U: TURI;
begin
  Result := False;
  AUrl := ATexto.Trim;
  while AUrl.EndsWith('/') do
    AUrl := AUrl.Remove(AUrl.Length - 1);
  if (AUrl = '') or (AUrl.IndexOfAny(['?', '#']) >= 0) then
    Exit;
  try
    U := TURI.Create(AUrl);
  except
    on ENetURIException do
      Exit;
  end;
  Result := MatchText(U.Scheme, [TURI.SCHEME_HTTP, TURI.SCHEME_HTTPS]) and (U.Host <> '');
end;

{ APin como pin SPKI: sha256/ y el base64 de 32 bytes, de ida y vuelta (el
  decodificador se salta lo que no es base64). }
function PinValido(const APin: string): Boolean;
var
  B64: string;
  Bytes: TBytes;
begin
  Result := False;
  if not APin.StartsWith(PREFIJO_PIN) then
    Exit;
  B64 := APin.Substring(Length(PREFIJO_PIN));
  Bytes := TNetEncoding.Base64String.DecodeStringToBytes(B64);
  Result := (Length(Bytes) = BYTES_DEL_PIN) and (TNetEncoding.Base64String.EncodeBytesToString(Bytes) = B64);
end;

{ Una credencial del json: basic (user, password), bearer (token), header o
  query (name, value); False si le falta lo suyo o el tipo no es ninguno. }
function AutenticacionDe(const AObj: TJSONObject; out A: TAutenticacionApi): Boolean;
begin
  A := Default(TAutenticacionApi);
  A.Tipo := SinMayusculas(Campo(AObj, 'type').Trim);
  A.Usuario := Campo(AObj, 'user');
  A.Clave := Campo(AObj, 'password');
  A.Nombre := Campo(AObj, 'name').Trim;
  if A.Tipo = AUTH_BEARER then
    A.Valor := Campo(AObj, 'token')
  else
    A.Valor := Campo(AObj, 'value');
  case IndexStr(A.Tipo, [AUTH_BASIC, AUTH_BEARER, AUTH_HEADER, AUTH_QUERY]) of
    0: Result := A.Usuario <> '';
    1: Result := A.Valor <> '';
    2, 3: Result := (A.Nombre <> '') and (A.Valor <> '');
  else
    Result := False;
  end;
end;

{ Una API del json, con su Defecto si no se puede usar: sin baseUrl valida,
  una credencial mal declarada, unas cabeceras que no son textos, un pin mal
  escrito, sin methods (falla cerrado) o un plazo fuera de 1..300 s. }
function ConexionApiDe(const AProyecto, AAlias: string; const AObj: TJSONObject): TConexionApi;
var
  V: TJSONValue;
  A: TAutenticacionApi;
  Url, Tipo, M: string;
  Auths: TArray<TJSONValue>;
  N: Integer;
begin
  Result := Default(TConexionApi);
  Result.Proyecto := AProyecto;
  Result.Alias := AAlias;
  Result.Plazo := PLAZO_API_POR_DEFECTO;
  if (AObj = nil) or not UrlBaseDe(Campo(AObj, 'baseUrl'), Url) then
  begin
    Result.Defecto := MsgText(SF_API_DEF_URL);
    Exit;
  end;
  Result.UrlBase := Url;
  // auth: un objeto o una lista de ellos (basic y una clave en cabecera, a la
  // vez); "none", o ninguno, sin credencial
  V := AObj.GetValue('auth');
  Auths := [];
  if V is TJSONArray then
  begin
    for var X in TJSONArray(V) do
      Auths := Auths + [X];
  end
  else if V <> nil then
    Auths := [V];
  for var X in Auths do
  begin
    Tipo := '';
    if X is TJSONObject then
      Tipo := SinMayusculas(Campo(TJSONObject(X), 'type').Trim);
    if Tipo = AUTH_NINGUNA then
      Continue;
    if not (X is TJSONObject) or not AutenticacionDe(TJSONObject(X), A) then
    begin
      Result.Defecto := MsgFmt(SF_API_DEF_AUTH_FMT, [Tipo]);
      Exit;
    end;
    Result.Auth := Result.Auth + [A];
  end;
  V := AObj.GetValue('headers');
  if V <> nil then
  begin
    if not (V is TJSONObject) then
    begin
      Result.Defecto := MsgText(SF_API_DEF_CABECERAS);
      Exit;
    end;
    for var P in TJSONObject(V) do
    begin
      if not (P.JsonValue is TJSONString) or (P.JsonString.Value.Trim = '') then
      begin
        Result.Defecto := MsgText(SF_API_DEF_CABECERAS);
        Exit;
      end;
      var C: TNombreValor;
      C.Nombre := P.JsonString.Value.Trim;
      C.Valor := TJSONString(P.JsonValue).Value;
      Result.Cabeceras := Result.Cabeceras + [C];
    end;
  end;
  Result.Pin := Campo(AObj, 'pin').Trim;
  if (Result.Pin <> '') and not PinValido(Result.Pin) then
  begin
    Result.Defecto := MsgText(SF_API_DEF_PIN);
    Exit;
  end;
  // un pin es de un certificado: sin TLS no hay ninguno que comprobar, y la
  // peticion salia en claro (con su credencial) antes de saberlo; la negativa
  // de despues decia que no se habia mandado nada (CH2 del revisor de la 1.29)
  if (Result.Pin <> '') and not SameText(TURI.Create(Result.UrlBase).Scheme, TURI.SCHEME_HTTPS) then
  begin
    Result.Defecto := MsgText(SF_API_DEF_PIN_SIN_TLS);
    Exit;
  end;
  V := AObj.GetValue('methods');
  if not (V is TJSONArray) or (TJSONArray(V).Count = 0) then
  begin
    Result.Defecto := MsgText(SF_API_DEF_METODOS);
    Exit;
  end;
  for var X in TJSONArray(V) do
  begin
    M := UpperCase(TextoDeValor(X).Trim);
    if not (X is TJSONString) or not MatchStr(M, METODOS_HTTP) then
    begin
      Result.Defecto := MsgText(SF_API_DEF_METODOS);
      Exit;
    end;
    if not MatchStr(M, Result.Metodos) then
      Result.Metodos := Result.Metodos + [M];
  end;
  V := AObj.GetValue('timeout');
  if V <> nil then
  begin
    if not (V is TJSONNumber) or not TryStrToInt(TJSONNumber(V).ToString, N) or (N < 1) or
       (N > PLAZO_API_MAXIMO) then
    begin
      Result.Defecto := MsgText(SF_API_DEF_PLAZO);
      Exit;
    end;
    Result.Plazo := N;
  end;
end;

function ConexionesApiDeLaSesion(out ANegativa: string): TArray<TConexionApi>;
var
  L: TArray<TConexionApi>;
begin
  L := [];
  ANegativa := RecorreConexiones(True,
    procedure(const AProyecto, AAlias: string; AObj: TJSONObject)
    begin
      L := L + [ConexionApiDe(AProyecto, AAlias, AObj)];
    end);
  Result := L;
end;

function ConexionApiDeLaSesion(const ANombre: string; out AConexion: TConexionApi;
  out ANegativa: string): Boolean;
var
  L: TArray<TConexionApi>;
  Nombres: TArray<string>;
  I: Integer;
begin
  AConexion := Default(TConexionApi);
  L := ConexionesApiDeLaSesion(ANegativa);
  Nombres := [];
  for var C in L do
    Nombres := Nombres + [NombreDeConexion(C)];
  I := PosicionDelNombre(Nombres, ANombre);
  Result := I >= 0;
  if Result then
    AConexion := L[I]
  else if ANegativa = '' then
    ANegativa := MsgFmt(SR_API_DESCONOCIDA_FMT, [ANombre.Trim]);
end;

function CredencialBasica(const A: TAutenticacionApi): string;
begin
  Result := TNetEncoding.Base64String.EncodeBytesToString(TEncoding.UTF8.GetBytes(A.Usuario + ':' + A.Clave));
end;

function NombreValor(const ANombre, AValor: string): TNombreValor;
begin
  Result.Nombre := ANombre;
  Result.Valor := AValor;
end;

function CabecerasDeLaConexion(const AConexion: TConexionApi): TArray<TNombreValor>;
begin
  Result := Copy(AConexion.Cabeceras);
  for var A in AConexion.Auth do
    case IndexStr(A.Tipo, [AUTH_BASIC, AUTH_BEARER, AUTH_HEADER]) of
      0: Result := Result + [NombreValor(CABECERA_AUTORIZACION, 'Basic ' + CredencialBasica(A))];
      1: Result := Result + [NombreValor(CABECERA_AUTORIZACION, 'Bearer ' + A.Valor)];
      2: Result := Result + [NombreValor(A.Nombre, A.Valor)];
    end;
end;

function QueryDeLaConexion(const AConexion: TConexionApi): TArray<TNombreValor>;
begin
  Result := [];
  for var A in AConexion.Auth do
    if A.Tipo = AUTH_QUERY then
      Result := Result + [NombreValor(A.Nombre, A.Valor)];
end;

function PinDeSpki(const ADer: TArray<Byte>): string;
begin
  Result := PREFIJO_PIN + TNetEncoding.Base64String.EncodeBytesToString(Sha256CrudoDeBytes(ADer));
end;

function MetodoDePeticion(const AMetodo: string): string;
begin
  Result := UpperCase(AMetodo.Trim);
  if Result = '' then
    Result := METODOS_HTTP[0];
end;

function MetodoQueLee(const AMetodo: string): Boolean;
var
  I: Integer;
begin
  // los tres primeros de METODOS_HTTP: GET, HEAD, OPTIONS
  I := IndexStr(MetodoDePeticion(AMetodo), METODOS_HTTP);
  Result := (I >= 0) and (I <= 2);
end;


{ Si C, pegado a una palabra del texto de un motor, la alarga: una letra o
  una cifra de cualquier alfabeto, la marca que acentua a la anterior, o
  '_'. Por su categoria Unicode: un PostgreSQL en espanol cita al usuario
  entre comillas latinas, y con EsCaracterDeIdent (la regla de Pascal, que
  cuenta todo lo no ASCII) el usuario del json salia en claro en DB-009
  (medido el 7-nov-2026). LA frontera de CambiaPalabra y de
  TapaDireccionesIp. }
function PegadoAPalabra(C: Char): Boolean;
begin
  Result := C.IsLetterOrDigit or (C = '_') or
    (C.GetUnicodeCategory in [TUnicodeCategory.ucNonSpacingMark, TUnicodeCategory.ucCombiningMark]);
end;

{ ATexto con cada aparicion de ABuscado como palabra ENTERA (sin nada que
  la alargue pegado delante o detras: PegadoAPalabra), sin mayusculas,
  cambiada por AMarca: un usuario 'sa' no se come 'casa' ni 'Base'. }
function CambiaPalabra(const ATexto, ABuscado, AMarca: string): string;
var
  I, Desde, L: Integer;
  Mayus, Buscado: string;
begin
  if ABuscado = '' then
    Exit(ATexto);
  // UpperCase: solo ASCII y la misma longitud, que las posiciones casen
  Mayus := UpperCase(ATexto);
  Buscado := UpperCase(ABuscado);
  L := Length(Buscado);
  Result := '';
  Desde := 1;
  I := PosEx(Buscado, Mayus, 1);
  while I > 0 do
  begin
    if ((I = 1) or not PegadoAPalabra(ATexto[I - 1])) and
       ((I + L > Length(ATexto)) or not PegadoAPalabra(ATexto[I + L])) then
    begin
      Result := Result + Copy(ATexto, Desde, I - Desde) + AMarca;
      Desde := I + L;
      I := PosEx(Buscado, Mayus, Desde);
    end
    else
      I := PosEx(Buscado, Mayus, I + 1);
  end;
  Result := Result + Copy(ATexto, Desde, MaxInt);
end;

{ ASecreto como puede volver escrito: tal cual; dentro de un JSON, como lo
  escribe EL codificador de la casa (TextoEnJson: el valor de un cuerpo JSON
  se tapa despues de pasar por el, Mcp.Tools.Api.JsonTapado), con la barra
  como \/ y con todo lo que no es letra ni cifra como \uXXXX (en mayusculas
  y en minusculas), que es como escriben otros codificadores el texto que
  queda crudo (lo recortado, out=); y en una URL - cada byte UTF-8 que no es
  de los no reservados de RFC 3986 como %XX, en mayusculas y en minusculas, y
  como lo codifica nuestra query (EncodeForm, QueryDe). Gramatica nuestra,
  declarada: el codificador de la API de otro no es un juez al que preguntar.
  Se tapaba solo tal cual: una API que devolvia la credencial con su + escrito
  como \u y 002B, o como %2B, la dejaba ver (CH1 del revisor del paisaje de la
  1.29). Sin repetidas. }
function FormasDelSecreto(const ASecreto: string): TArray<string>;
var
  Mayus, Minus: string;
  procedure Pon(const AForma: string);
  begin
    if (AForma <> '') and (IndexStr(AForma, Result) < 0) then
      Result := Result + [AForma];
  end;
begin
  Result := [];
  Pon(ASecreto);
  Pon(TextoEnJson(ASecreto));
  Pon(TextoEnJson(ASecreto).Replace('/', '\/'));
  Mayus := '';
  Minus := '';
  for var Ch in ASecreto do
    if CharInSet(Ch, ['A'..'Z', 'a'..'z', '0'..'9']) then
    begin
      Mayus := Mayus + Ch;
      Minus := Minus + Ch;
    end
    else
    begin
      Mayus := Mayus + '\u' + IntToHex(Ord(Ch), 4);
      Minus := Minus + '\u' + LowerCase(IntToHex(Ord(Ch), 4));
    end;
  Pon(Mayus);
  Pon(Minus);
  Mayus := '';
  Minus := '';
  for var B in TEncoding.UTF8.GetBytes(ASecreto) do
    if CharInSet(Char(B), ['A'..'Z', 'a'..'z', '0'..'9', '-', '.', '_', '~']) then
    begin
      Mayus := Mayus + Char(B);
      Minus := Minus + Char(B);
    end
    else
    begin
      Mayus := Mayus + '%' + IntToHex(B, 2);
      Minus := Minus + '%' + LowerCase(IntToHex(B, 2));
    end;
  Pon(Mayus);
  Pon(Minus);
  Pon(TNetEncoding.URL.EncodeForm(ASecreto));
end;

{ ATexto con cada secreto, en cada una de sus formas (FormasDelSecreto; de
  CLAVE_LARGA o mas, donde aparezca; mas corto, como palabra entera) y cada
  palabra (como palabra entera) cambiados por AMarca, en el orden dado: lo
  entero antes que sus trozos. EL tapado de las dos conexiones, bases y APIs. }
function Tapa(const ATexto, AMarca: string; const ASecretos, APalabras: array of string): string;
begin
  Result := ATexto;
  for var Secreto in ASecretos do
    for var S in FormasDelSecreto(Secreto) do
      if Length(S) >= CLAVE_LARGA then
        Result := StringReplace(Result, S, AMarca, [rfReplaceAll])
      else
        Result := CambiaPalabra(Result, S, AMarca);
  for var S in APalabras do
    Result := CambiaPalabra(Result, S, AMarca);
end;

{ ATexto con cada direccion IP (v4, o v6 con su zona %n) cambiada por AMarca:
  libpq pone junto al nombre del servidor la direccion que resolvio
  ('connection to server at "<x>" (fe80::...)') y la base, en su pg_hba, la
  de ESTE servidor; con el servidor por nombre en el json salian las dos (CH4
  de la 1.29, medido el 7-nov-2026). Que es una direccion lo dice el
  analizador de Windows (inet_pton, estricto: ni 15.0.2000.5, ni 10:30:00,
  ni una MAC, ni 01.2.3.4). Lo nuestro, declarado, es solo donde empieza y
  acaba un candidato: la tira mas larga de cifras hexadecimales, '.', ':' y
  '%' sin nada que la alargue pegado (PegadoAPalabra: la base cita la
  direccion de este servidor entre comillas latinas), sin su
  punto final, con alguna cifra (un '::' suelto no dice nada) y sin la zona,
  que inet_pton no lee; y una IPv4 seguida de :puerto. }
function TapaDireccionesIp(const ATexto, AMarca: string): string;

  function EsDireccion(const ACandidato: string): Boolean;
  var
    Buf: array[0..15] of Byte;
    A: AnsiString;
  begin
    // solo ASCII: el candidato son cifras hexadecimales, '.', ':' y '%'
    A := AnsiString(ACandidato);
    Result := (inet_pton(AF_INET, MarshaledAString(A), @Buf) = 1) or
      (inet_pton(AF_INET6, MarshaledAString(A), @Buf) = 1);
  end;

  { Cuantos caracteres del principio de ARun son una direccion (0 = ninguno). }
  function LargoDeDireccion(const ARun: string): Integer;
  var
    Cand, Nucleo: string;
    P: Integer;
    ConCifra: Boolean;
  begin
    Cand := ARun.TrimRight(['.']);
    if Cand.EndsWith(':') and not Cand.EndsWith('::') then
      Cand := Cand.Substring(0, Cand.Length - 1);
    Nucleo := Cand;
    P := Nucleo.IndexOf('%');
    if P >= 0 then
      Nucleo := Nucleo.Substring(0, P);
    ConCifra := False;
    for var C in Nucleo do
      ConCifra := ConCifra or CharInSet(C, ['0'..'9', 'A'..'F', 'a'..'f']);
    if ConCifra and EsDireccion(Nucleo) then
      Exit(Cand.Length);
    // una IPv4 con su puerto: 10.0.0.1:5432
    P := Cand.IndexOf(':');
    if (P > 0) and Cand.Substring(0, P).Contains('.') and EsDireccion(Cand.Substring(0, P)) then
      Exit(P);
    Result := 0;
  end;

const
  DE_DIRECCION = ['0'..'9', 'A'..'F', 'a'..'f', '.', ':', '%'];
var
  I, J, N, L: Integer;
  Run: string;
begin
  Result := '';
  N := Length(ATexto);
  I := 1;
  while I <= N do
  begin
    if not CharInSet(ATexto[I], DE_DIRECCION) then
    begin
      Result := Result + ATexto[I];
      Inc(I);
      Continue;
    end;
    J := I;
    while (J <= N) and CharInSet(ATexto[J], DE_DIRECCION) do
      Inc(J);
    Run := Copy(ATexto, I, J - I);
    L := 0;
    if not (((I > 1) and PegadoAPalabra(ATexto[I - 1])) or ((J <= N) and PegadoAPalabra(ATexto[J]))) then
      L := LargoDeDireccion(Run);
    if L > 0 then
      Result := Result + AMarca + Copy(Run, L + 1, MaxInt)
    else
      Result := Result + Run;
    I := J;
  end;
end;

function EnmascaraConexion(const ATexto: string; const AConexion: TConexionDb): string;
var
  Marca: string;
  Host, Resto: string;
  P: Integer;
begin
  // el servidor entero antes que sus trozos (host\instancia, host,puerto)
  Host := AConexion.Servidor;
  Resto := '';
  P := Host.IndexOfAny(['\', ',', ':']);
  if P >= 0 then
  begin
    Resto := Host.Substring(P + 1);
    Host := Host.Substring(0, P);
  end;
  Marca := '<' + NombreDeConexion(AConexion) + '>';
  Result := TapaDireccionesIp(Tapa(ATexto, Marca, [AConexion.Clave],
    [AConexion.Servidor, Resto, Host, AConexion.Base, AConexion.Usuario, AConexion.Puerto]), Marca);
end;

function EnmascaraApi(const ATexto: string; const AConexion: TConexionApi; ADireccion: Boolean): string;
var
  Secretos, Palabras: TArray<string>;
  U: TURI;
begin
  Secretos := [];
  Palabras := [];
  for var A in AConexion.Auth do
  begin
    Secretos := Secretos + [A.Clave, A.Valor];
    if A.Tipo = AUTH_BASIC then
    begin
      Secretos := Secretos + [CredencialBasica(A)];
      if ADireccion then
        Palabras := Palabras + [A.Usuario];
    end;
  end;
  if ADireccion and (AConexion.UrlBase <> '') then
  begin
    // la URL entera antes que su host y su puerto (ya juzgada: UrlBaseDe)
    Secretos := Secretos + [AConexion.UrlBase];
    U := TURI.Create(AConexion.UrlBase);
    Palabras := Palabras + [U.Host];
    // el puerto, solo si no es el de su esquema: TURI pone 443 u 80 cuando la
    // URL no lo escribe, y se tapaba un "Content-Length: 443" (CH8 de la 1.29).
    // El de su esquema lo dice el propio TURI, sin puerto
    var PorDefecto := -1;
    try
      PorDefecto := TURI.Create(U.Scheme + '://' + U.Host).Port;
    except
      // un host que no vuelve a componerse: se tapa el puerto, por si acaso
    end;
    if (U.Port > 0) and (U.Port <> PorDefecto) then
      Palabras := Palabras + [IntToStr(U.Port)];
  end;
  Result := Tapa(ATexto, '<' + NombreDeConexion(AConexion) + '>', Secretos, Palabras);
end;

end.
