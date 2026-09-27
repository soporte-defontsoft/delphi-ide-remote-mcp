unit Mld.Sesion;

{ UN detector de la sesion grafica de ESTE usuario, para los dos programas que
  la necesitan en el destino: el lanzador (McpRunJob completa con el el
  entorno grafico que falte) y el nodo de escritorio (no espera 20 s al
  portal si no la hay). Eran dos que no coincidian: el lanzador solo miraba
  /tmp/.X11-unix/X0, de cualquier dueno, y el nodo cualquier X de su uid o de
  root, asi que la pantalla de entrada de LightDM (Xorg de root) contaba como
  sesion y un xrdp en :10 no (revision del 26-sep-2026).

  La fuente es logind (/run/systemd/sessions/<id>): cada sesion dice de quien
  es (UID=), de que tipo (TYPE=x11, wayland, tty...) y en que estado
  (STATE=active, online, closing); la de x11 dice ademas su DISPLAY. La
  pantalla de entrada es del usuario del gestor (gdm, lightdm): no cuenta.
  logind llama a esos ficheros datos privados (lo estable es sd-login o su
  D-Bus); el formato CLAVE=valor no ha cambiado en una decada, y si un dia
  ninguno trae UID= se vuelve a los sockets. Sin logind, los sockets de ESTE
  usuario: wayland-N en su XDG_RUNTIME_DIR y X<n> de /tmp/.X11-unix que sean
  suyos. Si no se puede mirar, se da por buena: mas vale probar el portal
  que negar una sesion que existe. }

interface

type
  TSesionGrafica = record
    Hay: Boolean;
    Tipo: string;            // 'wayland' o 'x11' ('' si no se sabe)
    Display: string;         // el X de ESTE usuario: ':0', ':10'... ('' si no hay)
    WaylandDisplay: string;  // 'wayland-0'... ('' si no hay)
    Motivo: string;          // si no hay: por que, en palabras para el operador
  end;

{ La carpeta de ejecucion de ESTE usuario: XDG_RUNTIME_DIR, o la de su uid si
  el entorno no la trae. Ahi estan su bus, su socket de Wayland y la
  autorizacion de Xwayland. }
function RuntimeDelUsuario: string;

function SesionGrafica: TSesionGrafica;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  Posix.Unistd,
  Posix.SysStat,
  Mld.Textos;

function RuntimeDelUsuario: string;
begin
  Result := GetEnvironmentVariable('XDG_RUNTIME_DIR');
  if Result = '' then
    Result := '/run/user/' + IntToStr(getuid);
end;

{ El nombre del primer socket AMascara de ESTE usuario en ACarpeta
  ('wayland-0', 'X10'); '' si no hay. }
function PrimerSocketPropio(const ACarpeta, AMascara: string): string;
var
  St: _stat;
begin
  Result := '';
  if TDirectory.Exists(ACarpeta) then
    for var F in TDirectory.GetFileSystemEntries(ACarpeta, AMascara) do
      if (stat(PAnsiChar(UTF8String(F)), St) = 0) and
         ((St.st_mode and S_IFMT) = S_IFSOCK) and (St.st_uid = getuid) then
        Exit(TPath.GetFileName(F));
end;

function NombreDelUsuario: string;
begin
  Result := GetEnvironmentVariable('USER');
  if Result = '' then
    Result := GetEnvironmentVariable('LOGNAME');
  if Result = '' then
    Result := 'uid ' + IntToStr(getuid);
end;

function SesionGrafica: TSesionGrafica;
const
  SESIONES = '/run/systemd/sessions';
var
  L: TStringList;
  MiUid, Tipo, Estado, Mejor: string;
  ConUid: Boolean;
begin
  Result := Default(TSesionGrafica);
  MiUid := IntToStr(getuid);
  try
    // los sockets de ESTE usuario dan el WAYLAND_DISPLAY y el DISPLAY que
    // poner (logind no dice el X de una sesion wayland con Xwayland)
    Result.WaylandDisplay := PrimerSocketPropio(RuntimeDelUsuario, 'wayland-*');
    var X := PrimerSocketPropio('/tmp/.X11-unix', 'X*');
    if X <> '' then
      Result.Display := ':' + X.Substring(1);
    ConUid := False;
    if TDirectory.Exists(SESIONES) then
    begin
      Mejor := '';
      L := TStringList.Create;
      try
        for var F in TDirectory.GetFiles(SESIONES) do
        begin
          if F.EndsWith('.ref') then
            Continue;
          try
            L.LoadFromFile(F);
          except
            Continue; // una sesion que se cierra mientras se lee
          end;
          if L.Values['UID'] = '' then
            Continue;
          ConUid := True;
          if L.Values['UID'] <> MiUid then
            Continue;
          Tipo := L.Values['TYPE'];
          Estado := L.Values['STATE'];
          if not ((Tipo = 'x11') or (Tipo = 'wayland')) or (Estado = 'closing') then
            Continue;
          // la activa gana a la que solo esta abierta (online)
          if (Mejor = '') or (Estado = 'active') then
          begin
            Mejor := Estado;
            Result.Hay := True;
            Result.Tipo := Tipo;
            if (Tipo = 'x11') and (L.Values['DISPLAY'] <> '') then
              Result.Display := L.Values['DISPLAY'];
          end;
        end;
      finally
        L.Free;
      end;
    end;
    // sin logind, o con un formato que ya no trae UID=: los sockets de ESTE usuario
    if not ConUid then
      Result.Hay := (Result.WaylandDisplay <> '') or (Result.Display <> '');
  except
    // no se ha podido mirar: se da por buena y se prueba el portal
    Result.Hay := True;
    Exit;
  end;
  if not Result.Hay then
    Result.Motivo := MsgFmt(SF_NODE_SIN_SESION_GRAFICA_FMT, [NombreDelUsuario]);
end;

end.
