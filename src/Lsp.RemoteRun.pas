unit Lsp.RemoteRun;

{ Remote execution THROUGH PAServer - sin nada instalado en el destino.
  paclient.exe no tiene operacion "ejecuta" (medido 2026-08-24: su superficie
  es copiar ficheros, firmar y empaquetar Android), pero los FLAGS del --put
  si ejecutan: flag 5 hace que PAServer corra el fichero con /bin/sh y flag 3
  lanza un binario directamente. De ahi el mecanismo:

    servidor: --put  <Proyecto>/run-<id>.sh  con flag 5   (la orden)
    destino:  PAServer lo ejecuta; el guion lanza el binario DESATENDIDO y
              deja su salida en <Proyecto>/<id>.out, rematada con ___RC=<n>
    servidor: --get  sondea ese fichero hasta ver el centinela o agotar plazo

  Hasta el 19-sep-2026 esto iba por un demonio Python en el destino
  (runner/mcp-runner.py) con cola de trabajos en ficheros. Se retiro al medir
  que PAServer solo hace lo mismo y mejor: sin dependencias en el destino
  (exigia /usr/bin/python3), sin cola de uno en uno -que bloqueaba hasta las
  capturas mientras corria algo-, sin matar por plazo lo que no termina (una
  aplicacion con ventana), con la salida PARCIAL legible mientras el proceso
  vive, y mas rapido: 1,96 s por gesto contra 3,3 s. Y desaparece de raiz una
  clase de fallo: un fichero de trabajo en un disco sobrevive a quien lo pidio
  y se ejecuta solo cuando alguien arranca el demonio semanas despues (paso:
  al reactivarlo corrio trabajos de agosto).

  Lo que puede ejecutarse no cambia: SOLO el binario que ese proyecto
  desplego, en su carpeta del scratch-dir de PAServer. El guion lo escribe
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

{ Runs the program DEPLOYED for ADprojPath on the machine of PAServer profile
  AProfile. The remote path is DERIVED here, never taken from the caller:
  <windows user>-<profile>/<Project>/<Project> - the folder delphi_build
  target=Deploy writes and announces in its deployNote. AExeName, when given,
  picks another file of THAT SAME folder (a helper binary of the deploy) and
  may not contain path separators. Returns the JSON the tool hands back. }
function RemoteRun(const AProfile, ADprojPath, AExeName, AArgs: string;
  ATimeoutMs: Integer; const ALiteral: string = ''): TJSONObject;

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

{ El guion que PAServer ejecuta. Lo escribimos NOSOTROS: del agente solo entran
  los argumentos, y llegan aqui ya filtrados (ShellArgDenied rechaza cualquier
  metacaracter), dentro de la jaula y de la lista de proyectos con permiso.

  Va DESATENDIDO a proposito (el trabajo en segundo plano, con el HUP
  ignorado) por una razon medida: si esperase, una aplicacion CON VENTANA
  -que no termina nunca-
  dejaria colgado a quien la lanzo, y de paso bloquearia todo lo demas. Asi la
  llamada vuelve enseguida, el programa queda vivo, y el resultado se recoge
  del fichero cuando aparezca el centinela ___RC=<codigo>. Mientras no esta,
  lo que hay en el fichero es la salida PARCIAL: se puede leer el avance de un
  proceso largo, cosa que el runner nunca dio. }
{ Un argumento, blindado para /bin/sh: entre comillas SIMPLES el shell no
  interpreta nada, y la unica que hay que tratar es la propia comilla simple. }
function ComillasSh(const AArg: string): string;
begin
  Result := '''' + AArg.Replace(#13, ' ').Replace(#10, ' ')
    .Replace('''', '''\''''') + '''';
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

function GuionDeEjecucion(const AExeLeaf, AArgs, ASalida: string;
  const ALiteral: string = ''): string;
var
  Linea: string;
begin
  Linea := '"$D/' + AExeLeaf + '"';
  // CADA argumento entre comillas SIMPLES de shell. Iban A PELO dentro del
  // guion, y este es el unico sitio por donde pasan todos: el filtro de
  // metacaracteres lo aplicaba quien llama, remote-run SI y delphi_adb_linux
  // NO, asi que `type text="hola; rm -rf ~"` ejecutaba la segunda mitad en
  // la maquina destino (medido el 2026-09-21: un texto con parentesis rompio
  // la sintaxis del guion y enseno como viajaba). Dentro de comillas simples
  // el shell no interpreta NADA; la unica que hay que tratar es la propia
  // comilla simple. Y de paso un texto legitimo con ( ) * ? # ~ ' " deja de
  // romperse o de expandirse. El filtro de quien llama se queda: cinturon.
  for var Trozo in TrocearArgs(AArgs) do
    Linea := Linea + ' ' + ComillasSh(Trozo);
  // ALiteral: UN argumento que viaja TAL CUAL, sin trocear - el texto que
  // delphi_adb_linux manda teclear, con sus espacios y sus comillas.
  if ALiteral <> '' then
    Linea := Linea + ' ' + ComillasSh(ALiteral);
  Result :=
    '#!/bin/sh'#10 +
    'D="$(cd "$(dirname "$0")" && pwd)"'#10 +
    'O="$D/' + ASalida + '"'#10 +
    'rm -f "$O"'#10 +
    'cd "$D" || exit 1'#10 +
    // SOLO binarios nativos. Lo comprobaba el runner de Python y al retirarlo
    // el hueco quedo abierto: "exe" deja elegir OTRO fichero de la carpeta
    // desplegada, y ahi puede haber un .sh o un .py del propio despliegue
    // (GalateaFMX lleva un GalateaLanzador.sh al lado). Se mira la firma del
    // fichero, no su extension: 7f454c46 es ELF, los cuatro feedface... son
    // Mach-O y 4d5a ("MZ") es un PE - que tambien hace falta, porque un
    // target PAServer puede ser Windows. Un rechazo escribe su ___RC para que
    // quien sondea no espere en vano.
    // "no esta" y "no es ejecutable" son fallos DISTINTOS: si dan el mismo
    // mensaje, quien lo lee no sabe si se equivoco de nombre o de fichero.
    'if [ ! -f "$D/' + AExeLeaf + '" ]; then'#10 +
    '  { echo "error: no existe ' + AExeLeaf + ' en la carpeta desplegada ' +
      'de este proyecto en el target."; echo "___RC=127"; } > "$O"; exit 0'#10 +
    'fi'#10 +
    'M=$(head -c 4 "$D/' + AExeLeaf + '" 2>/dev/null | od -An -t x1 | ' +
      'tr -d " \n")'#10 +
    'case "$M" in'#10 +
    '  7f454c46|cffaedfe|cefaedfe|feedface|feedfacf|4d5a*) ;;'#10 +
    '  *) { echo "RECHAZADO: ' + AExeLeaf + ' no es un ejecutable nativo ' +
      '(ELF/Mach-O): solo se ejecuta el binario que produjo delphi_build."; ' +
      'echo "___RC=126"; } > "$O"; exit 0 ;;'#10 +
    'esac'#10 +
    '{ trap '''''''' HUP; ' + Linea + ' > "$O" 2>&1; ' +
      'echo "___RC=$?" >> "$O"; } &'#10 +
    'exit 0'#10;
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

function RemoteRun(const AProfile, ADprojPath, AExeName, AArgs: string;
  ATimeoutMs: Integer; const ALiteral: string): TJSONObject;
var
  ProjName, DeployRel, ARemoteExe, ExeLeaf: string;
  Pc, JobId, TmpDir, GuionFile, OutFile, Ops, Output, Texto, Salida: string;
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
  GuionFile := TPath.Combine(TmpDir, 'run-' + JobId + '.sh');
  // POSIX script: LF endings and NO BOM - /bin/sh chokes on both.
  Enc := TUTF8Encoding.Create(False);
  try
    TFile.WriteAllText(GuionFile,
      GuionDeEjecucion(ExeLeaf, AArgs, JobId + '.out', ALiteral), Enc);
  finally
    Enc.Free;
  end;

  // flag 5 = PAServer EJECUTA el fichero (con /bin/sh) y no deja la copia.
  Ops := Format('"--put=%s,%s,5,run-%s.sh"', [GuionFile, DeployRel, JobId]);
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
      Terminado := PartirSalida(Texto, Salida, Codigo);
    end;
  until Terminado or (Sw.ElapsedMilliseconds > ATimeoutMs);

  Result.AddPair('jobId', JobId);
  Result.AddPair('profile', AProfile);
  Result.AddPair('remoteExe', ARemoteExe);
  Result.AddPair('project', ProjName);
  Result.AddPair('durationMs', TJSONNumber.Create(Sw.ElapsedMilliseconds));
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
  Ops := Format('"--Remove=%s/%s.out"', [DeployRel, JobId]);
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
