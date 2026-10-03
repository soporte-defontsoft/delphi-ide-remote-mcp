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
  Lsp.Texts;

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
  PROC_THREAD_ATTRIBUTE_SECURITY_CAPABILITIES_ = $00020009;
  PROC_THREAD_ATTRIBUTE_HANDLE_LIST_ = $00020002;
  EXTENDED_STARTUPINFO_PRESENT_ = $00080000;

type
  TSecurityCapabilities = record
    AppContainerSid: PSID;
    Capabilities: Pointer; // ninguna: ni red ni nada
    CapabilityCount: DWORD;
    Reserved: DWORD;
  end;

  TStartupInfoExW_ = record
    StartupInfo: TStartupInfo;
    lpAttributeList: Pointer;
  end;

function CreateAppContainerProfile(pszAppContainerName, pszDisplayName,
  pszDescription: PWideChar; pCapabilities: Pointer; dwCapabilityCount: DWORD;
  out ppSidAppContainerSid: PSID): HRESULT; stdcall; external 'userenv.dll';

function DeleteAppContainerProfile(pszAppContainerName: PWideChar): HRESULT;
  stdcall; external 'userenv.dll';

// Propias y no las de Winapi.Windows: alli lpReturnSize es un "var", y el API
// lo quiere NULL (reservado)
function InitializeProcThreadAttributeList_(lpAttributeList: Pointer;
  dwAttributeCount, dwFlags: DWORD; var lpSize: NativeUInt): BOOL; stdcall;
  external kernel32 name 'InitializeProcThreadAttributeList';

function UpdateProcThreadAttribute_(lpAttributeList: Pointer; dwFlags: DWORD;
  Attribute: NativeUInt; lpValue: Pointer; cbSize: NativeUInt;
  lpPreviousValue, lpReturnSize: Pointer): BOOL; stdcall;
  external kernel32 name 'UpdateProcThreadAttribute';

procedure DeleteProcThreadAttributeList_(lpAttributeList: Pointer); stdcall;
  external kernel32 name 'DeleteProcThreadAttributeList';

function ConvertStringSecurityDescriptorToSecurityDescriptorW(
  StringSD: PWideChar; Revision: DWORD; out SD: PSECURITY_DESCRIPTOR;
  SDSize: PULONG): BOOL; stdcall;
  external 'advapi32.dll';

function ConvertSidToStringSidW(Sid: PSID; out StringSid: PWideChar): BOOL;
  stdcall; external 'advapi32.dll';

function SetFileSecurityW(FileName: PWideChar; SecurityInformation: DWORD;
  SD: PSECURITY_DESCRIPTOR): BOOL; stdcall; external 'advapi32.dll';

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

procedure BorraContenedor(var AC: TContenedor);
var
  Hr: HRESULT;
begin
  if AC.Sid <> nil then
    FreeSid(AC.Sid);
  AC.Sid := nil;
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

{ Los handles que el hijo debe heredar: los stdhandles del arranque y nada
  mas. Con bInheritHandles=True, CreateProcess pasa al hijo TODO handle
  heredable del servidor (el socket de escucha de Indy entre ellos) salvo que
  se le de ESTA lista; la jaula hereda solo su tuberia (revision 1.11.0). }
function HandlesDeArranque(const ASI: TStartupInfo): TArray<THandle>;

  function YaEsta(const A: TArray<THandle>; H: THandle): Boolean;
  var
    X: THandle;
  begin
    Result := False;
    for X in A do
      if X = H then
        Exit(True);
  end;

  procedure Anade(H: THandle);
  begin
    if (H <> 0) and (H <> INVALID_HANDLE_VALUE) and not YaEsta(Result, H) then
      Result := Result + [H];
  end;

begin
  Result := [];
  if (ASI.dwFlags and STARTF_USESTDHANDLES) = 0 then
    Exit;
  Anade(ASI.hStdInput);
  Anade(ASI.hStdOutput);
  Anade(ASI.hStdError);
end;

function CreateProcessEnContenedor(const AC: TContenedor; const ACmdLine: string;
  AWorkDir: PChar; ACreateFlags: DWORD; const ASI: TStartupInfo;
  out API: TProcessInformation): Boolean;
var
  Caps: TSecurityCapabilities;
  Tam: NativeUInt;
  Lista: Pointer;
  SIX: TStartupInfoExW_;
  Cmd, Entorno: string;
  Err: DWORD;
  H: TArray<THandle>;
  NAttrs: DWORD;
  Hereda: BOOL;
begin
  Result := False;
  FillChar(API, SizeOf(API), 0);
  if AC.Sid = nil then
  begin
    SetLastError(ERROR_INVALID_SID);
    Exit;
  end;
  FillChar(Caps, SizeOf(Caps), 0);
  Caps.AppContainerSid := AC.Sid;
  H := HandlesDeArranque(ASI);
  Hereda := Length(H) > 0;
  if Hereda then NAttrs := 2 else NAttrs := 1;
  Tam := 0;
  InitializeProcThreadAttributeList_(nil, NAttrs, 0, Tam);
  GetMem(Lista, Tam);
  try
    if not InitializeProcThreadAttributeList_(Lista, NAttrs, 0, Tam) then
      Exit;
    try
      if not UpdateProcThreadAttribute_(Lista, 0,
        PROC_THREAD_ATTRIBUTE_SECURITY_CAPABILITIES_, @Caps, SizeOf(Caps),
        nil, nil) then
        Exit;
      // SOLO la tuberia de salida se hereda: con bInheritHandles=True y sin
      // esta lista el hijo heredaba TODO handle heredable del servidor
      if Hereda and not UpdateProcThreadAttribute_(Lista, 0,
        PROC_THREAD_ATTRIBUTE_HANDLE_LIST_, @H[0], Length(H) * SizeOf(THandle),
        nil, nil) then
        Exit;
      FillChar(SIX, SizeOf(SIX), 0);
      SIX.StartupInfo := ASI;
      SIX.StartupInfo.cb := SizeOf(SIX);
      SIX.lpAttributeList := Lista;
      Cmd := ACmdLine;
      UniqueString(Cmd);
      Entorno := EntornoSinConfiguracion;
      Result := CreateProcess(nil, PChar(Cmd), nil, nil, Hereda,
        ACreateFlags or EXTENDED_STARTUPINFO_PRESENT_ or
        CREATE_UNICODE_ENVIRONMENT, PChar(Entorno), AWorkDir,
        PStartupInfo(@SIX)^, API);
    finally
      Err := GetLastError;
      DeleteProcThreadAttributeList_(Lista);
      SetLastError(Err);
    end;
  finally
    Err := GetLastError;
    FreeMem(Lista);
    SetLastError(Err);
  end;
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
