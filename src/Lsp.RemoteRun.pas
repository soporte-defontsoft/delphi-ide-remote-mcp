unit Lsp.RemoteRun;

{ Remote execution THROUGH PAServer - sin nada instalado en el destino.
  paclient.exe no tiene operacion "ejecuta" (medido 2026-08-24: su superficie
  es copiar ficheros, firmar y empaquetar Android), pero un flag del --put
  hace que PAServer ARRANQUE el fichero subido -sin argumentos- y ESPERE a que
  termine: flag 3 un ELF en Linux, flag 5 un PE en Windows (en Linux el 5 es
  "/bin/sh fichero"). Medido el 2026-09-22 en Zorin, Fedora y Windows. De ahi
  el mecanismo, UNO para los dos sistemas:

    servidor: --put  <Proyecto>/run-<id>.job  (flag 0: el trabajo, 3 lineas
              y un ARGUMENTO POR LINEA) y el LANZADOR node\McpRunJob con el
              nombre run-<id> (flag 3) o run-<id>.exe (flag 5)
    destino:  PAServer arranca el lanzador; este lee su .job, completa el
              entorno grafico que falte, comprueba que el binario es nativo,
              lo lanza DESATENDIDO con la salida en <Proyecto>/<id>.out y
              deja un vigia que la remata con ___RC=<n>
    servidor: --get  sondea ese fichero hasta ver el centinela o agotar plazo

  Hasta el 2026-09-22 en Linux se subia un guion /bin/sh compuesto AQUI (y el
  texto de un agente viajaba por un shell: la inyeccion del 21-sep), y en
  Windows el lanzador: dos escritores, dos lectores, dos ramas. Decision de
  David: una. Sin shell no hay nada que blindar: los argumentos van del .job
  al argv del programa tal cual. Hasta el 19-sep-2026 esto iba por un demonio
  Python en el destino (runner/mcp-runner.py); se retiro al medir que
  PAServer solo hace lo mismo y mejor: sin dependencias en el destino, sin
  matar por plazo lo que no termina (una aplicacion con ventana), con la
  salida PARCIAL legible mientras el proceso vive, y mas rapido.

  Lo que puede ejecutarse no cambia: SOLO el binario que ese proyecto
  desplego, en su carpeta del scratch-dir de PAServer. El .job lo escribe
  este servidor -del agente solo entran argumentos ya filtrados- y no se
  queda en el destino.

  DELPHI_MCP_PACLIENT overrides the paclient.exe path (the test battery
  points it at a stub that copies to a local folder). }

interface

uses
  System.JSON;

const
  { La carpeta y el binario del nodo de escritorio en el target. }
  NODE_PROJECT = 'McpDesktopNode';

{ La clave con la que el nodo reconoce que le llama ESTE servidor. Vive en
  un solo sitio para que los dos proyectos no se desincronicen. }
{$I ..\src_desktop_node\NodeKey.inc}

{ El nodo de escritorio EMPAQUETADO con el servidor: node\McpDesktopNode
  junto al exe. '' si la distribucion no lo trae. }
function BundledNodePath: string; overload;

{ El mismo, eligiendo binario por la plataforma del target ('Win64',
  'Linux64'...): a cada sistema el suyo. }
function BundledNodePath(const APlataforma: string): string; overload;

{ Deja el nodo del target AL DIA sin compilar nada (peticion David
  2026-09-19): compara el sello node.ver del target (SHA-256 del binario)
  con el del nodo empaquetado y, si falta o difiere, sube binario nuevo
  (flag 1 = ejecutable) y sello. Se comprueba UNA vez por perfil y proceso:
  los gestos siguientes no pagan el viaje. AAccion queda en '' (al dia),
  'desplegado' o 'actualizado'. Devuelve '' si bien, o el motivo. }
function EnsureNodeCurrent(const AProfile: string; out AAccion: string): string;

{ La plataforma del perfil (Profile_platform de su .profile): Linux64, Win64...
  '' si el perfil no existe. Con ella la tool de escritorio sabe que nodo y
  que teclas espera el destino. }
function PlataformaDelPerfil(const AProfile: string): string;

{ Runs the program DEPLOYED for ADprojPath on the machine of PAServer profile
  AProfile. The remote path is DERIVED here, never taken from the caller:
  <windows user>-<profile>/<Project>/<Project> - the folder delphi_build
  target=Deploy writes and announces in its deployNote. AExeName, when given,
  picks another file of THAT SAME folder (a helper binary of the deploy) and
  may not contain path separators. Returns the JSON the tool hands back. }
function RemoteRun(const AProfile, ADprojPath, AExeName: string;
  const AArgv: TArray<string>; ATimeoutMs: Integer): TJSONObject;

{ Trocea una linea de argumentos como lo haria quien la escribio: por
  espacios, y con comillas DOBLES para agrupar uno que lleva espacios. Es el
  UNICO troceador: lo que sale de aqui va al argv del programa tal cual. }
function TrocearArgs(const AArgs: string): TArray<string>;

{ Trae AQUI un fichero que el programa desplegado dejo en SU carpeta del
  target. ARelPath es relativo a esa carpeta ('captura.png'), nunca una ruta
  del sistema: igual que la ejecucion remota, esto solo alcanza lo que ESE
  proyecto desplego. Devuelve '' si todo fue bien, y el motivo si no. }
function FetchFromTarget(const AProfile, ADprojPath, ARelPath, ADestDir: string;
  out ALocalFile: string): string;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.Diagnostics,
  System.SyncObjs,
  System.Hash,
  System.RegularExpressions,
  Lsp.Guard,      // CrearCarpeta: crear la carpeta tolerando la carrera
  Lsp.BuildRunner,
  Lsp.Discovery,
  Lsp.Patch,     // DecodeSourceBytes: el lector de la casa
  Lsp.Texts;

var
  GNodoLock: TCriticalSection;
  GNodoAlDia: TStringList; // perfiles con nodo comprobado en este proceso

const
  POLL_MS = 1500;

function PaClientPath: string;
var
  Installs: TArray<TRadStudioInfo>;
  Info: TRadStudioInfo;
  P: string;
begin
  Result := GetEnvironmentVariable('DELPHI_MCP_PACLIENT');
  if (Result <> '') and TFile.Exists(Result) then
    Exit;
  Result := '';
  Installs := DiscoverAllRadStudios;
  for Info in Installs do
  begin
    if not Info.Found then
      Continue;
    P := TPath.Combine(TPath.Combine(
      ExcludeTrailingPathDelimiter(Info.RootDir), 'bin'), 'paclient.exe');
    if TFile.Exists(P) then
      Exit(P);
  end;
end;

function Paclient(const APaclient, AOps, AProfile: string;
  out AOutput: string): Integer;
var
  Exit_: Cardinal;
begin
  AOutput := RunCaptured(Format('"%s" %s "%s"', [APaclient, AOps, AProfile]),
    120000, Exit_);
  Result := Integer(Exit_);
end;

function JsonEsc(const S: string): string;
var
  J: TJSONString;
begin
  J := TJSONString.Create(S);
  try
    Result := J.ToJSON;
  finally
    J.Free;
  end;
end;

function FetchFromTarget(const AProfile, ADprojPath, ARelPath, ADestDir: string;
  out ALocalFile: string): string;
var
  Pc, ProjName, Ops, Output: string;
  Rc: Integer;
begin
  ALocalFile := '';
  Pc := PaClientPath;
  if Pc = '' then
    Exit(SR_REMOTERUN_NO_PACLIENT);
  if (ARelPath = '') or ARelPath.Contains('..') or
     ARelPath.StartsWith('/') or ARelPath.Contains('\') then
    Exit(SR_FETCHTARGET_BADPATH);
  ProjName := TPath.GetFileNameWithoutExtension(ADprojPath);
  CrearCarpeta(ADestDir);
  Ops := Format('"--get=%s/%s,%s"', [ProjName, ARelPath, ADestDir]);
  Rc := Paclient(Pc, Ops, AProfile, Output);
  if Rc <> 0 then
    Exit(Format(SR_FETCHTARGET_FAIL_FMT, [Rc, Output.Trim]));
  ALocalFile := TPath.Combine(ADestDir, TPath.GetFileName(ARelPath));
  if not TFile.Exists(ALocalFile) then
  begin
    ALocalFile := '';
    Exit(Format(SR_FETCHTARGET_NOFILE_FMT, [ARelPath]));
  end;
  Result := '';
end;

{ Trocea AArgs como lo haria quien los escribio: por espacios, y con comillas
  DOBLES para agrupar un argumento que lleva espacios ("ruta con espacios"
  uno dos). Las comillas dobles agrupan y se van; nada mas se interpreta. }
function TrocearArgs(const AArgs: string): TArray<string>;
var
  I: Integer;
  Actual: string;
  Dentro, Hay: Boolean;
begin
  Result := nil;
  Actual := '';
  Dentro := False;
  Hay := False;
  for I := 1 to Length(AArgs) do
    if AArgs[I] = '"' then
    begin
      Dentro := not Dentro;
      Hay := True; // "" es un argumento vacio, pero es un argumento
    end
    else if CharInSet(AArgs[I], [' ', #9, #13, #10]) and not Dentro then
    begin
      if Hay then
        Result := Result + [Actual];
      Actual := '';
      Hay := False;
    end
    else
    begin
      Actual := Actual + AArgs[I];
      Hay := True;
    end;
  if Hay then
    Result := Result + [Actual];
end;

{ EL FICHERO DE TRABAJO, el mismo para Linux y Windows: el binario, el fichero
  de salida y despues UN ARGUMENTO POR LINEA, tal cual - sin shell no hay
  nada que escapar. Su unico lector es el lanzador (src_run_job). Un salto de
  linea dentro de un argumento seria una linea mas, asi que se cambia por un
  espacio: es el unico caracter que el formato no puede llevar. }
function TrabajoDeEjecucion(const AExeLeaf, ASalida: string;
  const AArgv: TArray<string>): string;
var
  A: string;
begin
  Result := AExeLeaf + #10 + ASalida + #10;
  for A in AArgv do
    Result := Result + A.Replace(#13, ' ').Replace(#10, ' ') + #10;
end;

{ El lanzador que le toca al destino: el ELF a un Linux, el .exe a un Windows.
  Viaja en node\ junto a los dos nodos de escritorio. }
function BundledRunJobPath(const APlataforma: string): string;
var
  Nombre: string;
begin
  Nombre := 'McpRunJob';
  if APlataforma.StartsWith('Win', True) then
    Nombre := Nombre + '.exe';
  Result := TPath.Combine(TPath.Combine(
    TPath.GetDirectoryName(ParamStr(0)), 'node'), Nombre);
  if not TFile.Exists(Result) then
    Result := '';
end;

{ La primera linea de la salida es la del ENTORNO grafico (___ENV=<1|0>|<lo
  anadido>), escrita por el guion antes de lanzar el programa. Se separa del
  texto del programa y se traduce a una nota; sin ella (un guion viejo, un
  target raro) no hay nota y el texto queda como estaba. }
function PartirEntorno(var ATexto: string): string;
var
  Linea, Resto: string;
  P: Integer;
begin
  Result := '';
  if not ATexto.StartsWith('___ENV=') then
    Exit;
  P := ATexto.IndexOf(#10);
  if P < 0 then
  begin
    Linea := ATexto;
    ATexto := '';
  end
  else
  begin
    Linea := ATexto.Substring(0, P);
    ATexto := ATexto.Substring(P + 1);
  end;
  Linea := Linea.Substring(Length('___ENV=')).Trim([#13, ' ']);
  P := Linea.IndexOf('|');
  if P < 0 then
    Exit;
  Resto := Linea.Substring(P + 1).Trim;
  // el lanzador Windows dice en que SESION corre: la 0 es la de los servicios
  // y no tiene escritorio (gemela del "sin DISPLAY")
  if Resto.StartsWith('win:') then
  begin
    if Linea.StartsWith('0') then
      Result := SN_REMOTERUN_ENV_WIN0
    else
      Result := Format(SN_REMOTERUN_ENV_WIN_FMT, [Resto.Substring(4)]);
    Exit;
  end;
  if Linea.StartsWith('0') then
    Result := SN_REMOTERUN_ENV_NONE
  else if Resto = '' then
    Result := SN_REMOTERUN_ENV_INHERITED
  else
    Result := Format(SN_REMOTERUN_ENV_ADDED_FMT, [Resto.Replace(' ', ', ')]);
end;

{ Parte la salida en lo que escribio el programa y su codigo de salida. El
  centinela solo existe cuando el proceso TERMINO: mientras no esta, el
  trabajo sigue en marcha. }
function PartirSalida(const ATexto: string; out ASalida: string;
  out ACodigo: Integer): Boolean;
var
  P: Integer;
  Cola: string;
begin
  ACodigo := -1;
  ASalida := ATexto;
  P := ATexto.LastIndexOf('___RC=');
  Result := P >= 0;
  if not Result then
    Exit;
  ASalida := ATexto.Substring(0, P).TrimRight;
  Cola := ATexto.Substring(P + Length('___RC=')).Trim;
  ACodigo := StrToIntDef(Cola.Split([#10, #13])[0].Trim, -1);
end;

function RemoteRun(const AProfile, ADprojPath, AExeName: string;
  const AArgv: TArray<string>; ATimeoutMs: Integer): TJSONObject;
var
  ProjName, DeployRel, ARemoteExe, ExeLeaf: string;
  Pc, JobId, TmpDir, GuionFile, OutFile, Ops, Output, Texto, Salida: string;
  EntornoNota, Lanzador, Plataforma, RemotoLanzador: string;
  Flag: Integer;
  Rc, Codigo, Espera: Integer;
  Sw: TStopwatch;
  Enc: TEncoding;
  Terminado: Boolean;
begin
  Result := TJSONObject.Create;
  Pc := PaClientPath;
  if Pc = '' then
  begin
    Result.AddPair('success', TJSONBool.Create(False));
    Result.AddPair('error', SR_REMOTERUN_NO_PACLIENT);
    Exit;
  end;
  if ATimeoutMs <= 0 then
    ATimeoutMs := 30000;
  if ATimeoutMs > 300000 then
    ATimeoutMs := 300000;

  // The ONE thing that may run: what THIS project deployed, in its own folder
  // of the scratch dir. The caller never names a path (David's rule
  // 2026-08-24: "no se debe poder ejecutar otra cosa que no sea el programa
  // desplegado"), so a script or any other binary sitting in the scratch is
  // out of reach even for a full-access token. The guion we drop lands in
  // THAT same folder and runs from there, so $D is the deploy dir.
  ProjName := TPath.GetFileNameWithoutExtension(ADprojPath);
  DeployRel := ProjName;
  if AExeName = '' then
    ExeLeaf := ProjName
  else
    ExeLeaf := AExeName;
  ARemoteExe := DeployRel + '/' + ExeLeaf;

  // Timestamp alone collided when two agents fired remote-run in the same
  // millisecond (hermes, release audit 2026-08-26, P2.8). The GUID fragment
  // makes each operation's files unique while the prefix stays sortable.
  JobId := FormatDateTime('yyyymmdd"-"hhnnsszzz', Now) + '-' +
    LowerCase(TGUID.NewGuid.ToString.Substring(1, 8));
  // Temporal DEL SERVIDOR: este guion se manda al target y aqui no vuelve a
  // mirarlo nadie. Por el nombrador, no a mano (ver Lsp.Guard).
  TmpDir := ServerTempDir('remoterun');
  CrearCarpeta(TmpDir);
  // El lanzador del sistema del destino, con el nombre del trabajo: PAServer
  // arranca un ELF con flag 3 y un PE con flag 5 (y en Windows lo borra al
  // terminar). Todo lo demas es igual en los dos.
  Plataforma := PlataformaDelPerfil(AProfile);
  Lanzador := BundledRunJobPath(Plataforma);
  if Lanzador = '' then
  begin
    Result.AddPair('success', TJSONBool.Create(False));
    Result.AddPair('error', Format(SR_REMOTERUN_NO_RUNJOB_FMT,
      [IfThen(Plataforma.StartsWith('Win', True), 'McpRunJob.exe', 'McpRunJob')]));
    Exit;
  end;
  if Plataforma.StartsWith('Win', True) then
  begin
    Flag := 5;
    RemotoLanzador := 'run-' + JobId + '.exe';
  end
  else
  begin
    Flag := 3;
    RemotoLanzador := 'run-' + JobId;
  end;
  GuionFile := TPath.Combine(TmpDir, 'run-' + JobId + '.job');
  // el .job: LF y sin BOM, que lo lee un programa nuestro en los dos sistemas
  Enc := TUTF8Encoding.Create(False);
  try
    TFile.WriteAllText(GuionFile,
      TrabajoDeEjecucion(ExeLeaf, JobId + '.out', AArgv), Enc);
  finally
    Enc.Free;
  end;
  Ops := Format('"--put=%s,%s,0,run-%s.job;%s,%s,%d,%s"',
    [GuionFile, DeployRel, JobId, Lanzador, DeployRel, Flag, RemotoLanzador]);
  Rc := Paclient(Pc, Ops, AProfile, Output);
  TFile.Delete(GuionFile);
  if Rc <> 0 then
  begin
    Result.AddPair('success', TJSONBool.Create(False));
    Result.AddPair('error', Format(SR_REMOTERUN_PUT_FMT, [Rc, Output.Trim]));
    Exit;
  end;

  // el resultado se recoge del fichero: existe en cuanto el programa escribe,
  // y trae el centinela cuando termina
  OutFile := TPath.Combine(TmpDir, JobId + '.out');
  Texto := '';
  Terminado := False;
  Codigo := -1;
  Salida := '';
  EntornoNota := '';
  Sw := TStopwatch.StartNew;
  // Espera PROGRESIVA, y no es un detalle: un gesto del nodo dura ~2 s, asi
  // que un primer sondeo a los 1,5 s (lo que heredaba del runner) se comia
  // toda la ventaja. Empieza corto y crece hasta POLL_MS para no machacar la
  // red en un trabajo largo. Medido 19-sep: gesto completo 1,96 s por esta
  // via contra 3,3 s por el runner.
  Espera := 150;
  repeat
    Sleep(Espera);
    if Espera < POLL_MS then
      Espera := Espera * 2;
    if Espera > POLL_MS then
      Espera := POLL_MS;
    if TFile.Exists(OutFile) then
      TFile.Delete(OutFile);
    Ops := Format('"--get=%s/%s.out,%s"', [DeployRel, JobId, TmpDir]);
    if (Paclient(Pc, Ops, AProfile, Output) = 0) and TFile.Exists(OutFile) then
    begin
      // La salida de un programa AJENO: nadie garantiza que sea UTF-8, y
      // leida en estricto un solo byte suelto mataba el run entero.
      Texto := DecodeSourceBytes(TFile.ReadAllBytes(OutFile));
      EntornoNota := PartirEntorno(Texto);
      Terminado := PartirSalida(Texto, Salida, Codigo);
    end;
  until Terminado or (Sw.ElapsedMilliseconds > ATimeoutMs);

  Result.AddPair('jobId', JobId);
  Result.AddPair('profile', AProfile);
  Result.AddPair('remoteExe', ARemoteExe);
  Result.AddPair('project', ProjName);
  Result.AddPair('durationMs', TJSONNumber.Create(Sw.ElapsedMilliseconds));
  if EntornoNota <> '' then
    Result.AddPair('graphicalEnv', EntornoNota);
  if Terminado then
  begin
    Result.AddPair('success', TJSONBool.Create(Codigo = 0));
    Result.AddPair('exitCode', TJSONNumber.Create(Codigo));
    Result.AddPair('output', Salida);
  end
  else
  begin
    // Sigue corriendo. NO se mata: puede ser una aplicacion con ventana que
    // es justo lo que se queria dejar en marcha. Se devuelve lo que llevaba
    // escrito, que ya es mas de lo que daba el runner al expirar.
    Result.AddPair('success', TJSONBool.Create(False));
    Result.AddPair('exitCode', TJSONNumber.Create(-1));
    Result.AddPair('stillRunning', TJSONBool.Create(True));
    Result.AddPair('stillRunningNote', Format(SR_REMOTERUN_TIMEOUT_FMT,
      [ATimeoutMs div 1000, DeployRel]));
    if Texto <> '' then
      Result.AddPair('output', Texto);
  end;

  // limpieza remota: la salida ya viajo aqui
  if TFile.Exists(OutFile) then
    TFile.Delete(OutFile);
  // ...y el lanzador de este trabajo (en Linux flag 3 lo deja; en Windows
  // PAServer ya lo borro) y los vigias de Windows de trabajos acabados
  // (<job>.wait.exe vive lo que el programa: el de una ventana viva se queda).
  // Un nombre que no exista no es un error que importe.
  Ops := Format('"--Remove=%s/%s.out;%s/%s;%s/*.wait.exe"',
    [DeployRel, JobId, DeployRel, RemotoLanzador, DeployRel]);
  Paclient(Pc, Ops, AProfile, Output);

  Result.AddPair('note', SN_REMOTERUN_NOTE);
end;

function PlataformaDelPerfil(const AProfile: string): string;
var
  Installs: TArray<TRadStudioInfo>;
  Info: TRadStudioInfo;
  P: string;
begin
  { El .profile dice para que plataforma se creo (Profile_platform). Es la
    unica fuente fiable: el nombre del perfil no significa nada. }
  Result := '';
  Installs := DiscoverAllRadStudios;
  for Info in Installs do
  begin
    P := TPath.Combine(IdeProfilesDir(Info.Version), AProfile + '.profile');
    if TFile.Exists(P) then
      with TRegEx.Match(TFile.ReadAllText(P),
        '<Profile_platform>([^<]*)</Profile_platform>', [roIgnoreCase]) do
        if Success then
          Exit(Groups[1].Value.Trim);
  end;
end;

function BundledNodePath(const APlataforma: string): string;
var
  Nombre: string;
begin
  { UN nodo por sistema, y al target va el QUE LE CORRESPONDE (David,
    19-sep-2026). La distribucion trae los dos al lado del servidor:
    McpDesktopNode (ELF, para los Linux) y McpDesktopNode.exe (para un
    Windows con PAServer). Sin plataforma conocida se asume Linux, que es
    de donde viene este camino. }
  Nombre := NODE_PROJECT;
  if APlataforma.StartsWith('Win', True) then
    Nombre := NODE_PROJECT + '.exe';
  Result := TPath.Combine(TPath.Combine(
    TPath.GetDirectoryName(ParamStr(0)), 'node'), Nombre);
  if not TFile.Exists(Result) then
    Result := '';
end;

function BundledNodePath: string;
begin
  Result := BundledNodePath('');
end;

function Sha256DeFichero(const APath: string): string;
var
  H: THashSHA2;
begin
  H := THashSHA2.Create(THashSHA2.TSHA2Version.SHA256);
  H.Update(TFile.ReadAllBytes(APath));
  Result := H.HashAsString.ToLower;
end;

{ El trabajo; EnsureNodeCurrent lo envuelve en el cerrojo del nodo. }
function EnsureNodeCurrentNucleo(const AProfile: string;
  out AAccion: string): string;
var
  Bin, LocalSha, RemotoSha, Pc, Output, VerLocal, VerFile, TmpDir: string;
  Rc: Integer;
  Enc: TEncoding;
begin
  Result := '';
  AAccion := '';
  if GNodoAlDia.IndexOf(AProfile.Trim.ToLower) >= 0 then
    Exit;
  { Al target va el binario de SU sistema: el ELF a un Linux y el .exe a un
    Windows con PAServer. El nombre en el destino es el mismo para los dos
    (el proyecto), asi que el sello y el lanzador no cambian. }
  Bin := BundledNodePath(PlataformaDelPerfil(AProfile.Trim));
  if Bin = '' then
    Exit(SR_ADBLINUX_NONODE);
  Pc := PaClientPath;
  if Pc = '' then
    Exit(SR_REMOTERUN_NO_PACLIENT);
  LocalSha := Sha256DeFichero(Bin);
  // Carpeta PROPIA de esta comprobacion: el sello baja con su nombre remoto
  // (node.ver), asi que con un destino comun la comprobacion de un perfil se
  // llevaba por delante la de otro - dos Linux a la vez y cada uno leyendo el
  // sello del contrario (analisis de concurrencia 2026-09-20).
  TmpDir := TPath.Combine(ServerTempDir('remoterun'), 'ver-' +
    LowerCase(TGUID.NewGuid.ToString.Substring(1, 8)));
  CrearCarpeta(TmpDir);
  // el sello del target: ausente = nodo de antes de los sellos (o ninguno)
  RemotoSha := '';
  if FetchFromTarget(AProfile, NODE_PROJECT, 'node.ver', TmpDir, VerFile) = '' then
  try
    RemotoSha := TFile.ReadAllText(VerFile).Trim;
    TFile.Delete(VerFile);
  except
    RemotoSha := '';
  end;
  if not SameText(RemotoSha, LocalSha) then
  begin
    // flag 1 = runnable: PAServer deja el fichero ejecutable en su carpeta
    Rc := Paclient(Pc, Format('"--put=%s,%s,1,%s"',
      [Bin, NODE_PROJECT, NODE_PROJECT]), AProfile, Output);
    if Rc <> 0 then
      Exit(Format(SR_REMOTERUN_PUT_FMT, [Rc, Output.Trim]));
    VerLocal := TPath.Combine(TmpDir, 'node-' + LocalSha.Substring(0, 12) + '.ver');
    Enc := TUTF8Encoding.Create(False);
    try
      TFile.WriteAllText(VerLocal, LocalSha, Enc);
    finally
      Enc.Free;
    end;
    Rc := Paclient(Pc, Format('"--put=%s,%s,0,node.ver"',
      [VerLocal, NODE_PROJECT]), AProfile, Output);
    TFile.Delete(VerLocal);
    if Rc <> 0 then
      Exit(Format(SR_REMOTERUN_PUT_FMT, [Rc, Output.Trim]));
    if RemotoSha = '' then
      AAccion := 'desplegado'
    else
      AAccion := 'actualizado';
  end;
  if GNodoAlDia.IndexOf(AProfile.Trim.ToLower) < 0 then
    GNodoAlDia.Add(AProfile.Trim.ToLower);
  try
    BorraArbol(TmpDir); // la carpeta de ESTA comprobacion, sin cruzar enlaces
  except
    // dejar un temporal huerfano nunca es motivo para fallar un despliegue
  end;
end;

function EnsureNodeCurrent(const AProfile: string; out AAccion: string): string;
begin
  // Comprobar el sello y desplegar son UN gesto: separados, dos llamadas
  // simultaneas veian las dos "falta el nodo" y subian el binario a la vez
  // sobre el mismo fichero del target (analisis 2026-09-20). Pasa una vez por
  // perfil y proceso, asi que un cerrojo unico no le cuesta nada a nadie.
  GNodoLock.Enter;
  try
    Result := EnsureNodeCurrentNucleo(AProfile, AAccion);
  finally
    GNodoLock.Leave;
  end;
end;

initialization
  GNodoLock := TCriticalSection.Create;
  GNodoAlDia := TStringList.Create;

finalization
  GNodoAlDia.Free;
  GNodoLock.Free;

end.
