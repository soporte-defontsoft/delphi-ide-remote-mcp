unit Lsp.Capturas;

{ LAS CAPTURAS que el servidor hace para devolverlas: donde caen (CaptureTarget,
  el out= de toda la familia, o nuestra casa de capturas), si una es nuestra
  (IsAgentCapture, CapturaConsumible, EnCasaDeEntregables), recogerla por su
  enlace (CapturaPorNombre, ReclamaCaptura) y consumirla o purgar las que
  esperan. Trabajo nuestro, juzgado por su nombrador y no por la jaula.
  Vivia en Lsp.Guard (V94 de la depuracion de la 1.23, B6 de la 1.28): se
  mudo sin cambiar una linea. }

interface

{ Donde deja el servidor las capturas de quien llama para devolverselas:
  SU casa de capturas (Lsp.Casa.CasaDeCapturas: su temporal, por workspace y
  agente) + ASub. Trabajo nuestro, fuera del workspace y de la jaula: el
  porque, junto a su nombrador (Lsp.Casa). }
function AgentTempDir(const ASub: string = ''): string;

{ La pregunta de las PUERTAS sobre las capturas (el lugar ltEntregables de
  Lsp.Puertas, CaptureTarget antes de que nadie dibuje, baje o recorte alli, y
  quien entrega o consume una): APath cae en la casa de capturas del
  workspace de quien llama (cualquier agente suyo) SIN enlaces en el camino.
  La juzga el nombrador y no la jaula. Hasta la 1.18.1 nadie lo miraba: un
  enlace en la carpeta de capturas llevaba el renderizador y el recorte
  FUERA de las raices (1.18.2, punto 2b). }
function EnCasaDeEntregables(const APath: string): Boolean;

{ Una CAPTURA (escritorio o Android) en una carpeta temporal del servidor (un
  .png bajo <...>\__delphi-temp\...\desktop|android\) se CONSUME al recogerla: la
  imagen en linea, o GET /files?capture= (ReclamaCaptura), la borran; desde
  la 1.18.2 (2af) delphi_fetch es para los ficheros del agente y no consume.
  David, 25-sep-2026: 'lo mas sensato es borrar la captura una vez la ha
  recogido el agente, asi de simple; nada de caches ni rotaciones ni guardar
  nada; quiere otra, que la pida'. Medido el mismo dia: 10 gestos = 41 MB en
  la raiz del workspace, purgados solo al reiniciar. Una captura pedida con
  out= explicito NO esta en esa carpeta y no se toca. }
const
  // Las subcarpetas de captura: las pasa quien llama a CaptureTarget y las
  // reconoce IsAgentCapture. UNA lista - hasta el 25-sep-2026 el reconocedor
  // solo sabia de 'desktop' y las capturas de delphi_adb ('android') se
  // acumulaban sin consumirse.
  CAPTURE_SUB_DESKTOP = 'desktop';
  CAPTURE_SUB_ANDROID = 'android';
  CAPTURE_SUB_DESIGNER = 'designer'; // delphi_designer preview (1.17.0)
  // LO que viaja desde nuestra casa - en la respuesta o por su enlace - y lo
  // que se consume: un PNG. Estaba escrito a mano en cuatro sitios (2ai-B c
  // de la 1.18.2)
  CAPTURE_EXT = '.png';

function IsAgentCapture(const APath: string): Boolean;
{ Una captura es NUESTRA si esta donde nuestro nombrador la deja: en la casa
  de capturas del workspace de quien llama, sin enlaces en el camino. EL
  decisor del consumo: quien borra (ConsumeAgentCapture) y quien lo anuncia
  (la descarga por su enlace, la imagen en linea) preguntan aqui; hasta la
  1.7.3 el anuncio lo calculaba por su cuenta y decia "consumida" de una
  captura que seguia en disco (duodecima revision). }
function CapturaConsumible(const APath: string): Boolean;
{ La inversa del enlace de una captura nuestra (Lsp.Files.DownloadLinkFor):
  del NOMBRE que lleva el enlace, el fichero, buscado por la casa de
  capturas del workspace de quien la pide sin cruzar enlaces y aceptado solo
  si es nuestro (CapturaConsumible). '' y AFile, o la negativa: un nombre
  que no es un nombre de captura, o una que ya no esta. El agente nunca ve
  la ruta de nuestra casa (David, 12-oct-2026: "nuestros procesos internos
  y nuestro temp, los agentes no deben ni olerlo"), y la jaula no juzga
  nuestro trabajo devuelto: delphi_fetch es para los ficheros del agente. }
function CapturaPorNombre(const ANombre: string; out AFile: string): string;
function ConsumeAgentCapture(const APath: string): Boolean; // nunca lanza; True = borrada
{ Las capturas NUESTRAS que esperan su descarga en la casa de capturas del
  workspace de quien llama, la de AFile, con todos sus agentes (sin contar
  AFile): las de mas de AMinutos y las que pasen de las ACuantas mas nuevas
  se borran, por ConsumeAgentCapture. Con inline=false por HTTP una
  captura se quedaba en nuestra casa hasta que alguien la recogia o hasta la
  purga del arranque: una credencial, tambien de solo lectura, llenaba el
  disco del servidor capturando sin descargar (2ab-R3 de la 1.18.2). Nunca
  lanza. }
procedure PurgaCapturasEnEspera(const AFile: string; ACuantas, AMinutos: Integer);
{ RECOGER una captura nuestra para entregarla por su enlace (GET
  /files?capture=): se reclama abriendola en EXCLUSIVA (sin compartir) con
  borrado al cerrar, se leen sus bytes y se cierra - el fichero se va con el
  handle, sin dejar nombre para un segundo GET -. La apertura exclusiva ES el
  reclamo: el que la abre gana, otro GET del mismo enlace choca con una
  violacion de comparticion y es un 404 honesto. True y ABytes si se recogio;
  False si no estaba, no es nuestra, o la tiene otro. Nunca lanza. MoveFile no
  servia de reclamo: devolvia TRUE a VARIOS GET a la vez (medido: hasta 8 de
  10, y el destino de casi todos no existia), y cada TRUE-fantasma era un 500
  FILE-046 "no se pudo leer, ya no esta" (2am de la 1.18.2; antes, revisor del
  2af: dos 200 con el rename). }
function ReclamaCaptura(const AFile: string; out ABytes: TArray<Byte>): Boolean;

{ DONDE CAE UNA CAPTURA: el "out" de toda la familia (delphi_desktop,
  delphi_adb_linux, delphi_adb), resuelto en UN sitio. Hasta la v1.0.13 era
  una CARPETA en los dos escritorios y un FICHERO obligatorio acabado en
  ".png" en delphi_adb - misma idea, mismo nombre de parametro, contrato
  distinto - y el nombre del fichero se componia a mano en tres sitios. Un
  agente que pasaba out=...\captura.png a delphi_desktop conseguia una
  CARPETA llamada captura.png.

    vacio                          -> AgentTempDir(ASub), nombre nuestro
    carpeta que existe, o acaba \  -> esa carpeta, nombre nuestro
    sin extension                  -> carpeta nueva, nombre nuestro
    extension = la de la captura   -> ESE fichero
    otra extension                 -> RECHAZADO, nombrando el formato real

  AExt es la extension REAL de la captura (con su punto), la que trae lo
  que devolvio el nodo o el dispositivo: aqui no hay ningun "png" escrito.
  Si un dia un nodo devuelve otro formato, la regla sigue valiendo y nadie
  recibe una imagen con la extension de otra (David, 2026-09-21: "y si un
  dia no es png?"). Devuelve '' y el fichero final en AFile, o la negativa.
  Un destino que elige quien llama pasa por PathDenied; el nuestro no, que
  ya sale de AgentTempDir. No crea nada: crear la carpeta es de quien la use. }
function CaptureTarget(const AOut, ASub, APrefix, AExt: string;
  out AFile: string): string; overload;
{ ...y AEnLaCasa: si la dejo en la casa de los entregables (sin out=). EL que
  lo decide, para quien tiene que saber donde dibuja, baja o coloca: la casa
  la juzga su nombrador, un out= la jaula. Lo decidian a mano adb, el
  disenador y el escritorio, cada uno con su "out vacio" (revisor del 2i). }
function CaptureTarget(const AOut, ASub, APrefix, AExt: string;
  out AFile: string; out AEnLaCasa: Boolean): string; overload;
{ ...y el fichero de TRABAJO donde el servidor baja o dibuja la captura antes
  de colocarla: el mismo AFile si va a la casa; con un out=, uno de la casa
  con AExtTrabajo (el formato de lo que viaja), y el out= se coloca despues.
  El par lo escribian adb, el disenador y el escritorio (WHEN SEEN de F1 de
  la 1.29). }
function CaptureTargetYTrabajo(const AOut, ASub, APrefix, AExt, AExtTrabajo: string;
  out AFile, ATrabajo: string; out AEnLaCasa: Boolean): string;

implementation

uses
  System.Classes,
  Winapi.Windows,
  System.SysUtils,
  System.IOUtils,
  Lsp.NetDrives,
  Lsp.Texts,
  Lsp.Rutas,
  Lsp.Casa,
  Lsp.Identidad,
  Lsp.Pascal,
  MCPServer.Logger,
  // la ultima: lo suyo pesaba mas que lo de cualquier otra unidad cuando
  // esto vivia dentro de ella, y asi sigue
  Lsp.Guard;

function IsAgentCapture(const APath: string): Boolean;
var
  Full: string;
begin
  Result := False;
  try
    Full := TPath.GetFullPath(APath);
  except
    Exit;
  end;
  Result := SameText(TPath.GetExtension(Full), CAPTURE_EXT) and
    EnTemporal(Full) and
    RutaEnLista(TPath.GetFileName(TPath.GetDirectoryName(Full)),
      [CAPTURE_SUB_DESKTOP, CAPTURE_SUB_ANDROID, CAPTURE_SUB_DESIGNER]);
end;

function CapturaConsumible(const APath: string): Boolean;
begin
  // Nuestra por el NOMBRADOR, no por la puerta: en la casa de capturas del
  // workspace de quien llama, y el confinamiento no pinta nada (es trabajo
  // nuestro). Por EL lector de la casa (EnCasaDeEntregables), SIN enlaces en
  // el camino: con un enlace a la carpeta de otro un png de alli contaba como
  // nuestro y leerlo lo BORRABA (K6 de test_captura_puertas_1182, revisor del
  // 2b de la 1.18.2)
  try
    Result := IsAgentCapture(APath) and EnCasaDeEntregables(APath);
  except
    Result := False;
  end;
end;

function ConsumeAgentCapture(const APath: string): Boolean;
begin
  // Consumir es BORRAR: el nombre no basta. Lo llaman lectores (delphi_fetch,
  // la descarga, la imagen en linea), y una referencia con una carpeta de
  // capturas perdia sus ficheros al leerlos (auditoria 25-sep-2026).
  Result := False;
  if not CapturaConsumible(APath) then
    Exit;
  try
    if TFile.Exists(APath) then
    begin
      TFile.Delete(APath);
      Result := True;
    end;
  except
    // recoger no puede fallar por no poder borrar
  end;
end;

procedure PurgaCapturasEnEspera(const AFile: string; ACuantas, AMinutos: Integer);
var
  L: TStringList;
  Limite: TDateTime;
begin
  L := TStringList.Create;
  try
    try
      Limite := Now - AMinutos / (24 * 60);
      // las de TODO el workspace, no solo la carpeta de AFile: la de cada
      // agente sale del nombre que elige su cliente, y una credencial que
      // cambiaba de nombre en cada sesion dejaba en cada carpeta sus capturas
      // sin purgar hasta reiniciar (J5 del revisor de cierre de la 1.18.2,
      // medido). Por el recorredor de NUESTRA casa (sin cruzar enlaces), no
      // por WalkFiles: ese es el de lo que el agente lee y pregunta a la
      // jaula, que no es de lo interno - devolvia nada y no se purgaba
      // ninguna (medido, Q1/Q2 de test_capturas_en_espera_1182)
      RecorreSinEnlaces(CasaDeCapturas,
        procedure(const F: string)
        begin
          try
            if not SameFileName(F, AFile) and TFile.Exists(F) and CapturaConsumible(F) then
            begin
              var T := TFile.GetLastWriteTime(F);
              if T < Limite then
                ConsumeAgentCapture(F)
              else
                // por su marca de tiempo: ordenadas, de la mas vieja a la mas nueva
                L.Add(FormatDateTime('yyyymmddhhnnsszzz', T) + '|' + F);
            end;
          except
            // una que no se deja mirar se queda; las demas, no
          end;
        end);
      L.Sort;
      // AFile es una de las ACuantas: quedan ACuantas - 1 de las demas
      for var I := 0 to L.Count - ACuantas do
        ConsumeAgentCapture(Copy(L[I], Pos('|', L[I]) + 1, MaxInt));
    except
      // recoger no puede tumbar la entrega
    end;
  finally
    L.Free;
  end;
end;

function ReclamaCaptura(const AFile: string; out ABytes: TArray<Byte>): Boolean;
const
  TOPE = Int64(512) * 1024 * 1024; // una captura es de unos MB; tope defensivo
  ACCESO_BORRAR = $00010000; // DELETE: Winapi no lo declara y Delete es la RTL
var
  H: THandle;
  Tam: Int64;
  Leido: DWORD;
begin
  Result := False;
  ABytes := nil;
  try
    if not CapturaConsumible(AFile) then
      Exit;
    // EXCLUSIVA (ShareMode 0) y borrado al cerrar: el reclamo es la apertura
    // -uno gana, el resto choca con ERROR_SHARING_VIOLATION (404)- y el
    // fichero se va con el handle. MoveFile daba TRUE a varios a la vez (2am).
    H := CreateFile(PChar(AFile), GENERIC_READ or ACCESO_BORRAR, 0, nil,
      OPEN_EXISTING, FILE_FLAG_DELETE_ON_CLOSE, 0);
    if H = INVALID_HANDLE_VALUE then
      Exit;
    try
      Tam := 0;
      if (not GetFileSizeEx(H, Tam)) or (Tam <= 0) or (Tam > TOPE) then
        Exit; // se cierra y se borra igual (DELETE_ON_CLOSE)
      SetLength(ABytes, Tam);
      if (not ReadFile(H, ABytes[0], DWORD(Tam), Leido, nil)) or (Leido <> Tam) then
      begin
        ABytes := nil;
        Exit;
      end;
      Result := True;
    finally
      CloseHandle(H); // borra el fichero (FILE_FLAG_DELETE_ON_CLOSE)
    end;
  except
    ABytes := nil;
    Result := False;
  end;
end;

function CapturaPorNombre(const ANombre: string; out AFile: string): string;
var
  Nombre, Hallada: string;
begin
  AFile := '';
  Nombre := ANombre;
  // un NOMBRE y nada mas: ni carpeta, ni unidad, ni stream; y el de una captura
  try
    if not EsNombreSueltoEn(CasaDeCapturas, Nombre) or
       not SameText(TPath.GetExtension(Nombre), CAPTURE_EXT) then
      Exit(MsgText(SR_FILES_CAPTURA_NOMBRE));
  except
    Exit(MsgText(SR_FILES_CAPTURA_NOMBRE));
  end;
  Hallada := '';
  RecorreSinEnlaces(CasaDeCapturas,
    procedure(const P: string)
    begin
      if (Hallada = '') and SameFileName(TPath.GetFileName(P), Nombre) and
         TFile.Exists(P) and CapturaConsumible(P) then
        Hallada := P;
    end);
  if Hallada = '' then
    Exit(MsgText(SR_FILES_CAPTURA_NO_ESTA));
  AFile := Hallada;
  Result := '';
end;

function EnCasaDeEntregables(const APath: string): Boolean;
begin
  // la casa de capturas del workspace de quien llama, sin enlaces por debajo
  // de la temporal del servidor: un enlace plantado alli no saca nada de ella
  // (S3 de test_captura_puertas_1182). Ningun agente escribe en la temporal
  // del servidor: plantarlo pide estar ya en la maquina
  Result := EnLugarSinEnlaces(APath, ServerTempDir('')) and
    EnLugarSinEnlaces(APath, CasaDeCapturas);
end;

{ La casa de capturas de quien llama (Lsp.Casa.CasaDeCapturas: su workspace
  y su agente) + ASub. La subcarpeta del agente sale de la misma identidad
  que usa el modo confinado, asi que dos agentes no se pisan - y cuando no
  hay identidad (stdio, la consola del operador) no se inventa una. Hasta la
  1.18.2 iba DENTRO del workspace, en el __delphi-temp de la primera raiz
  escribible (la nota, en Lsp.Casa). El vaciado NO se hace aqui: lo hace la
  purga del arranque (PurgeServerTemp); a mitad de sesion se llevaria por
  delante la captura que otro agente acaba de pedir y aun no se ha bajado. }
function AgentTempDir(const ASub: string): string;
begin
  Result := CasaDeCapturas(CurrentAgent);
  if ASub <> '' then
    Result := TPath.Combine(Result, ASub);
end;

function CaptureTarget(const AOut, ASub, APrefix, AExt: string;
  out AFile: string): string;
var
  EnLaCasa: Boolean;
begin
  Result := CaptureTarget(AOut, ASub, APrefix, AExt, AFile, EnLaCasa);
end;

function CaptureTargetYTrabajo(const AOut, ASub, APrefix, AExt, AExtTrabajo: string;
  out AFile, ATrabajo: string; out AEnLaCasa: Boolean): string;
begin
  ATrabajo := '';
  Result := CaptureTarget(AOut, ASub, APrefix, AExt, AFile, AEnLaCasa);
  if Result <> '' then
    Exit;
  ATrabajo := AFile;
  if not AEnLaCasa then
    Result := CaptureTarget('', ASub, APrefix, AExtTrabajo, ATrabajo);
end;

function CaptureTarget(const AOut, ASub, APrefix, AExt: string;
  out AFile: string; out AEnLaCasa: Boolean): string;
var
  O, Carpeta, Ext: string;
begin
  Result := '';
  AFile := '';
  O := AOut.Trim;
  AEnLaCasa := O = '';
  // en nuestra casa, solo lo que viaja (CAPTURE_EXT): otro formato - el de un
  // nodo propio con project= - no se consumia ni tenia enlace, y su ruta, la
  // de nuestra casa, salia en la respuesta (2ai-B c de la 1.18.2). Con out=,
  // es del agente y se queda alli
  if (O = '') and not SameText(AExt, CAPTURE_EXT) then
    Exit(MsgFmt(SR_CAPTURE_SOLO_PNG_FMT, [AExt, CAPTURE_EXT]));
  Carpeta := '';
  if O = '' then
    Carpeta := AgentTempDir(ASub)
  else if O.EndsWith('\') or O.EndsWith('/') or TDirectory.Exists(O) then
    Carpeta := SinBarraFinal(O)
  else
  begin
    Ext := TPath.GetExtension(O);
    if Ext = '' then
      Carpeta := O
    else if SameText(Ext, AExt) then
      AFile := O
    else
      Exit(MsgFmt(SR_CAPTURE_EXT_FMT, [AExt, Ext]));
  end;
  if AFile = '' then
    // Milisegundos y un fragmento GUID: con resolucion de SEGUNDOS dos
    // capturas del mismo segundo compartian nombre y la segunda pisaba a la
    // primera - las dos llamadas se llevaban la misma imagen.
    AFile := TPath.Combine(Carpeta, Format('%s-%s%s', [APrefix, SelloUnico, AExt]));
  // la carpeta NUESTRA, por su nombrador y sin enlaces en el camino, ANTES de
  // que el renderizador dibuje, el nodo baje o adb deje nada alli: un enlace
  // plantado en ella llevaba la captura fuera de las raices (1.18.2, 2b)
  if (O = '') and not EnCasaDeEntregables(AFile) then
  begin
    // la carpeta, al log del operador (es quien quita el enlace); al agente
    // no se le ensena nuestra casa (2af de la 1.18.2)
    TLogger.Warning(MsgFmt(SL_CAPTURE_CASA_ENLACE_FMT, [Carpeta]));
    Exit(MsgText(SR_CAPTURE_CASA_ENLACE));
  end;
  if O <> '' then
  begin
    // la puerta de ESCRIBIR, la de todas (solo lectura incluida: una sesion
    // de solo lectura pisaba un .png con out=, tercera revision)
    Result := WriteTargetDenied(AFile);
    // Una captura no se guarda en los temporales del servidor: 90 capturas y
    // 66 MB de Hermes en una __delphi-temp anidada que la purga del arranque
    // no alcanza (25-sep-2026). Se omite out y llega en la respuesta (David:
    // 'no queremos acumular capturas, se entregan en una sola llamada y se
    // borran').
    if (Result <> '') and (DeadCopyWriteDenied(AFile) <> '') then
      Result := Result + ' ' + MsgText(SN_CAPTURE_OUT_TEMP_HINT);
  end;
end;

end.