unit Lsp.BaseDeDatos;

{ El lado FireDAC de delphi_db (1.29): los drivers que ENLAZA este servidor
  y la DLL cliente de cada uno. Una forma de codigo para todos los motores
  (David, 6-nov-2026: "luego solo trabajar con una forma de codigo"): el SQL
  lo compone el servidor una vez y FireDAC lo traduce (medido con la sonda
  del 6-nov: RecsSkip/RecsMax, sus escapes de funciones, QuoteObjName,
  metadatos).

  Que motores hay lo dice FireDAC (los DriverID registrados), no una lista
  nuestra. Lo NUESTRO es que drivers se enlazan y cuales cargan su DLL
  cliente de la casa del servidor (<casa>\drivers\<DriverID>, VendorHome:
  la ruta la compone FireDAC con su convencion, PG en \lib\libpq.dll): un
  driver CON casa la carga SIEMPRE de ahi, aunque la carpeta no este -
  falla, nunca se busca: una DLL que carga el servidor es codigo que ejecuta
  (David, 6-nov: "drivers\<motor>\ del servidor"). MSSQL va por el ODBC del
  sistema y no lleva casa (su enlace solo apaga la busqueda de servidores
  por la red, ver GMsSql). Anadir un motor = enlazar su driver y, si carga
  una DLL cliente, su enlace con su casa en la initialization. }

interface

uses
  System.SysUtils, Data.DB, FireDAC.Comp.Client,
  Lsp.Conexiones;

type
  { Un campo de una tabla como lo dice el catalogo de la base (los metadatos
    de FireDAC: mkTableFields y la clave), y el TFieldType con el que se tipa
    un parametro contra el (ColumnDef2FieldDef): PG no compara un entero con
    un texto (medido el 6-nov-2026), y la conversion la decide FireDAC. }
  TCampoDb = record
    Nombre: string;
    Tipo: string;            // como lo llama la base (int, varchar, timestamp...)
    TipoDeCampo: TFieldType; // el de FireDAC
    Nulo: Boolean;
    Clave: Boolean;
    { lo que la base pone sola en un insert que no lo da: su valor por defecto
      (caDefault) o su contador (caAutoInc), como lo dice el catalogo; un
      agente sabia que campos obligatorios tenia que dar a base de errores
      (la pasada en vivo de la 1.29) }
    Defecto, AutoInc: Boolean;
    Longitud, Precision, Escala: Integer;
  end;

  { Una clave ajena de una tabla y un indice, como los dice el catalogo de la
    base (los metadatos de FireDAC: mkForeignKeys/mkForeignKeyFields y
    mkIndexes/mkIndexFields; DB-P5 de la 1.29): con ellos el agente sabe como
    se relacionan las tablas sin adivinarlo por los nombres. }
  TClaveAjenaDb = record
    Nombre: string;
    Campos: TArray<string>;
    Tabla: string;                // la tabla a la que apunta
    CamposDeAlla: TArray<string>; // sus campos, en el orden de Campos
  end;
  TIndiceDb = record
    Nombre: string;
    Unico, Primario: Boolean;
    Campos: TArray<string>;
  end;

const
  // segundos que espera el servidor a que una base abra: SQL Server con un
  // host que no responde tardaba 42 s con LoginTimeout=5 (medido el 6-nov)
  PLAZO_CONEXION_DB = 12;
  // milisegundos de una orden: pasado, FireDAC la cancela
  PLAZO_ORDEN_DB = 30000;
  // segundos de una llamada ya abierta la base (Mcp.Tools.Db, EnLaBase): las
  // ordenes de la CONEXION (BEGIN, COMMIT, ROLLBACK) no llevan el plazo de
  // las de un comando, la cancelacion de una que si lo lleva vuelve por la
  // misma conexion, y con la red callada la llamada no volvia en 240 s (CH11
  // de la 1.29, medido el 7-nov-2026 con un proxy que calla). Caben dos
  // ordenes con su plazo entero (rows: el COUNT y la pagina) y un margen.
  PLAZO_LLAMADA_DB = 2 * (PLAZO_ORDEN_DB div 1000) + 5;

{ Los motores de este servidor: los DriverID de los drivers enlazados, como
  los dice FireDAC (FDManager.GetDriverNames). }
function MotoresDeBd: TArray<string>;

{ Por que AConexion no se puede usar en este servidor ('' = se puede): el
  Defecto de su entrada del json, o un motor que el servidor no tiene. Un
  fragmento (SF_DB_DEF_*): la lista de connections lo lleva tal cual, y quien
  la usa lo envuelve en DB-004. }
function DefectoDeConexion(const AConexion: TConexionDb): string;

{ Abre AConexion con lo que dice su json y nada mas: el puerto y el plazo,
  solo si la tabla de parametros de su driver los tiene (lo que ensena el
  editor de conexiones del IDE); y en un driver de libpq, sin el pgpass de la
  cuenta del servidor (lo leia por su cuenta y conectaba sin contrasena,
  medido el 6-nov). Con plazo PROPIO: si no abre en PLAZO_CONEXION_DB, DB-007
  y el hilo que espera a la base la libera cuando termine. '' = abierta en
  AConn (la libera quien llama); si no, la negativa ya enmascarada. }
function AbreBase(const AConexion: TConexionDb; out AConn: TFDConnection): string;

{ EL trabajo con una base con plazo sobre su conexion AConn (Lsp.ConPlazo,
  TrabajoConPlazo: el mismo protocolo): el de abrir (AbreBase, DB-007) y el
  de la llamada entera (Mcp.Tools.Db, DB-022). Ademas apunta las conexiones
  de los que se abandonan y siguen esperando a una base callada: al salir, el
  servidor las despierta antes que FireDAC (ver la finalization). }
function TrabajoConLaBase(AConn: TFDConnection; const ATrabajo: TProc; APlazoMs: Cardinal;
  const AAlVencer, ALibera: TProc): Boolean;

{ Las tablas (o las vistas, con AVistas) del esquema en que abre la conexion,
  como las nombra FireDAC: en PG, sin el esquema, salian las 214 de
  information_schema y pg_catalog (medido el 6-nov). }
function TablasDeBase(AConn: TFDConnection; AVistas: Boolean): TArray<string>;

{ Los campos de ATabla, en su orden. }
function CamposDeTabla(AConn: TFDConnection; const ATabla: string): TArray<TCampoDb>;

{ Las claves ajenas de ATabla y sus indices, cada uno con sus campos en su
  orden. }
function ClavesAjenasDeTabla(AConn: TFDConnection; const ATabla: string): TArray<TClaveAjenaDb>;
function IndicesDeTabla(AConn: TFDConnection; const ATabla: string): TArray<TIndiceDb>;

{ ANombre entrecomillado como lo pide el motor ([x] en MSSQL, "x" en PG): el
  de FireDAC, nunca uno nuestro. }
function CitaNombre(AConn: TFDConnection; const ANombre: string): string;

{ Un nombre NUEVO (el de una vista) como el generador de FireDAC nombra una
  tabla nueva (EncodeObjName con eoQuote y eoNormalize): en PG en minusculas,
  como un nombre sin comillas, y tal cual en MSSQL (medido el 7-nov-2026,
  C5 de la 1.29). CitaNombre cita tal cual uno que ya es del catalogo. }
function NombreNuevoCitado(AConn: TFDConnection; const ANombre: string): string;

{ DB-010 con lo que dijo la base, enmascarado. }
function NegativaDeLaBase(E: Exception; const AConexion: TConexionDb): string;

implementation

uses
  Winapi.Windows, // el entorno del proceso: QuitaEntornoDeLibpq
  System.Classes, System.StrUtils, System.SyncObjs, System.IOUtils, System.Variants,
  FireDAC.Stan.Intf, FireDAC.Stan.Option, FireDAC.Stan.Error, FireDAC.Stan.Def,
  FireDAC.Stan.Async, FireDAC.Stan.Consts, FireDAC.Phys.Intf, FireDAC.Phys,
  FireDAC.Phys.MSSQL, FireDAC.Phys.PG, FireDAC.DApt, FireDAC.DatS,
  FireDAC.ConsoleUI.Wait,
  Lsp.Texts, Lsp.Casa,
  Lsp.Sandbox,  // LineasDelEntorno: EL recorrido del entorno del proceso
  Lsp.ConPlazo, // TrabajoConPlazo: el plazo lo pone el servidor, no el driver
  System.Generics.Collections, // las conexiones abandonadas
  Winapi.WinSock2, // closesocket: despertar a una abandonada al salir
  FireDAC.Phys.PGWrapper; // TPgConnection: el socket de libpq de una conexion PG

const
  // el fichero de contrasenas que se le da a libpq para que no lea el de la
  // cuenta: NO EXISTE (en la casa del motor, donde ningun agente escribe)
  FICHERO_SIN_CLAVES = 'sin-claves.pgpass';

var
  // los drivers que cargan su DLL de la casa, con el enlace que la fija:
  // uno por motor enlazado que la necesita. Se crean al arrancar (abajo) y
  // no al primer uso: dos peticiones a la vez no crean dos.
  GPg: TFDPhysPgDriverLink = nil;
  // el de MSSQL no lleva casa (ODBC del sistema) pero apaga ListServers:
  // sin el, la tabla de parametros del driver (GetConnParams, la que lee
  // ParametrosDelDriver) lanza una TTask que BUSCA servidores SQL por la red
  // (SQLBrowseConnect -> NetServerEnum, unos 16 s) y queda viva; al salir el
  // servidor, FireDAC ya habia descargado odbc32.dll y la tarea volvia a
  // ella: 0xC0000005 al cerrar y sus atomos del RTL sin borrar (medido el
  // 7-nov-2026 con cdb y el visor de eventos: odbc32.dll_unloaded+0x2f490)
  GMsSql: TFDPhysMSSQLDriverLink = nil;
  // las conexiones de los trabajos con una base abandonados por su plazo que
  // siguen esperando a la base (TrabajoConLaBase), bajo su cerrojo: al salir,
  // la finalization las despierta
  GAbandonadas: TList<TFDConnection> = nil;
  GAbandonadasLock: TCriticalSection = nil;

function MotoresDeBd: TArray<string>;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    FDManager.GetDriverNames(L);
    Result := L.ToStringArray;
  finally
    L.Free;
  end;
end;

function DefectoDeConexion(const AConexion: TConexionDb): string;
var
  Motores: TArray<string>;
begin
  if AConexion.Defecto <> '' then
    Exit(AConexion.Defecto);
  Motores := MotoresDeBd;
  if not MatchText(AConexion.Motor, Motores) then
    Exit(MsgFmt(SF_DB_DEF_MOTOR_FMT, [AConexion.Motor, string.Join(', ', Motores)]));
  Result := '';
end;

{ Los nombres de la tabla de parametros de un driver (GetConnParams). }
function ParametrosDelDriver(const ADriverID: string): TArray<string>;
var
  Meta: IFDPhysDriverMetadata;
  T: TFDDatSTable;
  Col, R: Integer;
begin
  Result := [];
  (FDPhysManager as IFDPhysManagerMetadata).CreateDriverMetadata(ADriverID, Meta);
  T := Meta.GetConnParams(nil);
  try
    Col := -1;
    for R := 0 to T.Columns.Count - 1 do
      if SameText(T.Columns[R].Name, 'Name') then
        Col := R;
    if Col < 0 then
      Exit;
    for R := 0 to T.Rows.Count - 1 do
      Result := Result + [VarToStr(T.Rows[R].GetData(Col))];
  finally
    T.Free;
  end;
end;

procedure PonParametros(AConn: TFDConnection; const C: TConexionDb);
var
  Del: TArray<string>;
begin
  Del := ParametrosDelDriver(C.Motor);
  AConn.LoginPrompt := False;
  AConn.Params.Clear;
  AConn.Params.DriverID := C.Motor;
  AConn.Params.Database := C.Base;
  AConn.Params.UserName := C.Usuario;
  AConn.Params.Password := C.Clave;
  if C.Servidor <> '' then
    AConn.Params.Values[S_FD_ConnParam_Common_Server] := C.Servidor;
  if (C.Puerto <> '') and MatchText(S_FD_ConnParam_Common_Port, Del) then
    AConn.Params.Values[S_FD_ConnParam_Common_Port] := C.Puerto;
  if MatchText(S_FD_ConnParam_Common_LoginTimeout, Del) then
    AConn.Params.Values[S_FD_ConnParam_Common_LoginTimeout] := IntToStr(PLAZO_CONEXION_DB - 2);
  // ...y ni el certificado de cliente ni la identidad de Windows o Kerberos de
  // la cuenta del servidor: el json da usuario y contrasena, y libpq usaria por
  // su cuenta postgresql.crt de su perfil, GSS para cifrar y SSPI/GSS para
  // entrar (CH3 de la 1.29). Son claves de libpq 16 o posterior: una mas vieja
  // no abre y lo dice (invalid connection option), en vez de entrar como ella
  // quiera.
  if MatchText(S_FD_ConnParam_PG_PGAdvanced, Del) then
    AConn.Params.Values[S_FD_ConnParam_PG_PGAdvanced] :=
      'passfile=' + TPath.Combine(CarpetaDeDriverDeBd(C.Motor), FICHERO_SIN_CLAVES) +
      ';sslcertmode=disable;gssencmode=disable;require_auth=!gss,!sspi';
  AConn.ResourceOptions.CmdExecTimeout := PLAZO_ORDEN_DB;
end;

{ Lo que dijo el motor, para la causa de DB-009 y DB-010: enmascarado y sin
  su punto final, que el mensaje pone el suyo (medido en vivo el 6-nov-2026:
  "already exists.. Nothing was changed"). }
function TextoDelMotor(const AMensaje: string; const AConexion: TConexionDb): string;
begin
  Result := EnmascaraConexion(AMensaje, AConexion).Trim.TrimRight(['.']);
end;

type
  { Una apertura con plazo (Lsp.ConPlazo): la conexion y su resultado. }
  TApertura = class
  public
    Conn: TFDConnection;
    Fallo: Boolean;
    DelMotor: Boolean;
    // FireDAC no pudo cargar la libreria cliente del motor (DB-030)
    SinLibreria: Boolean;
    Kind: TFDCommandExceptionKind;
    Mensaje: string;
  end;

{ AConn entra (AEsta) o sale de las abandonadas. }
procedure ApuntaAbandonada(AConn: TFDConnection; AEsta: Boolean);
begin
  GAbandonadasLock.Enter;
  try
    if AEsta then
      GAbandonadas.Add(AConn)
    else
      GAbandonadas.Remove(AConn);
  finally
    GAbandonadasLock.Leave;
  end;
end;

function TrabajoConLaBase(AConn: TFDConnection; const ATrabajo: TProc; APlazoMs: Cardinal;
  const AAlVencer, ALibera: TProc): Boolean;
var
  AlVencer, Libera: TProc;
  Apuntada: Boolean;
begin
  AlVencer := AAlVencer;
  Libera := ALibera;
  Apuntada := False;
  Result := TrabajoConPlazo(ATrabajo, APlazoMs,
    // vencido: se apunta aqui, en el hilo de quien pide y ANTES de irse; el
    // hilo no la libera hasta que quien pide se haya ido
    procedure
    begin
      ApuntaAbandonada(AConn, True);
      Apuntada := True;
      if Assigned(AlVencer) then
        AlVencer();
    end,
    // ...y la quita antes de liberarla
    procedure
    begin
      ApuntaAbandonada(AConn, False);
      Libera();
    end);
  // acabo a la vez que vencia: es de quien pide, que la libera
  if Result and Apuntada then
    ApuntaAbandonada(AConn, False);
end;

{ Al salir, los trabajos abandonados que siguen esperando a una base callada
  tienen su conexion abierta en su hilo, y FireDAC al destruir su gestor la
  cierra desde el principal con su cerrojo tomado: el hilo que despierta no
  puede soltarla (interbloqueo, medido con cdb el 7-nov-2026) o usa lo que se
  acaba de liberar (0xC0000005 a los 2 s, medido el mismo dia). Ni shutdown
  ni CancelIoEx despiertan un select de Winsock (medido: el primero no lo
  toca, el segundo le da WSAEINTR y libpq reintenta); closesocket si. Con el
  socket cerrado, libpq vuelve con error EN SU HILO, el trabajo se deshace
  solo y suelta la conexion, y FireDAC sale. CH11 de la 1.29. }
procedure DespiertaLasAbandonadas;
var
  Cerradas: Integer;
  Hasta: UInt64;
begin
  Cerradas := 0;
  GAbandonadasLock.Enter;
  try
    for var C in GAbandonadas do
    begin
      // ConnectionIntf y no CliObj: CliObj comprueba que este activa y puede
      // ABRIRLA
      var Fisica := C.ConnectionIntf;
      if (Fisica <> nil) and SameText(C.Params.DriverID, GPg.ActualDriverID) and
         (TObject(Fisica.CliObj) is TPgConnection) then
      begin
        var Pg := TPgConnection(Fisica.CliObj);
        if Pg.FHandle <> nil then
        begin
          var Sock := Pg.Lib.FPQsocket(Pg.FHandle);
          if Sock >= 0 then
          begin
            closesocket(TSocket(Sock));
            Inc(Cerradas);
          end;
        end;
      end;
    end;
  finally
    GAbandonadasLock.Leave;
  end;
  if Cerradas = 0 then
    Exit;
  // a que se deshagan y la suelten
  Hasta := GetTickCount64 + 10000;
  repeat
    Sleep(20);
    GAbandonadasLock.Enter;
    try
      Cerradas := GAbandonadas.Count;
    finally
      GAbandonadasLock.Leave;
    end;
  until (Cerradas = 0) or (GetTickCount64 > Hasta);
end;

function AbreBase(const AConexion: TConexionDb; out AConn: TFDConnection): string;
var
  A: TApertura;
  Nombre: string;
begin
  AConn := nil;
  Nombre := NombreDeConexion(AConexion);
  A := TApertura.Create;
  try
    A.Conn := TFDConnection.Create(nil);
    PonParametros(A.Conn, AConexion);
  except
    A.Conn.Free;
    A.Free;
    raise;
  end;
  if not TrabajoConLaBase(A.Conn,
    procedure
    begin
      try
        A.Conn.Open;
      except
        on E: EFDDBEngineException do
        begin
          A.Fallo := True;
          A.DelMotor := True;
          A.Kind := E.Kind;
          A.Mensaje := E.Message;
        end;
        // la libreria cliente no se cargo: lo dice su codigo, no su texto
        on E: EFDException do
        begin
          A.Fallo := True;
          A.SinLibreria := E.FDCode = er_FD_AccCantLoadLibrary;
          A.Mensaje := E.Message;
        end;
        on E: Exception do
        begin
          A.Fallo := True;
          A.Mensaje := E.Message;
        end;
      end;
    end, PLAZO_CONEXION_DB * 1000, nil,
    // vencido: la conexion que se abria ya no es de nadie
    procedure
    begin
      A.Conn.Free;
      A.Free;
    end) then
    Exit(MsgFmt(SR_DB_NO_RESPONDE_FMT, [Nombre, PLAZO_CONEXION_DB]));
  try
    if not A.Fallo then
    begin
      AConn := A.Conn;
      Exit('');
    end;
    A.Conn.Free;
    if A.DelMotor and (A.Kind in [ekUserPwdInvalid, ekUserPwdExpired]) then
      Exit(MsgFmt(SR_DB_LOGIN_FMT, [Nombre]));
    if A.SinLibreria then
      Exit(MsgFmt(SR_DB_SIN_LIBRERIA_FMT, [Nombre, AConexion.Motor]));
    Result := MsgFmt(SR_DB_NO_ABRE_FMT, [Nombre, TextoDelMotor(A.Mensaje, AConexion)]);
  finally
    A.Free;
  end;
end;

function TablasDeBase(AConn: TFDConnection; AVistas: Boolean): TArray<string>;
var
  L: TStringList;
  Tipos: TFDPhysTableKinds;
begin
  if AVistas then
    Tipos := [tkView]
  else
    Tipos := [tkTable];
  L := TStringList.Create;
  try
    AConn.GetTableNames('', AConn.CurrentSchema, '', L, [osMy, osOther], Tipos, False);
    L.Sort;
    Result := L.ToStringArray;
  finally
    L.Free;
  end;
end;

{ Una consulta de metadatos de AQue sobre el objeto AObjeto (una tabla, con
  ABase vacio) o sobre el objeto AObjeto de la tabla ABase (los campos de un
  indice o de una clave ajena), en el esquema de la conexion, ya abierta: LA
  forma de pedirle a FireDAC el catalogo (los campos, las claves ajenas, los
  indices). }
function Metadatos(AConn: TFDConnection; AQue: TFDPhysMetaInfoKind;
  const ABase, AObjeto: string): TFDMetaInfoQuery;
begin
  Result := TFDMetaInfoQuery.Create(nil);
  try
    Result.Connection := AConn;
    Result.MetaInfoKind := AQue;
    Result.SchemaName := AConn.CurrentSchema;
    Result.BaseObjectName := ABase;
    Result.ObjectName := AObjeto;
    Result.Open;
  except
    Result.Free;
    raise;
  end;
end;

function CamposDeTabla(AConn: TFDConnection; const ATabla: string): TArray<TCampoDb>;
var
  M: TFDMetaInfoQuery;
  Claves: TStringList;
  C: TCampoDb;
  Atr: TFDDataAttributes;
  N, P, S: Integer;
  Tam: LongWord;
begin
  Result := [];
  M := nil;
  Claves := TStringList.Create;
  try
    AConn.GetKeyFieldNames('', AConn.CurrentSchema, ATabla, '', Claves);
    M := Metadatos(AConn, mkTableFields, '', ATabla);
    while not M.Eof do
    begin
      C := Default(TCampoDb);
      C.Nombre := M.FieldByName('COLUMN_NAME').AsString;
      C.Tipo := M.FieldByName('COLUMN_TYPENAME').AsString;
      C.Longitud := M.FieldByName('COLUMN_LENGTH').AsInteger;
      C.Precision := M.FieldByName('COLUMN_PRECISION').AsInteger;
      C.Escala := M.FieldByName('COLUMN_SCALE').AsInteger;
      N := M.FieldByName('COLUMN_ATTRIBUTES').AsInteger;
      Atr := [];
      Move(N, Atr, SizeOf(Atr));
      C.Nulo := caAllowNull in Atr;
      C.Defecto := caDefault in Atr;
      C.AutoInc := caAutoInc in Atr;
      C.Clave := Claves.IndexOf(C.Nombre) >= 0;
      Tam := 0;
      P := 0;
      S := 0;
      AConn.FormatOptions.ColumnDef2FieldDef(TFDDataType(M.FieldByName('COLUMN_DATATYPE').AsInteger),
        LongWord(C.Longitud), C.Precision, C.Escala, Atr, C.TipoDeCampo, Tam, P, S);
      Result := Result + [C];
      M.Next;
    end;
  finally
    M.Free;
    Claves.Free;
  end;
end;

{ Los campos de AObjeto (un indice o una clave ajena de ATabla) por su
  COLUMN_POSITION, y los de la otra tabla (ACampoDeAlla, si se pide). }
procedure CamposDeObjeto(AConn: TFDConnection; AQue: TFDPhysMetaInfoKind;
  const ATabla, AObjeto, ACampoDeAlla: string; out ACampos, ADeAlla: TArray<string>);
var
  M: TFDMetaInfoQuery;
begin
  ACampos := [];
  ADeAlla := [];
  M := Metadatos(AConn, AQue, ATabla, AObjeto);
  try
    M.IndexFieldNames := 'COLUMN_POSITION';
    M.First;
    while not M.Eof do
    begin
      ACampos := ACampos + [M.FieldByName('COLUMN_NAME').AsString];
      if ACampoDeAlla <> '' then
        ADeAlla := ADeAlla + [M.FieldByName(ACampoDeAlla).AsString];
      M.Next;
    end;
  finally
    M.Free;
  end;
end;

function ClavesAjenasDeTabla(AConn: TFDConnection; const ATabla: string): TArray<TClaveAjenaDb>;
var
  M: TFDMetaInfoQuery;
  K: TClaveAjenaDb;
begin
  Result := [];
  M := Metadatos(AConn, mkForeignKeys, '', ATabla);
  try
    while not M.Eof do
    begin
      K := Default(TClaveAjenaDb);
      K.Nombre := M.FieldByName('FKEY_NAME').AsString;
      K.Tabla := M.FieldByName('PKEY_TABLE_NAME').AsString;
      CamposDeObjeto(AConn, mkForeignKeyFields, ATabla, K.Nombre, 'PKEY_COLUMN_NAME', K.Campos, K.CamposDeAlla);
      Result := Result + [K];
      M.Next;
    end;
  finally
    M.Free;
  end;
end;

function IndicesDeTabla(AConn: TFDConnection; const ATabla: string): TArray<TIndiceDb>;
var
  M: TFDMetaInfoQuery;
  I: TIndiceDb;
  Nada: TArray<string>;
begin
  Result := [];
  M := Metadatos(AConn, mkIndexes, '', ATabla);
  try
    while not M.Eof do
    begin
      I := Default(TIndiceDb);
      I.Nombre := M.FieldByName('INDEX_NAME').AsString;
      I.Primario := TFDPhysIndexKind(M.FieldByName('INDEX_TYPE').AsInteger) = ikPrimaryKey;
      I.Unico := TFDPhysIndexKind(M.FieldByName('INDEX_TYPE').AsInteger) in [ikUnique, ikPrimaryKey];
      CamposDeObjeto(AConn, mkIndexFields, ATabla, I.Nombre, '', I.Campos, Nada);
      Result := Result + [I];
      M.Next;
    end;
  finally
    M.Free;
  end;
end;

function CitaNombre(AConn: TFDConnection; const ANombre: string): string;
begin
  Result := AConn.ConnectionMetaDataIntf.QuoteObjName(ANombre, npObject);
end;

function NombreNuevoCitado(AConn: TFDConnection; const ANombre: string): string;
var
  R: TFDPhysParsedName;
begin
  AConn.ConnectionMetaDataIntf.DecodeObjName(ANombre, R, nil, []);
  Result := AConn.ConnectionMetaDataIntf.EncodeObjName(R, nil, [eoQuote, eoNormalize]);
end;

function NegativaDeLaBase(E: Exception; const AConexion: TConexionDb): string;
begin
  Result := MsgFmt(SR_DB_RESPONDE_FMT, [NombreDeConexion(AConexion),
    TextoDelMotor(E.Message, AConexion)]);
end;

{ CH3 de la 1.29: libpq rellena lo que el json no dice con el ENTORNO de la
  cuenta del servidor - medido el 7-nov-2026: con el mismo json,
  PGSSLMODE=require cambiaba la conexion (de abrir a DB-009), y PGHOSTADDR
  la mandaria a otra maquina. Lo que abre una base es su json y nada mas
  (David). Las variables de libpq son las PG* (su documentacion: "Environment
  Variables", todas con ese prefijo, tambien las que lee sin ser claves de
  conexion, PGSERVICEFILE o PGSYSCONFDIR), y este servidor no usa ninguna:
  se quitan de SU entorno al arrancar, de las dos copias que hay - la de
  Windows y la de la CRT que usa libpq (ucrtbase: la copia la primera vez
  que alguien la lee, y despues no ve un SetEnvironmentVariable). }
procedure QuitaEntornoDeLibpq;
type
  TWPutEnvS = function(ANombre, AValor: PWideChar): Integer; cdecl;
const
  PREFIJO_DE_LIBPQ = 'PG';
var
  Nombres: TArray<string>;
  PonEnLaCrt: TWPutEnvS;
  Crt: HMODULE;
begin
  Nombres := [];
  for var Linea in LineasDelEntorno do
  begin
    // desde 1: una entrada de unidad empieza por '=' (=C:=C:\)
    var Igual := Linea.IndexOf('=', 1);
    if (Igual > 0) and Linea.StartsWith(PREFIJO_DE_LIBPQ, True) then
      Nombres := Nombres + [Linea.Substring(0, Igual)];
  end;
  PonEnLaCrt := nil;
  Crt := GetModuleHandle('ucrtbase.dll');
  if Crt <> 0 then
    @PonEnLaCrt := GetProcAddress(Crt, '_wputenv_s');
  for var N in Nombres do
  begin
    SetEnvironmentVariableW(PWideChar(N), nil);
    // un valor vacio la QUITA de la tabla de la CRT
    if Assigned(PonEnLaCrt) then
      PonEnLaCrt(PWideChar(N), '');
  end;
end;

initialization
  QuitaEntornoDeLibpq;
  GPg := TFDPhysPgDriverLink.Create(nil);
  GPg.VendorHome := CarpetaDeDriverDeBd(GPg.BaseDriverID);
  GMsSql := TFDPhysMSSQLDriverLink.Create(nil);
  GMsSql.ListServers := False;
  GAbandonadas := TList<TFDConnection>.Create;
  GAbandonadasLock := TCriticalSection.Create;

finalization
  // Antes que FireDAC (DespiertaLasAbandonadas). Una de SQL Server no se puede
  // despertar: su ODBC no da el socket, y SQLCancel solo le pide a la base
  // que cancele. Con una base de SQL Server callada a mitad, el servidor sigue
  // sin salir solo, como antes de la 1.29 (medido el 7-nov-2026 con un proxy
  // que calla al abrir: DB-007 a los 12 s y el proceso vivo a los 30 s; el
  // servicio lo termina el SCM).
  DespiertaLasAbandonadas;
  FreeAndNil(GMsSql);
  FreeAndNil(GPg);
  // la lista y su cerrojo, solo si quedo vacia: un hilo que aun espera a su
  // base los usa al acabar, y se van con el proceso
  if GAbandonadas.Count = 0 then
  begin
    FreeAndNil(GAbandonadas);
    FreeAndNil(GAbandonadasLock);
  end;

end.
