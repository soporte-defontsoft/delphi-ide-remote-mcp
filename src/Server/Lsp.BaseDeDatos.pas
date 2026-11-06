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
  Lsp.Conexiones;

{ Los motores de este servidor: los DriverID de los drivers enlazados, como
  los dice FireDAC (FDManager.GetDriverNames). }
function MotoresDeBd: TArray<string>;

{ Por que AConexion no se puede usar en este servidor ('' = se puede): el
  Defecto de su entrada del json, o un motor que el servidor no tiene. Un
  fragmento (SF_DB_DEF_*): la lista de connections lo lleva tal cual, y quien
  la usa lo envuelve en DB-004. }
function DefectoDeConexion(const AConexion: TConexionDb): string;

implementation

uses
  System.SysUtils, System.Classes, System.StrUtils,
  FireDAC.Stan.Intf, FireDAC.Stan.Option, FireDAC.Stan.Error, FireDAC.Stan.Def,
  FireDAC.Stan.Async, FireDAC.Phys.Intf, FireDAC.Phys, FireDAC.Phys.MSSQL,
  FireDAC.Phys.PG, FireDAC.DApt, FireDAC.ConsoleUI.Wait, FireDAC.Comp.Client,
  Lsp.Texts, Lsp.Casa;

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

initialization
  GPg := TFDPhysPgDriverLink.Create(nil);
  GPg.VendorHome := CarpetaDeDriverDeBd(GPg.BaseDriverID);

finalization
  FreeAndNil(GPg);

end.
