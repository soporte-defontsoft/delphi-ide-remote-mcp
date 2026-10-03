unit Lsp.Sandbox;

{ La jaula de delphi_test: un AppContainer de Windows POR EJECUCION. El test
  corre dentro, sobre una COPIA de su carpeta de salida en la casa del
  servidor (ServerTempDir), y el contenedor no tiene ninguna capacidad: no ve
  la red ni las unidades de red, y no lee ni escribe nada fuera de la carpeta
  que se le da. Nace con la peticion y se borra con la respuesta.

  Por que no la baja integridad de antes (2-oct-2026, medido): la etiqueta de
  integridad solo la hace cumplir Windows en el disco LOCAL. Un test a
  integridad baja escribia en una unidad de red (N:) con las credenciales de
  la sesion, leia cualquier fichero y abria conexiones; y en una raiz de red
  ni su propia salida se podia etiquetar (Samba no guarda la etiqueta). En el
  contenedor, medido: escribe solo en su carpeta y no sube de ella ni para
  leer, N: no existe ni por letra ni por UNC, no hay red, y dos tests vivos en
  contenedores distintos no se ven. Crear y borrar uno cuesta unos 30 ms.

  Lo que NO hay, decidido asi (David, 2-oct-2026): red (localhost se queda
  colgado hasta que TCP se rinde, unos 21 s), paquetes en tiempo de ejecucion
  (los .bpl de fuera de Program Files no se leen) y nada del proyecto que no
  viaje en su carpeta de salida. Es una jaula para tests de logica. }

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.IOUtils;

type
  { Un AppContainer de UNA ejecucion. Nombre es el perfil registrado (lo
    compone CreaContenedor, con la marca de esta casa del servidor) y Sid el
    suyo, que suelta BorraContenedor. }
  TContenedor = record
    Nombre: string;
    Sid: PSID;
    // Handles prestados de esta ejecucion: no se cierran, solo se quita SU ACE.
    Estacion, Escritorio: THandle;
  end;
  PContenedor = ^TContenedor;

{ Registra un contenedor nuevo, sin ninguna capacidad. 0 si lo hay; si no, el
  codigo que dio Windows (un HRESULT) y AC queda vacio. }
function CreaContenedor(out AC: TContenedor): DWORD;

{ Lo borra (el perfil y la carpeta que le hace Windows) y suelta el SID. Con
  AC vacio no hace nada, y nunca lanza. Se llama con el proceso ya muerto. }
procedure BorraContenedor(var AC: TContenedor);

{ Da al contenedor una carpeta VACIA recien creada por el servidor: permisos
  PROPIOS, no los de donde vive (el sistema, los administradores y esta
  cuenta con control total; el contenedor con modificar), heredables: lo
  que se copie DESPUES dentro es del contenedor (medido con la base
  preparada antes de copiar, 2-oct-2026). Sin etiqueta de integridad: el
  proceso del contenedor es de integridad baja, y aun asi escribe con este
  permiso y nada mas - medido con un mutante sin ella, la bateria entera
  siguio verde; era una llamada de mas que podia fallar. 0 o el error. }
function PreparaCarpetaDelContenedor(const AC: TContenedor;
  const ADir: string): DWORD;

{ CreateProcess DENTRO del contenedor, heredando handles (la tuberia de la
  salida) como el de siempre, y con el entorno SIN la configuracion del
  servidor (DELPHI_MCP_*: raices, tokens, interruptores): el test no ve con
  que se configuro quien lo lanza - medido el 2-oct-2026, las unitarias del
  propio servidor pasaban porque heredaban sus raices. False con GetLastError
  si Windows no lo lanza; no lanza excepciones: quien llama decide, y no
  poder lanzar dentro NO es lanzar fuera. }
function CreateProcessEnContenedor(const AC: TContenedor; const ACmdLine: string;
  AWorkDir: PChar; ACreateFlags: DWORD; const ASI: TStartupInfo;
  out API: TProcessInformation): Boolean;

{ Al arrancar: borra los contenedores de ESTA casa que dejo una caida. Los
  de otro servidor de la misma cuenta (una bateria, una segunda instalacion)
  llevan otra marca y no se tocan: pueden estar en uso. Nunca lanza. }
procedure PurgaContenedoresHuerfanos;

{ ONE handle-inheriting launch at a time. CreateProcess with
  bInheritHandles=True hands the child EVERY inheritable handle the process
  has at that instant, and the pipe ends made for a child are inheritable
  from CreatePipe until the parent closes its copy: two launches that
  overlap, and one child takes the other's pipe. Measured 2026-09-29: with
  two DelphiLSP engines starting together the second inherited the write end
  of the first one's output; when the first was stopped its reader never saw
  the end of the pipe and the stop did not return - a folder delete hung,
  with the global write lock held, until the second engine was killed from
  outside. Whoever launches inheriting handles wraps in this from the moment
  it creates its pipes until it has closed the child's ends. The two that
  do: the LSP transport and the build/git/test runner. }
procedure EnterSpawn;
procedure LeaveSpawn;

implementation

uses
  System.Classes,
  System.StrUtils,
  System.Win.Registry,
  Lsp.Guard, // ServerDir y ClaveDeCarpeta: la marca de esta casa
  MCPServer.Logger,
  Lsp.Texts,
  Lsp.ProcessLaunch;

var
  GSpawnLock: TObject;

procedure EnterSpawn;
begin
  System.TMonitor.Enter(GSpawnLock);
end;

procedure LeaveSpawn;
begin
  System.TMonitor.Exit(GSpawnLock);
end;

const
  CONTENEDOR_PREFIJO = 'DelphiLspMcp.Test.';
  // donde apunta Windows cada perfil: Mappings\<SID>\Moniker, con el nombre
  // en minusculas (medido 2-oct-2026; al borrarlo, la entrada se va)
  MAPPINGS_KEY = 'Software\Classes\Local Settings\Software\Microsoft\Windows\' +
    'CurrentVersion\AppContainer\Mappings';

function CreateAppContainerProfile(pszAppContainerName, pszDisplayName,
  pszDescription: PWideChar; pCapabilities: Pointer; dwCapabilityCount: DWORD;
  out ppSidAppContainerSid: PSID): HRESULT; stdcall; external 'userenv.dll';

function DeleteAppContainerProfile(pszAppContainerName: PWideChar): HRESULT;
  stdcall; external 'userenv.dll';


function ConvertStringSecurityDescriptorToSecurityDescriptorW(
  StringSD: PWideChar; Revision: DWORD; out SD: PSECURITY_DESCRIPTOR;
  SDSize: PULONG): BOOL; stdcall;
  external 'advapi32.dll';

function ConvertSidToStringSidW(Sid: PSID; out StringSid: PWideChar): BOOL;
  stdcall; external 'advapi32.dll';

function SetFileSecurityW(FileName: PWideChar; SecurityInformation: DWORD;
  SD: PSECURITY_DESCRIPTOR): BOOL; stdcall; external 'advapi32.dll';

function ConvertStringSidToSidW(StringSid: PWideChar; out Sid: PSID): BOOL;
  stdcall; external 'advapi32.dll';

// El descriptor de un objeto de ventanas (estacion, escritorio): propias
// porque Winapi.Windows pide el SI por valor y el API lo quiere por puntero
function GetUserObjectSecurity_(hObj: THandle; var pSIRequested: DWORD;
  pSD: Pointer; nLength: DWORD; var lpnLengthNeeded: DWORD): BOOL; stdcall;
  external user32 name 'GetUserObjectSecurity';

function SetUserObjectSecurity_(hObj: THandle; var pSIRequested: DWORD;
  pSD: Pointer): BOOL; stdcall; external user32 name 'SetUserObjectSecurity';

{ La marca de esta casa del servidor (la carpeta del exe), en el nombre de
  cada contenedor: cada servidor de la misma cuenta purga solo los suyos.
  LA clave de una carpeta (ClaveDeCarpeta), sus 8 primeros: el nombre de un
  contenedor no pasa de 64. }
function MarcaDeEstaCasa: string;
begin
  Result := ClaveDeCarpeta(ServerDir).Substring(0, 8);
end;

{ EL comienzo del nombre de todo contenedor de ESTA casa: lo compone quien
  crea uno y lo busca la purga (estaba escrito en los dos sitios; revision
  de la 1.11.0). En minusculas: asi lo guarda Windows en su Moniker. }
function PrefijoDeEstaCasa: string;
begin
  Result := LowerCase(CONTENEDOR_PREFIJO + MarcaDeEstaCasa + '.');
end;

function SidComoTexto(ASid: PSID): string;
var
  P: PWideChar;
begin
  Result := '';
  if (ASid <> nil) and ConvertSidToStringSidW(ASid, P) then
  try
    Result := P;
  finally
    LocalFree(HLOCAL(P));
  end;
end;

function SidDeEstaCuenta: string;
var
  Tok: THandle;
  Buf: array [0 .. 511] of Byte;
  Len: DWORD;
begin
  Result := '';
  if not OpenProcessToken(GetCurrentProcess, TOKEN_QUERY, Tok) then
    Exit;
  try
    if GetTokenInformation(Tok, TokenUser, @Buf, SizeOf(Buf), Len) then
      Result := SidComoTexto(PTokenUser(@Buf)^.User.Sid);
  finally
    CloseHandle(Tok);
  end;
end;

{ El bloque de entorno de este proceso sin las DELPHI_MCP_* (Unicode, cada
  variable terminada en nulo y un nulo mas al final, como lo pide
  CreateProcess). La temporal NO se toca: el AppContainer sobrescribe TMP/TEMP
  con su propia AC\Temp -existente y escribible, borrada con el perfil- y la
  API GetTempPath la devuelve (medido 2-oct-2026; solo TPath.GetTempPath de la
  RTL sale vacio bajo AppContainer, y eso es del binario del test). }
function EntornoSinConfiguracion: string;
var
  P, Q: PChar;
  Linea: string;
begin
  Result := '';
  P := GetEnvironmentStrings;
  if P = nil then
    Exit(#0#0); // un bloque de entorno vacio es DOS nulos, no uno
  try
    Q := P;
    while Q^ <> #0 do
    begin
      Linea := Q;
      if not StartsText('DELPHI_MCP_', Linea) then
        Result := Result + Linea + #0;
      Inc(Q, Length(Linea) + 1);
    end;
  finally
    FreeEnvironmentStrings(P);
  end;
  Result := Result + #0;
end;

{ Un descriptor de seguridad en SDDL puesto sobre ADir con AQue. 0 o el error. }
function PonDescriptor(const ADir, ASddl: string; AQue: DWORD): DWORD;
var
  SD: PSECURITY_DESCRIPTOR;
begin
  SD := nil;
  if not ConvertStringSecurityDescriptorToSecurityDescriptorW(PWideChar(ASddl),
    1 {SDDL_REVISION_1}, SD, nil) then
    Exit(GetLastError);
  try
    if SetFileSecurityW(PWideChar(ADir), AQue, SD) then
      Result := 0
    else
      Result := GetLastError;
  finally
    LocalFree(HLOCAL(SD));
  end;
end;

function CreaContenedor(out AC: TContenedor): DWORD;
var
  Hr: HRESULT;
  G: string;
begin
  AC.Sid := nil;
  AC.Estacion := GetProcessWindowStation;
  AC.Escritorio := GetThreadDesktop(GetCurrentThreadId);
  // 'DelphiLspMcp.Test.' + 8 + '.' + 32 = 59: el limite de Windows es 64
  G := TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '').Replace('-', '');
  AC.Nombre := PrefijoDeEstaCasa + LowerCase(G);
  Hr := CreateAppContainerProfile(PChar(AC.Nombre), PChar(AC.Nombre),
    PChar(AC.Nombre), nil, 0, AC.Sid);
  if Hr = S_OK then
    Exit(0);
  AC.Nombre := '';
  AC.Sid := nil;
  Result := DWORD(Hr);
end;

function PermisoDeVentanas(AObj: THandle; ASid: PSID; AMascara: DWORD;
  const ATipo: string): DWORD; forward;

procedure BorraContenedor(var AC: TContenedor);
var
  Hr: HRESULT;
begin
  if AC.Sid <> nil then
  begin
    PermisoDeVentanas(AC.Escritorio, AC.Sid, 0, 'desktop');
    PermisoDeVentanas(AC.Estacion, AC.Sid, 0, 'window station');
    FreeSid(AC.Sid);
  end;
  AC.Sid := nil;
  AC.Estacion := 0;
  AC.Escritorio := 0;
  if AC.Nombre <> '' then
  begin
    Hr := DeleteAppContainerProfile(PChar(AC.Nombre));
    if Hr <> S_OK then
      try
        TLogger.Warning(MsgFmt(SL_TEST_CONTENEDOR_NO_BORRADO_FMT,
          [AC.Nombre, IntToHex(Cardinal(Hr), 8)]));
      except
        // apuntarlo no puede hacer que borrar lance
      end;
  end;
  AC.Nombre := '';
end;

function PreparaCarpetaDelContenedor(const AC: TContenedor;
  const ADir: string): DWORD;
var
  Yo, Suyo: string;
begin
  Yo := SidDeEstaCuenta;
  Suyo := SidComoTexto(AC.Sid);
  if (Yo = '') or (Suyo = '') then
    Exit(ERROR_INVALID_SID);
  // D:P = permisos propios, no heredados de donde vive. 0x1301bf = modificar
  // (leer, escribir, ejecutar y borrar lo suyo)
  Result := PonDescriptor(ADir,
    'D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;FA;;;' + Yo + ')' +
    '(A;OICI;0x1301bf;;;' + Suyo + ')', DACL_SECURITY_INFORMATION);
end;


{ Una ACE para el SID de ESTA ejecucion, retirada por BorraContenedor.
  La estacion y el escritorio deben admitirlo antes de iniciar user32
  (0xC0000142 del servicio, medido 3-oct-2026). El permiso del escritorio
  aparece solo durante el DUnitX: su SID, 0x81, y al terminar las ACE de antes.
  Los permisos de Windows ya presentes se conservan. Mascara cero retira
  solo el SID de esta ejecucion. El lock serializa las lecturas y escrituras
  de la DACL: dos tests vivos no pueden perder la ACE del otro. }
const
  ACL_REVISION_ = 2;
  ACCESS_ALLOWED_ACE_TYPE_ = 0;
type
  // Winapi.Windows de RAD 13 no trae estos alias; el minimo para leer la
  // cabecera de una ACE y el SID de una de permiso. El recuento y el tamano
  // de la ACL salen del propio TACL (AceCount, AclSize), sin GetAclInformation.
  PCabeceraAce = ^TCabeceraAce;
  TCabeceraAce = packed record
    AceType: Byte;
    AceFlags: Byte;
    AceSize: Word;
  end;
  PAcePermiso = ^TAcePermiso;
  TAcePermiso = packed record
    Cabecera: TCabeceraAce;
    Mask: DWORD;
    SidStart: DWORD;
  end;
function ActualizaPermisoDeVentanas(AObj: THandle; ASid: PSID;
  AMascara: DWORD): DWORD;
var
  Si, Nec, Bytes: DWORD;
  SdViejo, Buf: TBytes;
  PSd: PSECURITY_DESCRIPTOR;
  Hay, PorDefecto: BOOL;
  DaclVieja, DaclNueva: PACL;
  Paquetes: PSID;
  I: Integer;
  PAce: Pointer;
  Nuevo: TSecurityDescriptor;
  Encontrada: Boolean;
begin
  if (AObj = 0) or (ASid = nil) then
    Exit(ERROR_INVALID_PARAMETER);
  Si := DACL_SECURITY_INFORMATION;
  Paquetes := nil;
  // Un permiso de Windows ya presente se conserva; nunca lo ampliamos.
  if (AMascara <> 0) and not ConvertStringSidToSidW('S-1-15-2-1', Paquetes) then
    Exit(GetLastError);
  EnterSpawn;
  try
    Nec := 0;
    GetUserObjectSecurity_(AObj, Si, nil, 0, Nec);
    if Nec = 0 then
      Exit(GetLastError);
    SetLength(SdViejo, Nec);
    if not GetUserObjectSecurity_(AObj, Si, @SdViejo[0], Nec, Nec) then
      Exit(GetLastError);
    PSd := @SdViejo[0];
    if not GetSecurityDescriptorDacl(PSd, Hay, DaclVieja, PorDefecto) then
      Exit(GetLastError);
    if (not Hay) or (DaclVieja = nil) then
      Exit(0);
    Encontrada := False;
    for I := 0 to Integer(DaclVieja^.AceCount) - 1 do
    begin
      if not GetAce(DaclVieja^, I, PAce) then
        Exit(GetLastError);
      if PCabeceraAce(PAce)^.AceType <> ACCESS_ALLOWED_ACE_TYPE_ then
        Continue;
      if EqualSid(PSID(@PAcePermiso(PAce)^.SidStart), ASid) then
        Encontrada := True;
      if (Paquetes <> nil) and EqualSid(
        PSID(@PAcePermiso(PAce)^.SidStart), Paquetes) then
        // Una ACE parcial no sustituye a los derechos necesarios del objeto.
        if (PAcePermiso(PAce)^.Mask and AMascara) = AMascara then
          Exit(0);
    end;
    if ((AMascara <> 0) and Encontrada) or
       ((AMascara = 0) and not Encontrada) then
      Exit(0);
    Bytes := DaclVieja^.AclSize;
    if AMascara <> 0 then
      Inc(Bytes, SizeOf(TAcePermiso) + GetLengthSid(ASid) - SizeOf(DWORD));
    SetLength(Buf, Bytes);
    DaclNueva := PACL(@Buf[0]);
    if not InitializeAcl(DaclNueva^, Bytes, ACL_REVISION_) then
      Exit(GetLastError);
    for I := 0 to Integer(DaclVieja^.AceCount) - 1 do
    begin
      if not GetAce(DaclVieja^, I, PAce) then
        Exit(GetLastError);
      // Mascara cero retira solo las ACE de permiso de ESTE contenedor.
      if (AMascara = 0) and
         (PCabeceraAce(PAce)^.AceType = ACCESS_ALLOWED_ACE_TYPE_) and
         EqualSid(PSID(@PAcePermiso(PAce)^.SidStart), ASid) then
        Continue;
      if not AddAce(DaclNueva^, ACL_REVISION_, MAXDWORD, PAce,
        PCabeceraAce(PAce)^.AceSize) then
        Exit(GetLastError);
    end;
    if (AMascara <> 0) and not AddAccessAllowedAce(DaclNueva^,
      ACL_REVISION_, AMascara, ASid) then
      Exit(GetLastError);
    if not InitializeSecurityDescriptor(@Nuevo, SECURITY_DESCRIPTOR_REVISION) then
      Exit(GetLastError);
    if not SetSecurityDescriptorDacl(@Nuevo, True, DaclNueva, False) then
      Exit(GetLastError);
    if not SetUserObjectSecurity_(AObj, Si, @Nuevo) then
      Exit(GetLastError);
    Result := 0;
  finally
    LeaveSpawn;
    if Paquetes <> nil then
      LocalFree(HLOCAL(Paquetes));
  end;
end;

function PermisoDeVentanas(AObj: THandle; ASid: PSID; AMascara: DWORD;
  const ATipo: string): DWORD;
begin
  Result := ActualizaPermisoDeVentanas(AObj, ASid, AMascara);
  if Result <> 0 then
    try
      TLogger.Warning(MsgFmt(SL_TEST_ESTACION_FMT, [ATipo, Result]));
    except
      // Un fallo del log no sustituye al error de Windows.
    end;
end;

function CreateProcessEnContenedor(const AC: TContenedor; const ACmdLine: string;
  AWorkDir: PChar; ACreateFlags: DWORD; const ASI: TStartupInfo;
  out API: TProcessInformation): Boolean;
var
  Entorno: string;
  Err: DWORD;
begin
  Result := False;
  FillChar(API, SizeOf(API), 0);
  if AC.Sid = nil then
  begin
    SetLastError(ERROR_INVALID_SID);
    Exit;
  end;
  // Minimo medido en estacion privada: leer seguridad y usar atomos globales.
  Err := PermisoDeVentanas(AC.Estacion, AC.Sid,
    READ_CONTROL or WINSTA_ACCESSGLOBALATOMS, 'window station');
  if Err = 0 then
    Err := PermisoDeVentanas(AC.Escritorio, AC.Sid,
      DESKTOP_READOBJECTS or DESKTOP_WRITEOBJECTS, 'desktop');
  if Err <> 0 then
  begin
    SetLastError(Err);
    Exit;
  end;
  Entorno := EntornoSinConfiguracion;
  Result := CreateProcessConHandles(ACmdLine, AWorkDir,
    ACreateFlags or CREATE_UNICODE_ENVIRONMENT, PChar(Entorno), ASI, API, AC.Sid);
end;

procedure PurgaContenedoresHuerfanos;
var
  R: TRegistry;
  Sids: TStringList;
  Mio, Moniker: string;
begin
  Mio := PrefijoDeEstaCasa;
  try
    R := TRegistry.Create(KEY_READ);
    Sids := TStringList.Create;
    try
      R.RootKey := HKEY_CURRENT_USER;
      if not R.OpenKeyReadOnly(MAPPINGS_KEY) then
        Exit;
      R.GetKeyNames(Sids);
      R.CloseKey;
      for var S in Sids do
        if R.OpenKeyReadOnly(MAPPINGS_KEY + '\' + S) then
        try
          if R.ValueExists('Moniker') then
          begin
            Moniker := R.ReadString('Moniker');
            if StartsText(Mio, Moniker) then
              DeleteAppContainerProfile(PChar(Moniker));
          end;
        finally
          R.CloseKey;
        end;
    finally
      Sids.Free;
      R.Free;
    end;
  except
    // arrancar no puede fallar por no poder limpiar
  end;
end;

initialization
  GSpawnLock := TObject.Create;

finalization
  GSpawnLock.Free;

end.
