unit Lsp.PurgaDelArranque;

{ LA PURGA DEL ARRANQUE y la presencia de cada instancia: al arrancar se vacia
  la casa del servidor (PurgeServerTemp) solo si este proceso es la PRIMERA
  instancia viva de este exe (SoyLaPrimeraInstancia) y la UNICA de su casa
  (HayOtraInstanciaViva, por la presencia que cada una apunta,
  ApuntaPresencia); ReclamaNombre es la regla de "de quien es esto mientras
  vive". Lo llama Lsp.Host al arrancar. Pregunta a la jaula (VaciaDesechable)
  y Lsp.Guard no usa nada de aqui. Vivia en Lsp.Guard (V94 de la depuracion
  de la 1.23, B6 de la 1.28): se mudo sin cambiar una linea. }

interface

{ Vacia la casa del servidor al arrancar. Lo que hay ahi pertenece a la
  llamada que lo creo y ninguna llamada sobrevive a un reinicio, asi que al
  arrancar TODO lo que quede es basura de una ejecucion anterior - la que
  dejo 56,4 MB olvidados en el %TEMP% de la maquina durante dos dias, medido
  el 2026-09-21. Solo purga la PRIMERA instancia viva de este exe: la
  premisa "el servidor y la bandeja no pueden correr a la vez, comparten
  puerto" no vale para stdio, que no abre puerto ninguno y comparte la
  carpeta con el servicio - su purga borraria ficheros EN USO de una
  llamada en vuelo del otro (el -F de un commit, una salida de remoterun).
  Nunca lanza: un temporal que no se deja borrar no es motivo para no
  arrancar.
  Las __delphi-temp de las RAICES no se tocan (V31 de la 1.23): desde la
  1.18.2 nada nuestro vive en ellas, y su purga borraba dentro del
  workspace, que no es la casa del servidor, lo que dejaron versiones
  anteriores. Lo que quede es del operador. }
procedure PurgeServerTemp;

implementation

uses
  Winapi.Windows,
  Winapi.TlHelp32,      // HayOtraInstanciaViva: los procesos por su nombre, sin abrirlos
  System.SysUtils,
  System.IOUtils,
  Lsp.Sandbox,          // PurgaContenedoresHuerfanos: la otra mitad de la casa
  Lsp.Casa,
  // la ultima: lo suyo pesaba mas que lo de cualquier otra unidad cuando
  // vivia alli, y asi sigue
  Lsp.Guard;

var
  GPrimera: THandle = 0;
  GPresencia: THandle = 0; // ApuntaPresencia: esta instancia, viva

{ Reclama AClave para ESTE proceso mientras viva: un mutex global que se
  queda abierto de por vida. False si otro proceso vivo ya la tiene, o si
  no se pudo crear (otra cuenta, otro fallo): en la duda no es nuestra, y
  no purgar es la opcion sin peligro. LA regla de "de quien es esto
  mientras vive": la usan la casa del servidor y la presencia de cada
  instancia. }
function ReclamaNombre(const AClave: string; out AHandle: THandle): Boolean;
begin
  AHandle := CreateMutex(nil, False, PChar(NombreDeMutex(AClave)));
  if (AHandle <> 0) and (GetLastError = ERROR_ALREADY_EXISTS) then
  begin
    CloseHandle(AHandle);
    AHandle := 0;
  end;
  Result := AHandle <> 0;
end;

{ True si este proceso es la PRIMERA instancia viva de ESTE exe (esta
  carpeta). El mutex se queda abierto de por vida: ser el primero dura
  hasta morir, y entonces lo hereda el siguiente arranque. Sin esto, un
  arranque stdio del exe del servicio purgaba __delphi-temp con el
  servicio en marcha y una llamada en vuelo perdia su fichero (el -F de
  un commit, una salida de remoterun) - auditoria 2026-09-21. }
function SoyLaPrimeraInstancia: Boolean;
var
  H: THandle;
begin
  if GPrimera <> 0 then
    Exit(True);
  Result := ReclamaNombre(ClaveDeCarpeta(ServerDir), H);
  if Result then
    GPrimera := H;
end;

{ La clave de la presencia de la instancia APid de ESTA casa (la carpeta del
  exe): la escribe ApuntaPresencia y la lee HayOtraInstanciaViva. }
function ClaveDePresencia(APid: DWORD): string;
begin
  Result := ClaveDeCarpeta(ServerDir) + '-pid-' + IntToStr(APid);
end;

{ Esta instancia se apunta como VIVA mientras viva, sea la primera o no: un
  mutex con su PID. La primera no sabia de las demas: el servicio que
  rearranca coge el mutex libre de la primera y vaciaba lo que una instancia
  stdio del mismo exe tenia en vuelo (pendiente 2 de la 1.11.0, medido con
  test_purga_instancias). }
procedure ApuntaPresencia;
begin
  if GPresencia = 0 then
    ReclamaNombre(ClaveDePresencia(GetCurrentProcessId), GPresencia);
end;

{ True si otra instancia de ESTA casa sigue viva. Los procesos se buscan por
  el nombre del exe (Toolhelp, sin abrirlos: desde la sesion interactiva el
  proceso del servicio NO se deja abrir, medido el 3-oct - acceso denegado)
  y cada uno se pregunta por su presencia: si su mutex existe, o no se deja
  abrir, esta vivo. Uno de otra carpeta no tiene presencia con esta clave:
  el mutex se crea y se suelta al momento. En la duda, viva: no purgar es lo
  que no rompe nada. }
function HayOtraInstanciaViva: Boolean;
var
  Snap, H: THandle;
  E: TProcessEntry32;
  Mio: string;
begin
  Result := False;
  Mio := TPath.GetFileName(ParamStr(0));
  Snap := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if Snap = INVALID_HANDLE_VALUE then
    Exit(True);
  try
    E.dwSize := SizeOf(E);
    if Process32First(Snap, E) then
      repeat
        if (E.th32ProcessID <> GetCurrentProcessId) and SameFileName(string(E.szExeFile), Mio) then
        begin
          if not ReclamaNombre(ClaveDePresencia(E.th32ProcessID), H) then
            Exit(True);
          CloseHandle(H);
        end;
      until not Process32Next(Snap, E);
  finally
    CloseHandle(Snap);
  end;
end;

procedure PurgeServerTemp;
begin
  // toda instancia se apunta como viva ANTES de decidir nada
  ApuntaPresencia;
  if not SoyLaPrimeraInstancia then
    Exit;
  // ...y la primera purga solo si es la UNICA viva de esta casa: el servicio
  // que rearranca es la primera aunque una instancia stdio del mismo exe siga
  // con un test o la -F de un commit a medias. Lo que
  // queda se lo lleva el siguiente arranque a solas.
  if HayOtraInstanciaViva then
    Exit;
  // La casa del servidor, la de siempre.
  VaciaDesechable(ServerTempDir);
  // ...y los contenedores de delphi_test que dejo una caida de ESTA casa: sus
  // copias se acaban de ir con la temporal, y el contenedor es la otra mitad.
  // Aqui y no antes del if: un arranque stdio del mismo exe no borra los del
  // servicio en marcha, como no borra sus temporales.
  PurgaContenedoresHuerfanos;
  // Las __delphi-temp de las RAICES ya no (V31 de la 1.23; su comentario
  // decia "Retirarla en la 1.19"): desde la 1.18.2 (2af) nada nuestro vive en
  // ellas -las capturas, en la casa (Lsp.Casa)- y su purga solo se llevaba lo
  // que dejaron versiones anteriores: un proceso interno del servidor
  // borrando DENTRO del workspace, y con una raiz compartida por dos
  // maquinas, lo que el servidor de la otra tuviera a medias. Lo que quede es
  // del operador: oculto en los listados y negado para escribir.
end;

end.