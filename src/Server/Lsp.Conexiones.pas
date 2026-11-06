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
  algo que no es true/false, la entrada no se usa (falla cerrado). }

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

{ <proyecto>/<alias>: EL nombre de una base para el agente. }
function NombreDeConexion(const AConexion: TConexionDb): string;

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
  el puerto (medido el 6-nov-2026). }
function EnmascaraConexion(const ATexto: string; const AConexion: TConexionDb): string;

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON, System.StrUtils,
  Lsp.Texts, Lsp.Casa, Lsp.Settings, Lsp.Json,
  Lsp.Pascal, // EsCaracterDeIdent: que es pegarse a una palabra
  Lsp.Codificacion; // BomUtf8En: el BOM lo lee el de la casa

const
  // el proveedor por el que conecta el servidor; ausente = este
  PROVEEDOR_FIREDAC = 'FIREDAC';
  SEPARADOR_DE_NOMBRE = '/';
  // una contrasena de al menos tanto se tapa donde aparezca; una mas corta,
  // solo como palabra entera (una 'x' no se come el texto)
  CLAVE_LARGA = 6;

function NombreDeConexion(const AConexion: TConexionDb): string;
begin
  Result := AConexion.Proyecto + SEPARADOR_DE_NOMBRE + AConexion.Alias;
end;

{ El texto del fichero de conexiones, o la negativa. Su lector y no una
  puerta: lleva credenciales y no es lugar de ninguna, como settings.ini.
  UTF-8 con o sin BOM. }
function TextoDeConexiones(out ATexto, ANegativa: string): Boolean;
var
  Ruta: string;
  B: TBytes;
  Ini: Integer;
begin
  ATexto := '';
  ANegativa := '';
  Ruta := FicheroDeConexiones(False);
  if not TFile.Exists(Ruta) then
  begin
    ANegativa := MsgFmt(SR_DB_FICHERO_FMT, [MsgText(SF_DB_FICHERO_NO_HAY)]);
    Exit(False);
  end;
  B := TFile.ReadAllBytes(Ruta);
  Ini := 0;
  if BomUtf8En(B, 0) then
    Ini := 3;
  ATexto := TEncoding.UTF8.GetString(B, Ini, Length(B) - Ini);
  Result := True;
end;

{ El valor de AClave como texto: una cadena, o un numero escrito como tal
  ("port": 5432; TJSONNumber es un TJSONString); '' si no esta o es otra
  cosa. }
function Campo(const AObj: TJSONObject; const AClave: string): string;
var
  V: TJSONValue;
begin
  V := AObj.GetValue(AClave);
  if V is TJSONString then
    Result := TJSONString(V).Value
  else
    Result := '';
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

function ConexionesDbDeLaSesion(out ANegativa: string): TArray<TConexionDb>;
var
  Proyectos: TArray<string>;
  Texto: string;
  Raiz, Lista, Bases: TJSONObject;
  P, B: TJSONPair;
begin
  Result := [];
  ANegativa := '';
  Proyectos := ProyectosDeConexionDeLaSesion(False);
  if Length(Proyectos) = 0 then
  begin
    ANegativa := MsgText(SR_DB_SIN_PROYECTOS);
    Exit;
  end;
  if not TextoDeConexiones(Texto, ANegativa) then
    Exit;
  Raiz := ObjetoJson(Texto);
  if Raiz = nil then
  begin
    ANegativa := MsgFmt(SR_DB_FICHERO_FMT, [MsgText(SF_DB_FICHERO_NO_JSON)]);
    Exit;
  end;
  try
    Lista := ObjetoDe(ObjetoDe(Raiz, 'db-connections'), 'projects');
    if Lista = nil then
    begin
      ANegativa := MsgFmt(SR_DB_FICHERO_FMT, [MsgText(SF_DB_FICHERO_SIN_RAIZ)]);
      Exit;
    end;
    for P in Lista do
    begin
      if not NombreEnLaLista(P.JsonString.Value, Proyectos) then
        Continue;
      if not (P.JsonValue is TJSONObject) then
        Continue;
      Bases := ObjetoDe(TJSONObject(P.JsonValue), 'databases');
      if Bases = nil then
        Continue;
      for B in Bases do
        if B.JsonValue is TJSONObject then
          Result := Result + [ConexionDe(P.JsonString.Value, B.JsonString.Value, TJSONObject(B.JsonValue))]
        else
          Result := Result + [ConexionDe(P.JsonString.Value, B.JsonString.Value, nil)];
    end;
  finally
    Raiz.Free;
  end;
end;

function ConexionDbDeLaSesion(const ANombre: string; out AConexion: TConexionDb;
  out ANegativa: string): Boolean;
var
  C: TConexionDb;
begin
  AConexion := Default(TConexionDb);
  for C in ConexionesDbDeLaSesion(ANegativa) do
    if SameText(NombreDeConexion(C), ANombre.Trim) then
    begin
      AConexion := C;
      Exit(True);
    end;
  if ANegativa = '' then
    ANegativa := MsgFmt(SR_DB_DESCONOCIDA_FMT, [ANombre.Trim]);
  Result := False;
end;


{ ATexto con cada aparicion de ABuscado como palabra ENTERA (sin un
  caracter de identificador pegado delante o detras: EsCaracterDeIdent, que
  cuenta tambien lo no ASCII), sin mayusculas, cambiada por AMarca: un
  usuario 'sa' no se come 'casa' ni 'Base'. }
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
    if ((I = 1) or not EsCaracterDeIdent(ATexto[I - 1])) and
       ((I + L > Length(ATexto)) or not EsCaracterDeIdent(ATexto[I + L])) then
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

function EnmascaraConexion(const ATexto: string; const AConexion: TConexionDb): string;
var
  Marca, Host: string;
  P: Integer;
begin
  Marca := '<' + NombreDeConexion(AConexion) + '>';
  Result := ATexto;
  if Length(AConexion.Clave) >= CLAVE_LARGA then
    Result := StringReplace(Result, AConexion.Clave, Marca, [rfReplaceAll])
  else
    Result := CambiaPalabra(Result, AConexion.Clave, Marca);
  // el servidor entero antes que sus trozos (host\instancia, host,puerto)
  Result := CambiaPalabra(Result, AConexion.Servidor, Marca);
  Host := AConexion.Servidor;
  P := Host.IndexOfAny(['\', ',', ':']);
  if P >= 0 then
  begin
    Result := CambiaPalabra(Result, Host.Substring(P + 1), Marca);
    Host := Host.Substring(0, P);
  end;
  Result := CambiaPalabra(Result, Host, Marca);
  Result := CambiaPalabra(Result, AConexion.Base, Marca);
  Result := CambiaPalabra(Result, AConexion.Usuario, Marca);
  Result := CambiaPalabra(Result, AConexion.Puerto, Marca);
end;

end.
