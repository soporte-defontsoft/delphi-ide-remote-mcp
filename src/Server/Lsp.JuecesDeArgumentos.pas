unit Lsp.JuecesDeArgumentos;

{ LOS JUECES de los argumentos de una llamada que no son rutas: como se lee un
  argumento (ArgStr, como lo resuelve el enlazador RTTI), el duplicado, el
  perfil de PAServer, lo que viaja a paclient (nombre de proyecto y campos de
  un DeployFile), el dispositivo y cada comando de delphi_adb (ADB_CAMPOS), y
  los de delphi_build y delphi_paserver. Los pregunta la puerta de la llamada
  (Lsp.Guard, ReglasDeLaLlamadaDenegadas) y quien compone esos campos. Vivia
  en Lsp.Guard (V94 de la depuracion de la 1.23, B6 de la 1.28): se mudo sin
  cambiar una linea. }

interface

uses
  System.JSON;

const
  { Los campos de cada comando de delphi_adb, la tabla de ParametroQueNoVa: la
    leen la tool y la puerta (AdbArgDenied). Los que llevan device hablan con UN
    dispositivo, y la puerta exige que se nombre: un comando nuevo se escribe
    una vez (P6 del revisor: eran dos listas). }
  ADB_CAMPOS: array[0..21] of string = (
    'discover', '', 'devices', '',
    'logcat', 'filter lines out device',
    'connect', 'address', 'disconnect', 'address',
    'install', 'apk device', 'run', 'app device', 'stop', 'app device',
    'screenshot', 'out inline maxwidth device',
    'tap', 'x y frame device', 'key', 'key device');

{ The identifier rule for a PAServer profile name: it becomes a file name in
  %APPDATA% and travels on command lines (paclient and msbuild /p:Profile=).
  ONE definition - PAServerArgDenied and BuildArgDenied ("profile" in both)
  read it, so the two mouths cannot drift. True = refuse. Tambien la leen
  delphi_config set-profile y delphi_paserver remove-profile: tenian una
  regex propia que dejaba pasar el punto, y set-profile fijaba en el .dproj
  un perfil que delphi_build profile= negaba despues (9-oct-2026). }
function BadProfileName(const V: string): Boolean;

{ La regla del nombre de un proyecto que viaja a paclient (--put / --get /
  --Remove de Lsp.RemoteRun y el Deploy de msbuild): paclient parte --put/--get
  por ',' y --Remove por ';', y la orden va como UN argumento entre comillas.
  True = el valor NO puede ir en un campo de paclient. Lista BLANCA: letras y
  digitos de cualquier alfabeto y ' _-.()+'; una lista de separadores no ve la
  variante que alguien normalice por el camino. Vacio, '.' y '..' tampoco. No
  hay juez que preguntar -la gramatica de campos de paclient es suya, medida-:
  una gramatica NUESTRA, UNA, aqui y vigilada por test_paisaje (V217 de la
  1.23.1). }
function NombreRompeCampoDePaclient(const V: string): Boolean;

{ La hermana para los campos de un DeployFile (Include, RemoteDir, RemoteName),
  que el Deploy de msbuild pone en el --put de paclient: un ';' abre otra entrada
  y lo que sobra se lee como fichero LOCAL a subir (medido el 30-oct-2026 contra
  el PAServer local, V217). Lista blanca: la del nombre mas lo que lleva una ruta.
  Su juez de lo legitimo son 62 manifiestos del IDE (Samples y raices, 30-oct): ni
  un ',' ';' '"' ni '%'. Lleva '$' y parentesis: quien llama decide las macros. }
function ValorRompeCampoDePaclient(const V: string): Boolean;

{ El nombre que el agente nombra (el del .dproj, como lo derivan remote-run,
  output, el Deploy...: TPath.GetFileNameWithoutExtension), juzgado para
  paclient: '' si es seguro componerlo en un campo, o PAS-071. EL lector de
  todas las puertas que mandan ese nombre a paclient -Lsp.RemoteRun
  (FetchFromTarget, RemoteRun, RemoteOutput; RemoteKill por RemoteRun), la
  puerta de Mcp.Tools.PAServer (EjecucionRemotaDenegada) y el Deploy de
  Lsp.BuildRunner-, para que ninguna derive a mano una regla que drifte.
  Y el nombre de la carpeta del nodo de escritorio (NODE_PROJECT) es del
  servidor: un proyecto del agente con ese nombre se desplegaba ENCIMA del
  nodo, que luego ejecutan las sesiones de escritorio de otros agentes en ese
  perfil (R1 del revisor del paisaje de la 1.29): PAS-074. ADelServidor: la
  llamada es del propio servidor (la comprobacion y las capturas del nodo, por
  FetchFromTarget), que si usa esa carpeta. }
function NombreDeProyectoParaPaclientDenegado(const ADprojPath: string;
  ADelServidor: Boolean = False): string;

{ Un RemoteDir o un RemoteName (AElemento, su valor AValor) de un DeployFile que
  despliega el proyecto AProyecto para APlataforma: '' si el fichero queda en la
  carpeta del proyecto en el destino, o BUILD-070. PAServer deja un DeployFile
  relativo a la carpeta del PERFIL (<usuario>-<perfil>/), y el IDE empieza
  RemoteDir por el nombre del proyecto (AppB9\). Medido el 7-nov-2026 en los 68
  .deployproj de esta maquina (ejemplos del IDE y proyectos): las 1.393 entradas
  de Linux64, Win32, Win64 y Android, TODAS en la carpeta del proyecto y
  ninguna con '..' ni con una macro. Otra primera carpeta pisaba la de OTRO
  proyecto: la del nodo de escritorio, que ejecutan las sesiones de escritorio
  de otros agentes, o la de un proyecto que el operador deja ejecutar (el
  homonimo de Fable de la 1.22.2, reabierto por RemoteDir): R1 de la 1.29.
  Apple (macOS, iOS) es la excepcion medida: el bundle se nombra P.app\..\ y
  $(PROJECTNAME); ahi se niega lo que sube por encima de la carpeta del perfil
  y la del nodo. Sin juez a quien preguntar (donde deja PAServer un fichero es
  suyo, medido en el destino): una gramatica NUESTRA, UNA, aqui. }
function CampoRemotoFueraDelProyectoDenegado(const AElemento, AValor, AProyecto,
  APlataforma, AFichero: string): string;

{ Lo que la puerta de la llamada (Lsp.Guard) pregunta de los argumentos, cada
  uno explicado en su cuerpo. Publicos desde que se mudaron aqui (B6 de la
  1.28). }
function ArgStr(const AArguments: TJSONObject; const AName: string): string;
function DuplicateArgDenied(const AArguments: TJSONObject): string;
function PerfilDeLaLlamadaDenegado(const V: string): string;
function AdbArgDenied(const AArguments: TJSONObject): string;
function BuildArgDenied(const AArguments: TJSONObject): string;
function PAServerArgDenied(const AArguments: TJSONObject): string;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.IOUtils,
  MCPServer.Serializer, // NormalizeKey: ONE rule for argument names
  Lsp.Dproj,            // CanonicalPlatform: the platform whitelist already exists
  Lsp.Texts,
  Lsp.Settings,
  Lsp.ProcessLaunch, // EnComillas: la linea de una orden
  Lsp.RemoteRun,     // NODE_PROJECT: la carpeta del nodo en el destino, del servidor
  System.Character;

{ Reads a tools/call argument the SAME WAY the RTTI binder resolves it
  (TMCPSerializer.NormalizeKey: case-insensitive AND ignoring '_').
  TJSONObject.TryGetValue is case-SENSITIVE, so the gate saw '' for an argument
  sent as "Args" or "com_mand" while the handler received its real value - a
  bypass of EVERY decision made here. The gate never calls TryGetValue on an
  argument again. Objects, arrays and null yield '' (TJSONAncestor.Value). }
function ArgStr(const AArguments: TJSONObject; const AName: string): string;
var
  P: TJSONPair;
  Want: string;
begin
  Result := '';
  if not Assigned(AArguments) then
    Exit;
  Want := TMCPSerializer.NormalizeKey(AName);
  for P in AArguments do
    if TMCPSerializer.NormalizeKey(P.JsonString.Value) = Want then
    begin
      // null es "falta", como para el binder: su .Value es el texto 'null' y
      // la puerta miraba un valor que la tool no recibe (septima revision)
      if P.JsonValue is TJSONNull then
        Exit('');
      Exit(P.JsonValue.Value);
    end;
end;

{ Two keys that normalize to the SAME parameter make the gate and the binder
  read different values: the binder probes the exact declared casing FIRST, so
  sending "args" with a harmless value AND "Args" with a dangerous one gets the
  first one vetted and the second one executed. Refusing the ambiguity removes
  the whole class instead of guessing which spelling wins. Runs BEFORE
  ExpandVirtualDrives, whose RemovePair also picks the first exact match.
  '' = clean. }
function DuplicateArgDenied(const AArguments: TJSONObject): string;
var
  I, J: Integer;
begin
  Result := '';
  if not Assigned(AArguments) then
    Exit;
  for I := 0 to AArguments.Count - 2 do
    for J := I + 1 to AArguments.Count - 1 do
      if TMCPSerializer.NormalizeKey(AArguments.Pairs[I].JsonString.Value) =
         TMCPSerializer.NormalizeKey(AArguments.Pairs[J].JsonString.Value) then
        Exit(MsgFmt(SR_ARG_DUPLICATE_FMT,
          [AArguments.Pairs[I].JsonString.Value]));
end;

function BadProfileName(const V: string): Boolean;
var
  C: Char;
begin
  // ...ni empieza por "-": el nombre va SOLO en la linea de paclient, y la
  // regla de la casa es que ningun valor suelto lo haga (git ya la tiene;
  // V197 de la 1.23.1)
  Result := (Length(V) > 64) or V.StartsWith('-');
  if not Result then
    for C in V do
      if not CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_', '-']) then
        Exit(True);
end;

{ LA regla del nombre de un perfil en la puerta, con su negativa ('' =
  limpio): el "profile" de delphi_build, delphi_paserver y delphi_desktop,
  que llega a la linea de paclient o de msbuild. Estaba escrita dos veces y
  a delphi_desktop le faltaba, aunque la descripcion de "profile" la promete
  para los tres (V8 de la 1.23). }
function PerfilDeLaLlamadaDenegado(const V: string): string;
begin
  Result := '';
  if (V.Trim <> '') and BadProfileName(V.Trim) then
    Result := MsgFmt(SR_PASERVER_NAME_FMT, [V.Trim]);
end;

function NombreRompeCampoDePaclient(const V: string): Boolean;
var
  C: Char;
begin
  if (V = '') or (V = '.') or (V = '..') then
    Exit(True);
  for C in V do
    if not (C.IsLetterOrDigit or CharInSet(C, [' ', '_', '-', '.', '(', ')', '+'])) then
      Exit(True);
  Result := False;
end;

function ValorRompeCampoDePaclient(const V: string): Boolean;
var
  C: Char;
begin
  Result := False;
  for C in V do
    if not (C.IsLetterOrDigit or CharInSet(C, [' ', '\', '/', '.', '_', '-', '(', ')', '+',
       '$', ':', '@', '~', '&', '''', '#', '[', ']', '{', '}', '!', '=', '^'])) then
      Exit(True);
end;

function NombreDeProyectoParaPaclientDenegado(const ADprojPath: string;
  ADelServidor: Boolean): string;
var
  Nombre: string;
begin
  Result := '';
  Nombre := TPath.GetFileNameWithoutExtension(ADprojPath);
  if NombreRompeCampoDePaclient(Nombre) then
    Result := MsgFmt(SR_PACLIENT_NOMBRE_FMT, [Nombre])
  else if not ADelServidor and SameText(Nombre.Trim, NODE_PROJECT) then
    Result := MsgFmt(SR_PACLIENT_NOMBRE_RESERVADO_FMT, [Nombre]);
end;

function CampoRemotoFueraDelProyectoDenegado(const AElemento, AValor, AProyecto,
  APlataforma, AFichero: string): string;
const
  MACRO_DEL_IDE = '$(PROJECTNAME)';
var
  Pila: TArray<string>;
  Apple, Mal: Boolean;
begin
  Result := '';
  Apple := SistemaDePlataforma(APlataforma) in [spMacOS, spIOS];
  Mal := False;
  Pila := [];
  var Valor := AValor;
  if Apple then
    Valor := StringReplace(Valor, MACRO_DEL_IDE, AProyecto, [rfReplaceAll, rfIgnoreCase])
  else
    Mal := Valor.Contains('$');
  // los pasos, como los da PAServer: '' y '.' no mueven, '..' sube
  for var Paso in Valor.Split(['\', '/']) do
    if (Paso.Trim = '') or (Paso.Trim = '.') then
      Continue
    else if Paso.Trim = '..' then
    begin
      // un RemoteName no sube nunca; fuera de Apple, nada sube; y nada sube
      // por encima de la carpeta del perfil
      if SameText(AElemento, 'RemoteName') or not Apple or (Length(Pila) = 0) then
        Mal := True
      else
        SetLength(Pila, Length(Pila) - 1);
    end
    else
      Pila := Pila + [Paso.Trim];
  if not Mal and SameText(AElemento, 'RemoteDir') then
  begin
    if Apple then
      Mal := (Length(Pila) > 0) and SameText(Pila[0], NODE_PROJECT)
    else
      Mal := (Length(Pila) = 0) or not SameText(Pila[0], AProyecto);
  end;
  if Mal then
    Result := MsgFmt(SR_BUILD_CARPETA_REMOTA_FMT,
      [AElemento, TPath.GetFileName(AFichero), AValor, AProyecto, APlataforma, AProyecto]);
end;

{ The identifier rule for a device address or serial (adb's ip:port or a
  serial like emulator-5554 / R58M...): what adb itself prints. ONE
  definition - AdbArgDenied (address/device) and BuildArgDenied (deviceid)
  both read it. True = refuse. }
function BadDeviceToken(const V: string): Boolean;
var
  C: Char;
begin
  // ...ni empieza por "-" (adb connect lo lleva solo en su linea; V197)
  Result := (Length(V) > 64) or V.StartsWith('-');
  if not Result then
    for C in V do
      if not CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '.', ':', '_', '-']) then
        Exit(True);
end;

{ El nombre de un dispositivo, que puede ser el mDNS que adb numera ("adb-X
  (2)._adb-tls-connect._tcp"): la misma regla sobre el nombre sin el numero, y
  el tope sobre el entero. address no pasa por aqui: es ip:port. True = refuse. }
function BadDeviceName(const V: string): Boolean;
begin
  Result := (Length(V) > 64) or BadDeviceToken(DispositivoSinNumeroMdns(V));
end;

{ delphi_adb's address/device land on the adb command line. Same lesson as
  git/build/paserver: one vetting place for both access levels. The apk path
  is a filesystem argument vetted by the tool through ReadPathDenied. }
function AdbArgDenied(const AArguments: TJSONObject): string;
var
  V: string;
begin
  Result := '';
  LoadSecurity;
  V := ArgStr(AArguments, 'address').Trim;
  if V <> '' then
  begin
    if BadDeviceToken(V) then
      Exit(MsgFmt(SR_ADB_TARGET_FMT, [V]));
    if not AdbTargetAllowed(V) then
      Exit(MsgFmt(SR_ADB_ALLOWLIST_FMT, [V]));
  end;
  V := ArgStr(AArguments, 'device').Trim;
  if V <> '' then
  begin
    if BadDeviceName(V) then
      Exit(MsgFmt(SR_ADB_TARGET_FMT, [V]));
    if not AdbTargetAllowed(V) then
      Exit(MsgFmt(SR_ADB_ALLOWLIST_FMT, [V]));
  end;
  // "app" is a package name reaching adb shell am start - same charset rule
  // (a package is letters/digits/dots/underscores), own message.
  V := ArgStr(AArguments, 'app').Trim;
  if (V <> '') and BadDeviceToken(V) then
    Exit(MsgFmt(SR_ADB_APP_FMT, [V]));
  // tap coordinates reach adb shell input - digits only. The key name is
  // whitelisted in the tool; here only its charset (letters).
  for var Coord in TArray<string>.Create('x', 'y') do
  begin
    V := ArgStr(AArguments, Coord).Trim;
    if V <> '' then
      for var C in V do
        if not CharInSet(C, ['0'..'9']) then
          Exit(MsgFmt(SR_ADB_XY_FMT, [V]));
  end;
  V := ArgStr(AArguments, 'key').Trim;
  if V <> '' then
    for var C in V do
      if not CharInSet(C, ['A'..'Z', 'a'..'z']) then
        Exit(MsgFmt(SR_ADB_KEY_FMT, [V]));
  // Y al final, el target implicito: podria ser un dispositivo NO listado
  // que casualmente es el unico conectado - se nombra o nada. Va tras las
  // reglas de formato para que el error mas util conteste primero. Desde
  // v0.98 la lista es del workspace y vacia = ninguno: sin excepcion.
  if (ArgStr(AArguments, 'device').Trim = '') then
  begin
    var Cmd := Trim(ArgStr(AArguments, 'command'));
    var I := 0;
    while I < High(ADB_CAMPOS) do
    begin
      if SameText(ADB_CAMPOS[I], Cmd) and MatchText('device', ADB_CAMPOS[I + 1].Split([' '])) then
        Exit(MsgText(SR_ADB_ALLOWLIST_DEVICE));
      Inc(I, 2);
    end;
  end;
end;

{ delphi_build's platform/config/target reach msbuild's command line. Until
  2an of 1.18.2 that line went through cmd.exe UNQUOTED (rsvars.bat &&
  msbuild ...), where a metacharacter was arbitrary execution; msbuild now
  runs with no shell, and these judges stay as the second barrier (David,
  11-oct). platform reuses the whitelist that ALREADY exists for
  the .dproj XML sink (Lsp.Dproj.CanonicalPlatform) instead of a second, weaker
  charset test; target is a fixed trio; config is NOT a fixed list - a project
  may declare its own configurations (parity with the IDE), so it is bounded by
  a charset that admits no shell metacharacter. '' = clean. }
function BuildArgDenied(const AArguments: TJSONObject): string;
var
  V: string;
  C: Char;
begin
  Result := '';
  V := ArgStr(AArguments, 'platform').Trim;
  if (V <> '') and (CanonicalPlatform(V) = '') then
    Exit(NegativaDePlataforma(V));
  V := ArgStr(AArguments, 'target').Trim;
  if (V <> '') and not MatchText(V, TARGETS_DE_BUILD) then
  begin
    Result := MsgFmt(SR_BUILD_TARGET_FMT, [V]);
    // una plataforma en target ("target platform"): donde va
    if CanonicalPlatform(V) <> '' then
      Result := Result + MsgFmt(SF_BUILD_TARGET_ES_PLATAFORMA_FMT, [V, CanonicalPlatform(V)]);
    Exit;
  end;
  // "profile" is a PAServer profile name reaching the msbuild command line
  // (/p:Profile=) - the same identifier rule as delphi_paserver's "profile",
  // ONE definition for every mouth (PerfilDeLaLlamadaDenegado).
  Result := PerfilDeLaLlamadaDenegado(ArgStr(AArguments, 'profile'));
  if Result <> '' then
    Exit;
  // "deviceid" is an adb serial reaching msbuild (/p:DeviceId=) - the same
  // rule as delphi_adb's address/device.
  V := ArgStr(AArguments, 'deviceid').Trim;
  if (V <> '') and BadDeviceName(V) then
    Exit(MsgFmt(SR_ADB_TARGET_FMT, [V]));
  // ...y uno de los dispositivos que el workspace permite, la lista de
  // delphi_adb: el agente elige entre lo que el servidor sabe, no escribe un
  // valor libre en la linea de msbuild (D6 del revisor del paisaje de la 1.28)
  if (V <> '') and not AdbTargetAllowed(V) then
    Exit(MsgFmt(SR_ADB_ALLOWLIST_FMT, [V]));
  // "sdk" reaches msbuild's line (/p:PlatformSDK=): a file NAME, never a
  // path and never a metacharacter (audit 2026-09-25). The build also
  // checks it against the SDKs of the platform, like set-sdk does.
  V := ArgStr(AArguments, 'sdk').Trim;
  if V <> '' then
    for C in V do
      if not CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.']) then
        Exit(MsgFmt(SR_BUILD_SDK_NAME_FMT, [V]));
  // el nombre de la config, con la regla de su casa (Lsp.Dproj), la misma que
  // aplica el fondo (ConfigDelBuild)
  V := ArgStr(AArguments, 'config');
  if NombreDeConfigNoValido(V) then
    Exit(MsgFmt(SR_BUILD_CONFIG_FMT, [V]));
end;

{ delphi_paserver's add-profile/test-connection compose a paclient.exe command
  line (direct CreateProcess, no shell - but a double quote would re-split the
  argument list) and the profile NAME doubles as a file name in %APPDATA%.
  Vetted here for BOTH access levels: one place, same lesson as the git and
  build argument filters. The platform whitelist is paclient's own
  (PACLIENT_PLATFORMS, Lsp.Dproj) - narrower than CanonicalPlatform. The
  password may not carry quotes or control characters; everything else is the
  PAServer's business. '' = clean. }
function PAServerArgDenied(const AArguments: TJSONObject): string;
var
  V: string;
  C: Char;
  N: Integer;
begin
  Result := '';
  // El perfil se llama "profile" desde la 1.17.0 ("name" es su alias, y el
  // alias se aplica ANTES de esta puerta): la puerta leia la clave cruda
  // "name", y al renombrar el parametro un nombre con espacios y simbolos
  // paso y llego a ser un .profile de verdad en el APPDATA (medido por
  // test_paserver, 7-oct-2026). Las dos claves, por si el orden cambia.
  for var Clave in ['profile', 'name'] do
  begin
    Result := PerfilDeLaLlamadaDenegado(ArgStr(AArguments, Clave));
    if Result <> '' then
      Exit;
  end;
  V := ArgStr(AArguments, 'host').Trim;
  if V <> '' then
    for C in V do
      if not CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '.', '-', ':']) then
        Exit(MsgFmt(SR_PASERVER_HOST_FMT, [V]));
  V := ArgStr(AArguments, 'port').Trim;
  if V <> '' then
    if not TryStrToInt(V, N) or (N < 1) or (N > 65535) then
      Exit(MsgFmt(SR_PASERVER_PORT_FMT, [V]));
  V := ArgStr(AArguments, 'platform').Trim;
  // EL juez de la plataforma, el mismo con el que add-profile la toma (C4)
  if (V <> '') and (PlataformaDePaclient(V) = '') then
    Exit(MsgFmt(SR_PASERVER_PLATFORM_FMT, [V, PaclientPlatformsList]));
  // la contrasena va a la linea de paclient, un programa Delphi: EL juez de los
  // valores nuestros (ValorDeLaCasaLlega: su ParamStr la recibe entera, sin
  // caracteres de control), y dice CUAL no llega, como TEST-037 (B7)
  V := ArgStr(AArguments, 'password');
  if not ValorDeLaCasaLlega(V) then
    Exit(MsgFmt(SR_PASERVER_PASSWORD_FMT, [CaracterQueNoLlega(V)]));
end;

end.