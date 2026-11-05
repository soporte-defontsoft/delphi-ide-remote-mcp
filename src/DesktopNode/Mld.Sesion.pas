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
  que negar una sesion que existe. El Id (el nombre del fichero) es lo que
  login1 pide por GetSession para decir si ESA sesion esta bloqueada: el
  fichero no trae el bloqueo (medido en Zorin 18 el 14-oct-2026).

  El ENTORNO grafico (DISPLAY, WAYLAND_DISPLAY, XAUTHORITY) lo dice un juez:
  el que la sesion le da al gestor de usuario de systemd al empezar (GNOME y
  Plasma lo escriben; es lo que contesta systemctl --user show-environment).
  Los sockets y el .mutter-Xwaylandauth.* mas reciente eran adivinanzas de
  GNOME: en Plasma la autorizacion es xauth_*, y una app FMX lanzada por un
  PAServer nacido antes de la sesion moria sin ella (exit 134; Fedora 44 con
  Plasma 6.8, 4-nov-2026). Quedan para cuando el gestor no contesta. }

interface

type
  TSesionGrafica = record
    Hay: Boolean;
    Tipo: string;            // 'wayland' o 'x11' ('' si no se sabe)
    Display: string;         // el X de ESTE usuario: ':0', ':10'... ('' si no hay)
    WaylandDisplay: string;  // 'wayland-0'... ('' si no hay)
    Xauthority: string;      // el fichero de autorizacion de X para XAUTHORITY ('' si no hay)
    NoPudeMirar: string;     // lo que impidio buscar esa autorizacion en la carpeta de ejecucion
    Motivo: string;          // si no hay: por que, en palabras para el operador
    Id: string;              // el id de logind de la sesion ('3'); '' si no la dio logind
    Usuario: string;         // el nombre de ESTE usuario, para los motivos
  end;

{ La carpeta de ejecucion de ESTE usuario: XDG_RUNTIME_DIR, o la de su uid si
  el entorno no la trae. Ahi estan su bus, su socket de Wayland y la
  autorizacion de Xwayland. }
function RuntimeDelUsuario: string;

{ La sesion grafica de ESTE usuario y su entorno: DISPLAY, WAYLAND_DISPLAY y
  la autorizacion de X, por el juez de la cabecera. }
function SesionGrafica: TSesionGrafica;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  Posix.Unistd,
  Posix.SysStat,
  Mld.DBus,
  Mld.Textos;

function RuntimeDelUsuario: string;
begin
  Result := GetEnvironmentVariable('XDG_RUNTIME_DIR');
  if Result = '' then
    Result := '/run/user/' + IntToStr(getuid);
end;

const
  { La autorizacion de Xwayland de mutter: cambia de sufijo en cada inicio de sesion }
  MASCARA_XWAYLANDAUTH = '.mutter-Xwaylandauth.*';

{ La adivinanza de la autorizacion de X para cuando el juez no contesta: el
  fichero mas reciente de Xwayland de mutter en ARuntime, o el ~/.Xauthority de
  siempre. '' si no hay. Lo que impida mirar ARuntime, en AError. }
function XauthorityMasReciente(const ARuntime: string; out AError: string): string;
var
  Mas: TDateTime;
begin
  Result := '';
  AError := '';
  Mas := 0;
  if ARuntime <> '' then
    try
      for var F in TDirectory.GetFiles(ARuntime, MASCARA_XWAYLANDAUTH) do
        if (Result = '') or (TFile.GetLastWriteTime(F) > Mas) then
        begin
          Result := F;
          Mas := TFile.GetLastWriteTime(F);
        end;
    except
      on E: Exception do
      begin
        Result := '';
        AError := E.Message;
      end;
    end;
  if (Result = '') and TFile.Exists(GetEnvironmentVariable('HOME') + '/.Xauthority') then
    Result := GetEnvironmentVariable('HOME') + '/.Xauthority';
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

{ El entorno que la sesion le dio al gestor de usuario de systemd (el juez de
  la cabecera), en AEntorno como CLAVE=valor: se lee con Values, como los
  ficheros de logind. Nada si el gestor no contesta. }
procedure LeeEntornoDeLaSesion(AEntorno: TStringList);
var
  Bus: TConexionBus;
  Lineas: TArray<string>;
begin
  Bus := TConexionBus.Create;
  try
    if Bus.Conectar and Bus.EntornoDelGestor(Lineas) then
      AEntorno.AddStrings(Lineas);
  finally
    Bus.Free;
  end;
end;

function SesionGrafica: TSesionGrafica;
const
  SESIONES = '/run/systemd/sessions';
var
  L, Juez: TStringList;
  MiUid, Tipo, Estado, Mejor: string;
  ConUid: Boolean;
begin
  Result := Default(TSesionGrafica);
  Result.Usuario := NombreDelUsuario;
  MiUid := IntToStr(getuid);
  // EL juez del entorno grafico (la cabecera): lo que dice, manda
  Juez := TStringList.Create;
  try
    try
      LeeEntornoDeLaSesion(Juez);
    except
      Juez.Clear; // sin libdbus o sin bus: se adivina, como antes
    end;
    Result.WaylandDisplay := Juez.Values['WAYLAND_DISPLAY'];
    Result.Display := Juez.Values['DISPLAY'];
    Result.Xauthority := Juez.Values['XAUTHORITY'];
  finally
    Juez.Free;
  end;
  // sin el: la autorizacion de Xwayland mas reciente de mutter, o ~/.Xauthority
  if Result.Xauthority = '' then
    Result.Xauthority := XauthorityMasReciente(RuntimeDelUsuario, Result.NoPudeMirar);
  try
    // sin el juez, los sockets de ESTE usuario dan el WAYLAND_DISPLAY y el
    // DISPLAY que poner (logind no dice el X de una sesion wayland con Xwayland)
    if Result.WaylandDisplay = '' then
      Result.WaylandDisplay := PrimerSocketPropio(RuntimeDelUsuario, 'wayland-*');
    if Result.Display = '' then
    begin
      var X := PrimerSocketPropio('/tmp/.X11-unix', 'X*');
      if X <> '' then
        Result.Display := ':' + X.Substring(1);
    end;
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
            Result.Id := TPath.GetFileName(F);
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
    Result.Motivo := MsgFmt(SF_NODE_SIN_SESION_GRAFICA_FMT, [Result.Usuario]);
end;

end.
