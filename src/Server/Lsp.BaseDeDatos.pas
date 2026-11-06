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
  sistema y no lleva casa. Anadir un motor = enlazar su driver y, si carga
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
    Longitud, Precision, Escala: Integer;
  end;

const
  // segundos que espera el servidor a que una base abra: SQL Server con un
  // host que no responde tardaba 42 s con LoginTimeout=5 (medido el 6-nov)
  PLAZO_CONEXION_DB = 12;
  // milisegundos de una orden: pasado, FireDAC la cancela
  PLAZO_ORDEN_DB = 30000;

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

{ Las tablas (o las vistas, con AVistas) del esquema en que abre la conexion,
  como las nombra FireDAC: en PG, sin el esquema, salian las 214 de
  information_schema y pg_catalog (medido el 6-nov). }
function TablasDeBase(AConn: TFDConnection; AVistas: Boolean): TArray<string>;

{ Los campos de ATabla, en su orden. }
function CamposDeTabla(AConn: TFDConnection; const ATabla: string): TArray<TCampoDb>;

{ ANombre entrecomillado como lo pide el motor ([x] en MSSQL, "x" en PG): el
  de FireDAC, nunca uno nuestro. }
function CitaNombre(AConn: TFDConnection; const ANombre: string): string;

{ DB-010 con lo que dijo la base, enmascarado. }
function NegativaDeLaBase(E: Exception; const AConexion: TConexionDb): string;

implementation

uses
  System.Classes, System.StrUtils, System.SyncObjs, System.IOUtils, System.Variants,
  FireDAC.Stan.Intf, FireDAC.Stan.Option, FireDAC.Stan.Error, FireDAC.Stan.Def,
  FireDAC.Stan.Async, FireDAC.Stan.Consts, FireDAC.Phys.Intf, FireDAC.Phys,
  FireDAC.Phys.MSSQL, FireDAC.Phys.PG, FireDAC.DApt, FireDAC.DatS,
  FireDAC.ConsoleUI.Wait,
  Lsp.Texts, Lsp.Casa,
  Lsp.ConPlazo; // TrabajoConPlazo: el plazo lo pone el servidor, no el driver

const
  // el fichero de contrasenas que se le da a libpq para que no lea el de la
  // cuenta: NO EXISTE (en la casa del motor, donde ningun agente escribe)
  FICHERO_SIN_CLAVES = 'sin-claves.pgpass';

var
  // los drivers que cargan su DLL de la casa, con el enlace que la fija:
  // uno por motor enlazado que la necesita. Se crean al arrancar (abajo) y
  // no al primer uso: dos peticiones a la vez no crean dos.
  GPg: TFDPhysPgDriverLink = nil;

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
  if MatchText(S_FD_ConnParam_PG_PGAdvanced, Del) then
    AConn.Params.Values[S_FD_ConnParam_PG_PGAdvanced] :=
      'passfile=' + TPath.Combine(CarpetaDeDriverDeBd(C.Motor), FICHERO_SIN_CLAVES);
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
    Kind: TFDCommandExceptionKind;
    Mensaje: string;
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
  if not TrabajoConPlazo(
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
  Claves := TStringList.Create;
  M := TFDMetaInfoQuery.Create(nil);
  try
    AConn.GetKeyFieldNames('', AConn.CurrentSchema, ATabla, '', Claves);
    M.Connection := AConn;
    M.MetaInfoKind := mkTableFields;
    M.SchemaName := AConn.CurrentSchema;
    M.ObjectName := ATabla;
    M.Open;
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

function CitaNombre(AConn: TFDConnection; const ANombre: string): string;
begin
  Result := AConn.ConnectionMetaDataIntf.QuoteObjName(ANombre, npObject);
end;

function NegativaDeLaBase(E: Exception; const AConexion: TConexionDb): string;
begin
  Result := MsgFmt(SR_DB_RESPONDE_FMT, [NombreDeConexion(AConexion),
    TextoDelMotor(E.Message, AConexion)]);
end;

initialization
  GPg := TFDPhysPgDriverLink.Create(nil);
  GPg.VendorHome := CarpetaDeDriverDeBd(GPg.BaseDriverID);

finalization
  FreeAndNil(GPg);

end.
