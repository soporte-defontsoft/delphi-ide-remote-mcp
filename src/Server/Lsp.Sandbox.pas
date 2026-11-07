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
  viaje en su carpeta de salida. Es una jaula para tests de logica.

  El NOMBRE del contenedor no es de una ejecucion sino de un PUESTO de esta
  casa (NombreDeContenedor): cada ejecucion toma el primero libre, le registra
  un perfil nuevo y lo borra al acabar. Windows da a cada SID de contenedor
  distinto una entrada de la sesion que no suelta hasta que la sesion acaba
  (TokenAppContainerNumber; medido el 4-nov-2026: veinte nombres nuevos
  seguidos, veinte numeros nuevos; el mismo nombre, borrado y recreado, siempre
  el mismo). Con un nombre nuevo por ejecucion, tras ocho dias de baterias la
  sesion ya no lanzaba ningun proceso en un contenedor (CreateProcess 1450, C29
  de la 1.27). Dos ejecuciones vivas siguen en puestos distintos. }

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.IOUtils;

type
  { Un AppContainer de UNA ejecucion. Nombre es el perfil registrado, el de su
    puesto (NombreDeContenedor, con la marca de esta casa del servidor), Sid el
    suyo, que suelta BorraContenedor, y Puesto el semaforo que lo reserva
    mientras dura la ejecucion. }
  TContenedor = record
    Nombre: string;
    Sid: PSID;
    // Handles prestados de esta ejecucion: no se cierran, solo se quita SU ACE.
    Estacion, Escritorio: THandle;
    // Lo pone quien va a lanzar un programa con ventanas (el renderizador, aunque
    // no se vean): un test de consola no las crea, y no las pide.
    ConVentanas: Boolean;
    Puesto: THandle;
  end;
  PContenedor = ^TContenedor;

{ Toma el primer puesto libre de esta casa y registra en el un perfil NUEVO,
  sin ninguna capacidad (el que dejo una caida se borra antes; el de un puesto
  cuyo perfil Windows no deja quitar se retira y se prueba otro; sin ninguno
  libre, un nombre de una sola ejecucion). 0 si lo hay; si no, el codigo que dio
  Windows (un HRESULT) y AC queda vacio. }
function CreaContenedor(out AC: TContenedor): DWORD;

{ Lo borra (el perfil y la carpeta que le hace Windows), suelta el SID y
  devuelve su puesto. Con AC vacio no hace nada, y nunca lanza. Se llama con el
  proceso ya muerto. }
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

{ Una carpeta VACIA recien creada que TODOS los contenedores pueden leer y
  ejecutar, y ninguno escribir: lo que se copie despues dentro lo hereda. Es
  la de lo que comparten y no es de nadie (los paquetes del IDE, V65 de la
  1.24): un ACE por contenedor serian dos escritores de la misma DACL y un
  permiso a propagar por cientos de ficheros en cada ejecucion. 0 o el error. }
function PreparaCarpetaParaLosContenedores(const ADir: string): DWORD;

{ La etapa de UNA ejecucion en un contenedor: el contenedor sin capacidades -con
  ventanas si AConVentanas- y su carpeta AEtapa, creada vacia y SUYA
  (PreparaCarpetaDelContenedor). 0 o el error de Windows, y entonces no queda
  nada, ni contenedor ni carpeta; si crear la carpeta lanza, tampoco. La abrian a
  mano los cuatro que corren algo en un contenedor (el renderizador, el conversor
  de estilos, brcc32 y delphi_test: C13 del revisor del paisaje del cierre de la
  1.26). }
function AbreEtapa(const AEtapa: string; AConVentanas: Boolean; out AC: TContenedor): DWORD;

{ ...y su final, el UNICO: el contenedor fuera y la carpeta recuperada
  (ReclamaArbol: una que dejo cerrada lo que corrio dentro, el codigo de un
  paquete o de un test) y borrada sin cruzar enlaces. Con lo que AbreEtapa no
  llego a hacer, nada. Nunca lanza: '' o por que la carpeta se quedo, que se lleva
  la purga del arranque; entonces su puesto no se devuelve mientras viva este
  proceso (la carpeta da permiso a SU SID). El conversor y brcc32 no la
  recuperaban. }
function CierraEtapa(var AC: TContenedor; const AEtapa: string): string;

{ CreateProcess DENTRO del contenedor, heredando handles (la tuberia de la
  salida) como el de siempre, y con el entorno SIN la configuracion del
  servidor (DELPHI_MCP_*: raices, tokens, interruptores): el test no ve con
  que se configuro quien lo lanza - medido el 2-oct-2026, las unitarias del
  propio servidor pasaban porque heredaban sus raices. False con GetLastError
  si Windows no lo lanza; no lanza excepciones: quien llama decide, y no
  poder lanzar dentro NO es lanzar fuera. AEntorno, si va, el bloque entero
  (EntornoSinConfiguracion con lo que el hijo necesite fijo). }
function CreateProcessEnContenedor(const AC: TContenedor; const ACmdLine: string;
  AWorkDir: PChar; ACreateFlags: DWORD; const ASI: TStartupInfo;
  out API: TProcessInformation; const AEntorno: string = ''): Boolean;

{ Al arrancar: borra los contenedores de ESTA casa que dejo una caida; uno
  cuyo puesto tiene tomado otro proceso de la casa esta en uso y se queda. Los
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

const
  { El SID de LocalSystem: "S-1-5-18", en cualquier idioma de Windows. }
  SID_DE_LOCALSYSTEM = 'S-1-5-18';

{ El SID de la cuenta de este proceso, leido de su token ('' si no se pudo). }
function SidDeEstaCuenta: string;

{ El nombre de la cuenta de este proceso, el que dice Windows. Del entorno se leia
  en dos sitios (USERNAME), y ese lo pone quien lanza el proceso. }
function NombreDeEstaCuenta: string;

{ El SID de la cuenta de este proceso, el de su token, dentro de ABuf (el
  TOKEN_USER entero, del tamano que pide Windows); nil si no se lee. EL lector: lo
  leian a mano SidDeEstaCuenta y el reclamo de una DACL (Lsp.Guard), cada uno con
  su bufer (revisor del paisaje de la 1.26, 19). }
function SidDelProceso(out ABuf: TArray<Byte>): PSID;

{ DOMINIO\cuenta de este proceso como la dice Windows (LookupAccountSid de su SID:
  NT AUTHORITY\SYSTEM para LocalSystem, en el idioma de Windows); '' si no se
  sabe. Se componia con USERDOMAIN del entorno, que pone quien lanza el proceso
  (revisor del paisaje de la 1.26, 13). }
function CuentaDeEsteProceso: string;

{ Un solo lector del entorno: sin secretos del servidor y con ajustes fijos
  del hijo. No modifica el entorno del servidor ni carreras entre llamadas. }
function EntornoSinConfiguracion(const AFijas: TArray<string> = nil): string;

{ Las lineas NOMBRE=valor del entorno de ESTE proceso, en el orden del bloque
  (GetEnvironmentStrings): EL recorrido del bloque, el de
  EntornoSinConfiguracion y el de Lsp.BaseDeDatos.QuitaEntornoDeLibpq. }
function LineasDelEntorno: TArray<string>;

{ EL entorno de un hijo del servidor: el que se le da o, sin darlo, el de este
  proceso sin la configuracion (EntornoSinConfiguracion). Sin darlo, paclient,
  adb y su demonio, reg.exe y el motor heredaban el entorno ENTERO, el token
  incluido (colaterales de A1 de la 1.27, medido con test_entorno_hijos_127). Lo
  preguntan todos los que lanzan: RunCore, RunDetached, el motor y el
  contenedor, que lo tenia escrito aparte. }
function EntornoDelHijo(const AEntorno: string = ''): string;

{ Lo que msbuild ve de una variable del entorno del servidor: su valor, y las
  de la configuracion (DELPHI_MCP_*), que no le llegan, vacias. Lo preguntaban
  dos, y uno no las quitaba: EL prefijo, aqui (P5 del revisor). }
function VariableQueVeElBuild(const ANombre: string): string;

implementation

uses
  System.Classes,
  System.StrUtils,
  System.Win.Registry,
  MCPServer.Logger,
  Lsp.Texts,
  Lsp.ProcessLaunch,
  Lsp.Casa, // ServerDir y ClaveDeCarpeta: la marca de esta casa
  Lsp.Guard;

const
  PREFIJO_DE_CONFIGURACION = 'DELPHI_MCP_';

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

const
  // cuantas ejecuciones en contenedor a la vez admite una casa: una por puesto
  PUESTOS_POR_CASA = 64;
  // HRESULT_FROM_WIN32(ERROR_ALREADY_EXISTS): el perfil que dejo una caida en su puesto
  HR_PERFIL_YA_EXISTE = HRESULT($800700B7);

  // lo que se espera entre dos intentos de recuperar un puesto retirado: el
  // borrado de lo que no se deja borrar cuesta sus reintentos (ConReintentos)
  RETIRADO_REINTENTO_MS = 2000;

type
  { Un puesto fuera de uso: su semaforo, tomado mientras siga asi, y lo que lo
    retiro - la etapa que no se pudo borrar (con permiso para SU SID) o el perfil
    que Windows no quito. }
  TPuestoRetirado = record
    Semaforo: THandle;
    Nombre, Etapa: string;
    PerfilQueda: Boolean;
    UltimoIntento: UInt64;
  end;

var
  GPuestosLock: TObject;
  GPuestosRetirados: TArray<TPuestoRetirado>;

{ EL nombre del contenedor del puesto APuesto de esta casa, el que registra
  CreaContenedor (y su SID, que Windows deriva del nombre) }
function NombreDeContenedor(APuesto: Integer): string;
begin
  Result := PrefijoDeEstaCasa + IntToStr(APuesto);
end;

{ El semaforo que reserva el puesto de un contenedor, de su nombre: de cuenta
  uno, sin dueno por hilo (lo suelta quien acaba, no quien empezo), con EL
  nombrador de los objetos con nombre de la casa (NombreDeMutex, Global\): lo ven
  el servicio y un stdio del mismo exe, en sesiones distintas y con los mismos
  perfiles (son del usuario, no de la sesion; con Local\ los dos tomaban el puesto
  0: revisores de la 1.27). Windows lo cierra si el proceso que lo tiene muere. }
function SemaforoDePuesto(const ANombre: string): string;
begin
  Result := NombreDeMutex(ANombre);
end;

{ El primer puesto libre de esta casa: su nombre y su semaforo, tomado. Se
  saltan el que tiene otra ejecucion (de este proceso o de otro de la casa), el
  retirado y el que no se deja abrir (otro objeto con ese nombre). Sin ninguno,
  un nombre de UNA sola ejecucion, sin semaforo: gasta una entrada de la sesion
  (C29), pero ningun estado de los puestos deja sin contenedor a nadie. }
procedure TomaPuesto(out ANombre: string; out ASemaforo: THandle);
begin
  ASemaforo := 0;
  for var I := 0 to PUESTOS_POR_CASA - 1 do
  begin
    var Nombre := NombreDeContenedor(I);
    var S := CreateSemaphore(nil, 1, 1, PChar(SemaforoDePuesto(Nombre)));
    if S = 0 then
      Continue;
    if WaitForSingleObject(S, 0) = WAIT_OBJECT_0 then
    begin
      ANombre := Nombre;
      ASemaforo := S;
      Exit;
    end;
    CloseHandle(S);
  end;
  // 'delphilspmcp.test.' + 8 + '.u' + 32 = 60: el limite de Windows es 64
  ANombre := PrefijoDeEstaCasa + 'u' +
    LowerCase(TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '').Replace('-', ''));
  try
    TLogger.Warning(MsgFmt(SL_CONTENEDOR_SIN_PUESTO_FMT, [PUESTOS_POR_CASA]));
  except
    // apuntarlo no puede dejar sin contenedor
  end;
end;

{ Los puestos retirados vuelven si lo que los retiro ya no esta: la etapa que no
  se pudo borrar se borra ahora, el perfil que Windows no quito se quita ahora;
  lo que sigue sin poder, sigue retirado, y no se reintenta antes de
  RETIRADO_REINTENTO_MS. Lo mira cada contenedor nuevo: algo de un momento (un
  antivirus con un fichero abierto) no se lleva un puesto para siempre, y un test
  que deja algo imborrable no se queda con los 64 (revisor de la 1.27). }
procedure RecuperaRetirados;
var
  Quedan: TArray<TPuestoRetirado>;
  Ahora: UInt64;
begin
  TMonitor.Enter(GPuestosLock);
  try
    if Length(GPuestosRetirados) = 0 then
      Exit;
    Ahora := GetTickCount64;
    Quedan := nil;
    for var R in GPuestosRetirados do
    begin
      var Listo := False;
      if Ahora - R.UltimoIntento >= RETIRADO_REINTENTO_MS then
      begin
        Listo := True;
        if R.Etapa <> '' then
          try
            ReclamaArbol(R.Etapa);
            BorraArbol(R.Etapa); // sin cruzar enlaces: ver Lsp.Guard
          except
            Listo := False;
          end;
        if Listo and R.PerfilQueda then
        begin
          // S_OK, o ya no esta (ERROR_NOT_FOUND, ERROR_FILE_NOT_FOUND)
          var Hr := DeleteAppContainerProfile(PChar(R.Nombre));
          Listo := (Hr = S_OK) or (Hr = HRESULT($80070490)) or (Hr = HRESULT($80070002));
        end;
      end;
      if Listo then
      begin
        ReleaseSemaphore(R.Semaforo, 1, nil);
        CloseHandle(R.Semaforo);
      end
      else
      begin
        var Sigue := R;
        if Ahora - R.UltimoIntento >= RETIRADO_REINTENTO_MS then
          Sigue.UltimoIntento := Ahora;
        Quedan := Quedan + [Sigue];
      end;
    end;
    GPuestosRetirados := Quedan;
  finally
    TMonitor.Exit(GPuestosLock);
  end;
end;

{ Devuelve el puesto de AC para la siguiente ejecucion o, si su etapa AEtapaQueda
  se quedo en disco (con permiso para ESTE SID: la siguiente del puesto la
  alcanzaria) o su perfil no se pudo quitar (APerfilQueda), lo retira: tomado
  hasta que RecuperaRetirados pueda con ello o el proceso acabe; la purga del
  arranque se lleva la etapa. Un nombre de una sola ejecucion no tiene puesto.
  Nunca lanza. }
procedure SueltaPuesto(var AC: TContenedor; const AEtapaQueda: string; APerfilQueda: Boolean);
begin
  if AC.Puesto = 0 then
    Exit;
  if (AEtapaQueda <> '') or APerfilQueda then
  begin
    var R := Default(TPuestoRetirado);
    R.Semaforo := AC.Puesto;
    R.Nombre := AC.Nombre;
    R.Etapa := AEtapaQueda;
    R.PerfilQueda := APerfilQueda;
    R.UltimoIntento := GetTickCount64;
    TMonitor.Enter(GPuestosLock);
    try
      GPuestosRetirados := GPuestosRetirados + [R];
    finally
      TMonitor.Exit(GPuestosLock);
    end;
    try
      TLogger.Warning(MsgFmt(SL_CONTENEDOR_PUESTO_RETIRADO_FMT, [AC.Nombre]));
    except
      // apuntarlo no puede hacer que soltar lance
    end;
  end
  else
  begin
    ReleaseSemaphore(AC.Puesto, 1, nil);
    CloseHandle(AC.Puesto);
  end;
  AC.Puesto := 0;
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

function SidDelProceso(out ABuf: TArray<Byte>): PSID;
var
  Tok: THandle;
  Tam: DWORD;
begin
  Result := nil;
  ABuf := nil;
  if not OpenProcessToken(GetCurrentProcess, TOKEN_QUERY, Tok) then
    Exit;
  try
    Tam := 0;
    GetTokenInformation(Tok, TokenUser, nil, 0, Tam); // pide el tamano
    if Tam = 0 then
      Exit;
    SetLength(ABuf, Tam);
    if GetTokenInformation(Tok, TokenUser, @ABuf[0], Tam, Tam) then
      Result := PTokenUser(@ABuf[0])^.User.Sid;
  finally
    CloseHandle(Tok);
  end;
end;

function SidDeEstaCuenta: string;
var
  Buf: TArray<Byte>;
begin
  Result := SidComoTexto(SidDelProceso(Buf));
end;

function CuentaDeEsteProceso: string;
var
  Buf: TArray<Byte>;
  Nombre, Dominio: array [0 .. 255] of Char;
  LN, LD: DWORD;
  Uso: SID_NAME_USE;
begin
  Result := '';
  var Sid := SidDelProceso(Buf);
  if Sid = nil then
    Exit;
  LN := Length(Nombre);
  LD := Length(Dominio);
  if not LookupAccountSid(nil, Sid, Nombre, LN, Dominio, LD, Uso) then
    Exit;
  Result := string(PChar(@Nombre[0]));
  if Dominio[0] <> #0 then
    Result := string(PChar(@Dominio[0])) + '\' + Result;
end;

function EntornoDelHijo(const AEntorno: string): string;
begin
  Result := AEntorno;
  if Result = '' then
    Result := EntornoSinConfiguracion;
end;

function VariableQueVeElBuild(const ANombre: string): string;
begin
  Result := '';
  if (ANombre <> '') and not StartsText(PREFIJO_DE_CONFIGURACION, ANombre) then
    Result := GetEnvironmentVariable(ANombre);
end;

{ El bloque de entorno de este proceso sin las DELPHI_MCP_* (Unicode, cada
  variable terminada en nulo y un nulo mas al final, como lo pide
  CreateProcess). La temporal NO se toca: el AppContainer sobrescribe TMP/TEMP
  con su propia AC\Temp -existente y escribible, borrada con el perfil- y la
  API GetTempPath la devuelve (medido 2-oct-2026; solo TPath.GetTempPath de la
  RTL sale vacio bajo AppContainer, y eso es del binario del test). }
function LineasDelEntorno: TArray<string>;
var
  P, Q: PChar;
  Linea: string;
begin
  Result := [];
  P := GetEnvironmentStrings;
  if P = nil then
    Exit;
  try
    Q := P;
    while Q^ <> #0 do
    begin
      Linea := Q;
      Result := Result + [Linea];
      Inc(Q, Length(Linea) + 1);
    end;
  finally
    FreeEnvironmentStrings(P);
  end;
end;

function EntornoSinConfiguracion(const AFijas: TArray<string>): string;
var
  Lineas: TStringList;
  Sustituida: Boolean;
begin
  Result := '';
  Lineas := TStringList.Create;
  try
    Lineas.Sorted := True;
    Lineas.CaseSensitive := False;
    for var Linea in LineasDelEntorno do
    begin
      Sustituida := StartsText(PREFIJO_DE_CONFIGURACION, Linea);
      for var Fija in AFijas do
        if StartsText(Copy(Fija, 1, Pos('=', Fija)), Linea) then
          Sustituida := True;
      if not Sustituida then
        Lineas.Add(Linea);
    end;
    // una fija vacia ('NOMBRE=') QUITA la variable, como SET NOMBRE= en cmd:
    // rsvars.bat vacia asi PLATFORM y PlatformSDK, y el build ya no lo lee
    // cmd sino EL lector (Lsp.Discovery.VariablesDeRsVars; 2an de la 1.18.2).
    // De dos fijas con el mismo nombre, la ULTIMA, como la tabla de la puerta
    // (PonEnLaTabla): un TEMP que el operador redefine en el IDE y el de este
    // build iban los dos al bloque, y la tabla se quedaba con el ultimo
    // (revisor del paisaje de la 1.27, B2)
    for var I := 0 to High(AFijas) do
    begin
      var Nombre := Copy(AFijas[I], 1, Pos('=', AFijas[I]));
      if Nombre = '' then
        Continue;
      var Ultima := True;
      for var K := I + 1 to High(AFijas) do
        if StartsText(Nombre, AFijas[K]) then
          Ultima := False;
      if Ultima and (Pos('=', AFijas[I]) < Length(AFijas[I])) then
        Lineas.Add(AFijas[I]);
    end;
    for var Linea in Lineas do
      Result := Result + Linea + #0;
    if Result = '' then
      Result := #0;
    Result := Result + #0;
  finally
    Lineas.Free;
  end;
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
begin
  RecuperaRetirados;
  // un puesto mas que puestos: el ultimo intento, como mucho, es el nombre de una
  // sola ejecucion (TomaPuesto)
  for var Intento := 0 to PUESTOS_POR_CASA do
  begin
    AC := Default(TContenedor);
    // 'DelphiLspMcp.Test.' + 8 + '.' + el puesto: el limite de Windows es 64
    TomaPuesto(AC.Nombre, AC.Puesto);
    Hr := CreateAppContainerProfile(PChar(AC.Nombre), PChar(AC.Nombre),
      PChar(AC.Nombre), nil, 0, AC.Sid);
    // el perfil que dejo una caida en este puesto: fuera, y uno nuevo; nada de
    // aquella ejecucion pasa a esta
    if Hr = HR_PERFIL_YA_EXISTE then
    begin
      DeleteAppContainerProfile(PChar(AC.Nombre));
      Hr := CreateAppContainerProfile(PChar(AC.Nombre), PChar(AC.Nombre),
        PChar(AC.Nombre), nil, 0, AC.Sid);
    end;
    if Hr = S_OK then
    begin
      AC.Estacion := GetProcessWindowStation;
      AC.Escritorio := GetThreadDesktop(GetCurrentThreadId);
      Exit(0);
    end;
    // un perfil que Windows no deja quitar: su puesto se retira y se prueba el
    // siguiente (se tomaba siempre el mismo, el mas bajo, y fallaba todo)
    if (Hr = HR_PERFIL_YA_EXISTE) and (AC.Puesto <> 0) then
    begin
      SueltaPuesto(AC, '', True);
      Continue;
    end;
    SueltaPuesto(AC, '', False);
    AC := Default(TContenedor);
    Exit(DWORD(Hr));
  end;
  AC := Default(TContenedor);
  Result := DWORD(HR_PERFIL_YA_EXISTE);
end;

function PermisoDeVentanas(AObj: THandle; ASid: PSID; AMascara: DWORD;
  const ATipo: string): DWORD; forward;

{ BorraContenedor sin devolver el puesto: lo devuelve quien sabe si se
  retira (CierraEtapa). El nombre se queda, para decir que puesto era. False
  si Windows no quito el perfil: con el puesto, la siguiente ejecucion lo
  heredaria (su carpeta, su AC\Temp). }
function QuitaContenedor(var AC: TContenedor): Boolean;
var
  Hr: HRESULT;
begin
  Result := True;
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
    begin
      Result := False;
      try
        TLogger.Warning(MsgFmt(SL_TEST_CONTENEDOR_NO_BORRADO_FMT,
          [AC.Nombre, IntToHex(Cardinal(Hr), 8)]));
      except
        // apuntarlo no puede hacer que borrar lance
      end;
    end;
  end;
end;

procedure BorraContenedor(var AC: TContenedor);
begin
  var PerfilQuitado := QuitaContenedor(AC);
  SueltaPuesto(AC, '', not PerfilQuitado);
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

function PreparaCarpetaParaLosContenedores(const ADir: string): DWORD;
var
  Yo: string;
begin
  Yo := SidDeEstaCuenta;
  if Yo = '' then
    Exit(ERROR_INVALID_SID);
  // 0x1200a9 = leer y ejecutar; AC = TODOS LOS PAQUETES DE APLICACIONES
  Result := PonDescriptor(ADir,
    'D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;FA;;;' + Yo + ')' +
    '(A;OICI;0x1200a9;;;AC)', DACL_SECURITY_INFORMATION);
end;

function AbreEtapa(const AEtapa: string; AConVentanas: Boolean; out AC: TContenedor): DWORD;
begin
  Result := CreaContenedor(AC);
  if Result <> 0 then
    Exit;
  AC.ConVentanas := AConVentanas;
  try
    CrearCarpeta(AEtapa);
    Result := PreparaCarpetaDelContenedor(AC, AEtapa);
  except
    CierraEtapa(AC, AEtapa);
    raise;
  end;
  if Result <> 0 then
    CierraEtapa(AC, AEtapa);
end;

function CierraEtapa(var AC: TContenedor; const AEtapa: string): string;
begin
  Result := '';
  var PerfilQuitado := QuitaContenedor(AC);
  if AEtapa <> '' then
    try
      ReclamaArbol(AEtapa);
      BorraArbol(AEtapa); // sin cruzar enlaces: ver Lsp.Guard
    except
      on E: Exception do
        Result := E.Message;
    end;
  // una etapa que se queda da permiso al SID de su puesto: no se devuelve hasta
  // que se pueda con ella (RecuperaRetirados)
  SueltaPuesto(AC, (if Result <> '' then AEtapa else ''), not PerfilQuitado);
  AC.Nombre := '';
end;


{ Una ACE para el SID de ESTA ejecucion, retirada por QuitaContenedor.
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
  Exacta, Otra, Cubierta: Boolean;
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
    // la ACE de ESTE SID con la mascara pedida (Exacta) o con otra (Otra): el SID
    // de un puesto se repite entre ejecuciones (C29), y la ACE que dejo colgada
    // un servidor matado no puede dar su mascara a la siguiente (revisor de la
    // 1.27); con mascara cero, toda ACE del SID es Otra
    Exacta := False;
    Otra := False;
    Cubierta := False;
    for I := 0 to Integer(DaclVieja^.AceCount) - 1 do
    begin
      if not GetAce(DaclVieja^, I, PAce) then
        Exit(GetLastError);
      if PCabeceraAce(PAce)^.AceType <> ACCESS_ALLOWED_ACE_TYPE_ then
        Continue;
      if EqualSid(PSID(@PAcePermiso(PAce)^.SidStart), ASid) then
        if (AMascara <> 0) and (PAcePermiso(PAce)^.Mask = AMascara) then
          Exacta := True
        else
          Otra := True;
      // Una ACE parcial no sustituye a los derechos necesarios del objeto.
      if (Paquetes <> nil) and EqualSid(PSID(@PAcePermiso(PAce)^.SidStart), Paquetes) and
         ((PAcePermiso(PAce)^.Mask and AMascara) = AMascara) then
        Cubierta := True;
    end;
    if not Otra and ((AMascara = 0) or Exacta or Cubierta) then
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
      // las ACE de permiso de ESTE contenedor fuera, todas: la que se pide va nueva
      if (PCabeceraAce(PAce)^.AceType = ACCESS_ALLOWED_ACE_TYPE_) and
         EqualSid(PSID(@PAcePermiso(PAce)^.SidStart), ASid) then
        Continue;
      if not AddAce(DaclNueva^, ACL_REVISION_, MAXDWORD, PAce,
        PCabeceraAce(PAce)^.AceSize) then
        Exit(GetLastError);
    end;
    if (AMascara <> 0) and not Cubierta and not AddAccessAllowedAce(DaclNueva^,
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
  out API: TProcessInformation; const AEntorno: string): Boolean;
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
  var Estacion: DWORD := READ_CONTROL or WINSTA_ACCESSGLOBALATOMS;
  var Escritorio: DWORD := DESKTOP_READOBJECTS or DESKTOP_WRITEOBJECTS;
  if AC.ConVentanas then
  begin
    Estacion := Estacion or WINSTA_READATTRIBUTES;
    Escritorio := Escritorio or DESKTOP_CREATEWINDOW or DESKTOP_CREATEMENU;
  end;
  Err := PermisoDeVentanas(AC.Estacion, AC.Sid, Estacion, 'window station');
  if Err = 0 then
    Err := PermisoDeVentanas(AC.Escritorio, AC.Sid, Escritorio, 'desktop');
  if Err <> 0 then
  begin
    SetLastError(Err);
    Exit;
  end;
  Entorno := EntornoDelHijo(AEntorno);
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
            begin
              // con su puesto tomado por otro proceso de esta casa, esta en uso
              var Puesto := CreateSemaphore(nil, 1, 1, PChar(SemaforoDePuesto(Moniker)));
              if Puesto <> 0 then
              try
                if WaitForSingleObject(Puesto, 0) = WAIT_OBJECT_0 then
                try
                  DeleteAppContainerProfile(PChar(Moniker));
                finally
                  ReleaseSemaphore(Puesto, 1, nil);
                end;
              finally
                CloseHandle(Puesto);
              end;
            end;
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

function NombreDeEstaCuenta: string;
var
  Buf: array[0..256] of Char;
  Len: DWORD;
begin
  Len := Length(Buf);
  if GetUserName(Buf, Len) then
    Result := Buf
  else
    Result := '';
end;

initialization
  GSpawnLock := TObject.Create;
  GPuestosLock := TObject.Create;

finalization
  // los semaforos de los puestos retirados no se sueltan: los cierra Windows
  GPuestosLock.Free;
  GSpawnLock.Free;

end.
