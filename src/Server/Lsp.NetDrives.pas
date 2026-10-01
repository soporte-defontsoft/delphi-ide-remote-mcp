unit Lsp.NetDrives;

{ Las letras de RED de los sitios declarados, al arrancar.

  Un sitio (una raiz, una referencia) se declara con su letra, y una letra de
  red es de la SESION que la conecto: un servicio, aunque corra con la misma
  cuenta que el escritorio, no ve las que se conectaron alli (medido el
  1-oct-2026 con un programa lanzado por el servicio: solo existen las
  unidades locales). Una raiz en una letra asi fallaba en cada llamada - "the
  drive cannot be found" - y el arranque no decia nada.
  Lo que la cuenta SI comparte entre sus sesiones es su registro, y los
  mapeos que se conectan "al iniciar sesion" estan en HKCU\Network\<letra>
  (RemotePath). Al arrancar, por cada letra de un sitio declarado que este
  proceso no ve, se busca ahi, se conecta para este proceso y se comprueba
  que se entra a lo declarado; cada paso sale como nota de arranque, y lo que
  no va, como aviso. Nada se guarda en ningun sitio: ni el recurso en el
  settings.ini, ni la conexion en el perfil, ni una credencial (no se pasa
  ninguna; en el caso medido - un recurso cuyas credenciales no son las de
  la cuenta - conecto).
  La letra que tiene mapeo y no conecta porque la red o el recurso no estan
  - el servicio arranco antes que la red, el recurso esta apagado - se vuelve
  a intentar en segundo plano, y se dice en el log cuando conecta (David,
  1-oct-2026). Solo esa: con un error de credenciales no se insiste.

  La regla va separada de la maquina: lo que pregunta (TManosDeUnidades) se
  le da hecho, y asi se prueba sin unidades ni red. Las manos de Windows,
  abajo. }

interface

const
  { Lo que el arranque espera, como mucho, a que la red conteste: un recurso
    que no responde tarda lo que Windows quiera. Pasado el plazo el arranque
    sigue, y lo que se estaba mirando acaba por su cuenta y lo dice en el log. }
  PLAZO_LETRAS_DE_RED_MS = 15000;
  { Cada cuanto se vuelve a intentar una letra que tiene mapeo y no conecto. }
  REINTENTO_LETRAS_DE_RED_MS = 30000;

type
  { Lo que la sesion de ESTE proceso sabe de una letra, por su tabla de
    unidades (local, sin abrir nada). }
  TClaseDeLetra = (clAusente, clDeRed, clLocal);

  TPreguntaClase = reference to function(ALetra: Char): TClaseDeLetra;
  TPreguntaRecurso = reference to function(ALetra: Char): string;
  TOrdenConecta = reference to function(ALetra: Char;
    const ARecurso: string): Cardinal;
  TPreguntaEntra = reference to function(const ASitio: string): Cardinal;

  { Lo que la regla pregunta a la maquina. Las dos primeras son locales (la
    tabla de unidades, el registro); las dos ultimas salen a la red y tardan
    lo que tarde un recurso que no contesta. }
  TManosDeUnidades = record
    Clase: TPreguntaClase;     // que es esa letra para este proceso
    Recurso: TPreguntaRecurso; // el recurso de su mapeo persistente; '' = no hay
    Conecta: TOrdenConecta;    // conecta la letra al recurso; 0 = hecho, o el error de Windows
    Entra: TPreguntaEntra;     // 0 = el sitio es una carpeta que se abre, o el error de Windows
  end;

  { A donde va una nota que ya no cabe en las del arranque: las del primer
    repaso si acabo pasado el plazo, y las de los reintentos. }
  TDiceNota = reference to procedure(const ANota: string);

{ La letra (en mayuscula) de una ruta escrita con unidad, #0 si no lo esta
  (un UNC, una relativa). }
function LetraDeRuta(const ARuta: string): Char;
{ LAS DOS formas de quitar la barra final de una ruta, y nadie mas la quita
  (el ExcludeTrailingPathDelimiter de la RTL solo se llama desde aqui; lo
  vigila test_raiz_unidad). Para Windows "N:" a secas no es la raiz de N:
  sino su carpeta ACTUAL, y este servidor no trabaja con rutas relativas: una
  raiz que es la unidad entera (Roots=N:\) quedaba en "N:" al quitarle la
  barra, y con el servidor instalado en esa misma unidad la raiz pasaba a
  ser la carpeta desde la que corria (medido el 1-oct-2026: 18 de 30
  comprobaciones de test_raiz_unidad en rojo).

  SinBarraFinal: para USAR o ENSENAR una ruta. La raiz de una unidad
  conserva su barra ("N:\"), y una unidad a secas la recibe.
  PrefijoSinBarra: para hacer CUENTAS con el texto (pegarle '\resto', medir
  su longitud, partirlo). Sin la barra siempre: de "N:\" queda "N:". Lo que
  devuelve no es una ruta que se pueda dar a Windows.
  RaizSiUnidad: una unidad a secas ("N:"), con su barra; lo demas, como
  viene. Para quien recibe una ruta y no le quita nada. }
function SinBarraFinal(const ASitio: string): string;
function PrefijoSinBarra(const ARuta: string): string;
function RaizSiUnidad(const ARuta: string): string;
{ Que es esa letra para este proceso: la tabla de unidades de su sesion, sin
  tocar el disco ni la red. EL lector de esa tabla. }
function ClaseDeLetra(ALetra: Char): TClaseDeLetra;
function ManosDeWindows: TManosDeUnidades;
{ La nota, al log del servidor: un aviso si empieza por SL_MARCA_AVISO (la
  misma lectura que Lsp.Host hace de las notas de arranque). El TDiceNota de
  un servidor. }
procedure NotaAlLog(const ANota: string);

{ La regla. Por cada letra de ASitios (los que se escribieron con unidad; lo
  demas no es de aqui), en el orden en que aparecen:
  - local: nada;
  - ausente con mapeo persistente: se conecta, y se dice. Si Windows contesta
    un error pero la letra YA es de red - otro proceso de la sesion la
    conecto a la vez -, se dice eso. Si no conecto, aviso; y si el error es
    el de una red o un recurso que no estan, la letra queda en APendientes
    (un error de credenciales o de permiso no se reintenta);
  - ausente sin mapeo: aviso, y no se intenta nada;
  - de red (ya lo era, o acaba de conectarse): se entra a cada sitio de esa
    letra, y se dice cual se abre y cual no.
  Devuelve las notas; las que son un aviso empiezan por SL_MARCA_AVISO. No
  cambia nada mas: un sitio al que no se entra sigue declarado. }
function RevisaLetrasDeRed(const ASitios: TArray<string>;
  const AManos: TManosDeUnidades; out APendientes: string): TArray<string>;
{ Otra vuelta sobre APendientes: la letra que ahora conecta - o que ya es de
  red - sale de la lista y deja sus notas (conectada, y a que se entra); la
  que sigue sin red se queda y no dice nada (su aviso ya se dio); la que ya
  no tiene mapeo, o topa ahora con otro error, sale con su aviso. }
function ReintentaLetrasDeRed(const ASitios: TArray<string>;
  const AManos: TManosDeUnidades; var APendientes: string): TArray<string>;
{ El arranque. Si ninguna letra es de red ni falta, no hace nada (ni un
  hilo). Si las hay, la regla corre aparte y se la espera APlazoMs: sus notas
  son el resultado. Pasado el plazo vuelve UN aviso y el arranque sigue; la
  regla acaba por su cuenta y sus notas van a ADice. Y mientras queden letras
  pendientes, el mismo hilo las reintenta cada AReintentoMs y dice a ADice lo
  que cambie, hasta que no quede ninguna o acabe el proceso. }
function VigilaLetrasDeRed(const ASitios: TArray<string>;
  const AManos: TManosDeUnidades; APlazoMs, AReintentoMs: Cardinal;
  const ADice: TDiceNota): TArray<string>;
{ Cuantos hilos de VigilaLetrasDeRed siguen vivos (el que ya no tiene letras
  pendientes acaba). Para quien tiene que saber que la regla ha TERMINADO y
  no va a decir nada mas: las pruebas esperaban un silencio, que no lo dice. }
function VigilantesVivos: Integer;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Win.Registry,
  MCPServer.Logger,
  Lsp.Texts;

function LetraDeRuta(const ARuta: string): Char;
begin
  Result := #0;
  if (Length(ARuta) >= 2) and (ARuta[2] = ':') and
     CharInSet(ARuta[1], ['A' .. 'Z', 'a' .. 'z']) then
    Result := UpCase(ARuta[1]);
end;

function RaizSiUnidad(const ARuta: string): string;
begin
  Result := ARuta;
  if (Length(Result) = 2) and (LetraDeRuta(Result) <> #0) then
    Result := Result + '\';
end;

function PrefijoSinBarra(const ARuta: string): string;
begin
  Result := ExcludeTrailingPathDelimiter(ARuta);
end;

function SinBarraFinal(const ASitio: string): string;
begin
  Result := RaizSiUnidad(ExcludeTrailingPathDelimiter(ASitio));
end;

function ClaseDeLetra(ALetra: Char): TClaseDeLetra;
begin
  case GetDriveType(PChar(UpCase(ALetra) + ':\')) of
    DRIVE_NO_ROOT_DIR:
      Result := clAusente;
    DRIVE_REMOTE:
      Result := clDeRed;
  else
    Result := clLocal;
  end;
end;

{ El recurso del mapeo PERSISTENTE de esa letra en la cuenta de este proceso:
  HKCU\Network\<letra>, RemotePath. '' si no hay, o si no es un recurso de
  red. Solo lee. }
function RecursoPersistente(ALetra: Char): string;
var
  Reg: TRegistry;
begin
  Result := '';
  try
    Reg := TRegistry.Create(KEY_READ);
    try
      Reg.RootKey := HKEY_CURRENT_USER;
      if Reg.OpenKeyReadOnly('Network\' + UpCase(ALetra)) then
      try
        if Reg.ValueExists('RemotePath') then
          Result := Reg.ReadString('RemotePath').Trim;
      finally
        Reg.CloseKey;
      end;
    finally
      Reg.Free;
    end;
  except
    // un valor que no es un texto, una clave que no se deja leer: no hay mapeo
    Result := '';
  end;
  if not Result.StartsWith('\\') then
    Result := '';
end;

{ Conecta la letra al recurso para la sesion de este proceso. Sin nombre ni
  contrasena (cuales usa Windows entonces no se ha mirado: en el caso medido,
  con un recurso cuyas credenciales no son las de la cuenta, conecto). Sin
  apuntarlo en el perfil: el mapeo persistente ya esta, y es del operador. }
function ConectaLetra(ALetra: Char; const ARecurso: string): Cardinal;
var
  Red: TNetResource;
  Unidad: string;
begin
  Unidad := UpCase(ALetra) + ':';
  FillChar(Red, SizeOf(Red), 0);
  Red.dwType := RESOURCETYPE_DISK;
  Red.lpLocalName := PChar(Unidad);
  Red.lpRemoteName := PChar(ARecurso);
  Result := WNetAddConnection2(Red, nil, nil, 0);
end;

function ErrorAlEntrar(const ASitio: string): Cardinal;
var
  Atr: DWORD;
begin
  Atr := GetFileAttributes(PChar(SinBarraFinal(ASitio)));
  if Atr = INVALID_FILE_ATTRIBUTES then
  begin
    Result := GetLastError;
    if Result = ERROR_SUCCESS then
      Result := ERROR_PATH_NOT_FOUND;
  end
  else if (Atr and FILE_ATTRIBUTE_DIRECTORY) = 0 then
    Result := ERROR_DIRECTORY // un sitio es una carpeta
  else
    Result := ERROR_SUCCESS;
end;

procedure NotaAlLog(const ANota: string);
begin
  if ANota.StartsWith(SL_MARCA_AVISO) then
    TLogger.Warning(ANota)
  else
    TLogger.Info(ANota);
end;

function ManosDeWindows: TManosDeUnidades;
begin
  Result.Clase := ClaseDeLetra;
  Result.Recurso := RecursoPersistente;
  Result.Conecta := ConectaLetra;
  Result.Entra := ErrorAlEntrar;
end;

{ Los sitios escritos con unidad, una vez cada uno (el mismo en dos
  workspaces es el mismo), en el orden en que llegan. }
function SitiosConLetra(const ASitios: TArray<string>): TArray<string>;
var
  S, T, Visto: string;
  Repetido: Boolean;
begin
  Result := nil;
  for S in ASitios do
  begin
    T := S.Trim;
    if LetraDeRuta(T) = #0 then
      Continue;
    Repetido := False;
    for Visto in Result do
      if SameText(SinBarraFinal(Visto), SinBarraFinal(T)) then
      begin
        Repetido := True;
        Break;
      end;
    if not Repetido then
      Result := Result + [T];
  end;
end;

{ Las letras de esos sitios, una vez cada una, en el orden en que aparecen. }
function LetrasDe(const ASitios: TArray<string>): string;
var
  S: string;
  L: Char;
begin
  Result := '';
  for S in ASitios do
  begin
    L := LetraDeRuta(S);
    if (L <> #0) and (Pos(L, Result) = 0) then
      Result := Result + L;
  end;
end;

function SitiosDeLetra(const ASitios: TArray<string>; ALetra: Char): string;
var
  S: string;
begin
  Result := '';
  for S in ASitios do
    if LetraDeRuta(S) = ALetra then
    begin
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + SinBarraFinal(S);
    end;
end;

function TextoDeError(ACodigo: Cardinal): string;
begin
  Result := SysErrorMessage(ACodigo).Trim;
end;

{ Una letra de red - la que ya lo era y la recien conectada -: se entra a
  cada sitio declarado en ella? }
procedure NotasDeSusSitios(const ASitios: TArray<string>; ALetra: Char;
  const AManos: TManosDeUnidades; var ANotas: TArray<string>);
var
  S: string;
  Codigo: Cardinal;
  T0: UInt64;
  Ms: Integer;
begin
  for S in ASitios do
    if LetraDeRuta(S) = ALetra then
    begin
      T0 := GetTickCount64;
      Codigo := AManos.Entra(S);
      Ms := Integer(GetTickCount64 - T0);
      if Codigo = ERROR_SUCCESS then
        ANotas := ANotas + [MsgFmt(SL_NET_SITIO_ENTRA_FMT,
          [ALetra, SinBarraFinal(S), Ms])]
      else
        ANotas := ANotas + [MsgFmt(SL_NET_SITIO_NO_ENTRA_FMT,
          [SinBarraFinal(S), ALetra, Codigo, TextoDeError(Codigo), Ms])];
    end;
end;

{ Conecta una letra ausente a su recurso. True si la letra queda de red: la
  conecto, y lo dice; o Windows contesto un error pero la letra YA lo es -
  otro proceso de la sesion la conecto a la vez (ERROR_ALREADY_ASSIGNED) -, y
  dice eso. False: no conecto; ACodigo y AMs son los del intento. }
function ConectaYDice(ALetra: Char; const ARecurso: string;
  const AManos: TManosDeUnidades; var ANotas: TArray<string>;
  out ACodigo: Cardinal; out AMs: Integer): Boolean;
var
  T0: UInt64;
begin
  T0 := GetTickCount64;
  ACodigo := AManos.Conecta(ALetra, ARecurso);
  AMs := Integer(GetTickCount64 - T0);
  Result := True;
  if ACodigo = ERROR_SUCCESS then
    ANotas := ANotas + [MsgFmt(SL_NET_LETRA_CONECTADA_FMT,
      [ALetra, ARecurso, ALetra, AMs])]
  else if AManos.Clase(ALetra) = clDeRed then
    ANotas := ANotas + [MsgFmt(SL_NET_LETRA_YA_CONECTADA_FMT, [ALetra])]
  else
    Result := False;
end;

{ El error dice que la red o el recurso NO ESTAN (todavia): es lo unico que
  se reintenta. Con un error de credenciales o de permiso, insistir cada 30 s
  serian dos inicios de sesion fallidos por minuto contra el recurso, para
  siempre (segunda revision de la 1.9.0). Lista corta y cerrada: lo que no
  esta en ella no se reintenta.
  El 67, MEDIDO el 1-oct-2026 (WNetAddConnection2, sin letra): lo da igual
  un host que no existe o no se resuelve (2,1 s la primera vez) que un
  recurso que no existe en un servidor que si contesta. Es lo que contesta
  un NAS apagado, y por eso se reintenta; el precio es insistir cada 30 s
  con un recurso que alguien quito del servidor, sin credenciales de por
  medio (la sesion ya esta abierta: no es un inicio de sesion fallido). }
function EsFaltaDeRed(ACodigo: Cardinal): Boolean;
begin
  case ACodigo of
    51,    // ERROR_REM_NOT_LIST: el equipo remoto no esta disponible
    53,    // ERROR_BAD_NETPATH: no se encontro la ruta de red
    54,    // ERROR_NETWORK_BUSY
    59,    // ERROR_UNEXP_NET_ERR
    64,    // ERROR_NETNAME_DELETED
    67,    // ERROR_BAD_NET_NAME: no se encuentra el nombre de red
    121,   // ERROR_SEM_TIMEOUT
    1203,  // ERROR_NO_NET_OR_BAD_PATH
    1222,  // ERROR_NO_NETWORK: la red no esta presente o no se ha iniciado
    1231,  // ERROR_NETWORK_UNREACHABLE
    1232,  // ERROR_HOST_UNREACHABLE
    1460:  // ERROR_TIMEOUT
      Result := True;
  else
    Result := False;
  end;
end;

{ El aviso de una letra que no conecto, con lo que el servidor hara despues. }
function NotaDeNoConecta(ALetra: Char; const ARecurso, ASusSitios: string;
  ACodigo: Cardinal; AMs: Integer): string;
var
  Despues: string;
begin
  if EsFaltaDeRed(ACodigo) then
    Despues := MsgText(SF_NET_SE_REINTENTA)
  else
    Despues := MsgText(SF_NET_NO_SE_REINTENTA);
  Result := MsgFmt(SL_NET_LETRA_NO_CONECTA_FMT, [ALetra, ARecurso, ALetra, AMs,
    ACodigo, TextoDeError(ACodigo), ASusSitios, Despues]);
end;

function RevisaLetrasDeRed(const ASitios: TArray<string>;
  const AManos: TManosDeUnidades; out APendientes: string): TArray<string>;
var
  Sitios: TArray<string>;
  L: Char;
  Recurso: string;
  Codigo: Cardinal;
  Ms: Integer;
begin
  Result := nil;
  APendientes := '';
  Sitios := SitiosConLetra(ASitios);
  for L in LetrasDe(Sitios) do
  begin
    case AManos.Clase(L) of
      clLocal:
        Continue;
      clAusente:
        begin
          Recurso := AManos.Recurso(L);
          if Recurso = '' then
          begin
            Result := Result + [MsgFmt(SL_NET_LETRA_SIN_MAPEO_FMT,
              [L, L, SitiosDeLetra(Sitios, L)])];
            Continue;
          end;
          if not ConectaYDice(L, Recurso, AManos, Result, Codigo, Ms) then
          begin
            Result := Result + [NotaDeNoConecta(L, Recurso,
              SitiosDeLetra(Sitios, L), Codigo, Ms)];
            if EsFaltaDeRed(Codigo) then
              APendientes := APendientes + L;
            Continue;
          end;
        end;
    end;
    NotasDeSusSitios(Sitios, L, AManos, Result);
  end;
end;

function ReintentaLetrasDeRed(const ASitios: TArray<string>;
  const AManos: TManosDeUnidades; var APendientes: string): TArray<string>;
var
  Sitios: TArray<string>;
  L: Char;
  Siguen, Recurso: string;
  Codigo: Cardinal;
  Ms: Integer;
begin
  Result := nil;
  Sitios := SitiosConLetra(ASitios);
  Siguen := '';
  for L in APendientes do
  begin
    case AManos.Clase(L) of
      clLocal:
        Continue; // ya no es una letra de red: no es de aqui
      clDeRed:
        Result := Result + [MsgFmt(SL_NET_LETRA_YA_CONECTADA_FMT, [L])];
      clAusente:
        begin
          Recurso := AManos.Recurso(L);
          if Recurso = '' then
          begin
            // el mapeo ya no esta: no hay a que conectarla, y no se insiste
            Result := Result + [MsgFmt(SL_NET_LETRA_SIN_MAPEO_FMT,
              [L, L, SitiosDeLetra(Sitios, L)])];
            Continue;
          end;
          if not ConectaYDice(L, Recurso, AManos, Result, Codigo, Ms) then
          begin
            if EsFaltaDeRed(Codigo) then
              Siguen := Siguen + L // sin nota: su aviso ya se dio
            else
              // la red ya esta y Windows dice otra cosa (credenciales, un
              // permiso): se dice, y no se insiste
              Result := Result + [NotaDeNoConecta(L, Recurso,
                SitiosDeLetra(Sitios, L), Codigo, Ms)];
            Continue;
          end;
        end;
    end;
    NotasDeSusSitios(Sitios, L, AManos, Result);
  end;
  APendientes := Siguen;
end;

{ Las letras de ASitios que no son locales para este proceso: las que la
  regla tendria que mirar saliendo a la red. }
function LetrasQueRevisar(const ASitios: TArray<string>;
  const AManos: TManosDeUnidades): string;
var
  L: Char;
begin
  Result := '';
  for L in LetrasDe(SitiosConLetra(ASitios)) do
    if AManos.Clase(L) <> clLocal then
    begin
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + L + ':';
    end;
end;

type
  { Donde el hilo deja las notas de su primer repaso para quien las espera.
    La sujetan los dos. O las recoge quien espera, o las dice el hilo: si el
    plazo vence, quien esperaba se va (Espera devuelve False) y el hilo, al
    llegar, lo sabe (Pon devuelve False) y las manda por el otro camino. }
  ICajaDeNotas = interface
    function Pon(const ANotas: TArray<string>): Boolean;
    function Espera(APlazoMs: Cardinal; out ANotas: TArray<string>): Boolean;
  end;

  TCajaDeNotas = class(TInterfacedObject, ICajaDeNotas)
  private
    FCandado: TCriticalSection;
    FHecho: TEvent;
    FNotas: TArray<string>;
    FPuestas, FAbandonada: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    function Pon(const ANotas: TArray<string>): Boolean;
    function Espera(APlazoMs: Cardinal; out ANotas: TArray<string>): Boolean;
  end;

constructor TCajaDeNotas.Create;
begin
  inherited Create;
  FCandado := TCriticalSection.Create;
  FHecho := TEvent.Create(nil, True, False, '');
end;

destructor TCajaDeNotas.Destroy;
begin
  FHecho.Free;
  FCandado.Free;
  inherited;
end;

function TCajaDeNotas.Pon(const ANotas: TArray<string>): Boolean;
begin
  FCandado.Enter;
  try
    Result := not FAbandonada;
    if Result then
    begin
      FNotas := ANotas;
      FPuestas := True;
    end;
  finally
    FCandado.Leave;
  end;
  if Result then
    FHecho.SetEvent;
end;

function TCajaDeNotas.Espera(APlazoMs: Cardinal;
  out ANotas: TArray<string>): Boolean;
begin
  ANotas := nil;
  FHecho.WaitFor(APlazoMs);
  // con el candado: las notas que llegan justo al vencer el plazo las
  // recoge quien espera o las dice el hilo, nunca ninguno
  FCandado.Enter;
  try
    Result := FPuestas;
    if Result then
      ANotas := FNotas
    else
      FAbandonada := True;
  finally
    FCandado.Leave;
  end;
end;

procedure DiTodas(const ADice: TDiceNota; const ANotas: TArray<string>);
var
  N: string;
begin
  if not Assigned(ADice) then
    Exit;
  for N in ANotas do
    try
      ADice(N);
    except
      // quien escucha fallo: esa nota se pierde, el hilo sigue
    end;
end;

var
  GVigilantes: Integer = 0;

function VigilantesVivos: Integer;
begin
  Result := TInterlocked.CompareExchange(GVigilantes, 0, 0);
end;

function VigilaLetrasDeRed(const ASitios: TArray<string>;
  const AManos: TManosDeUnidades; APlazoMs, AReintentoMs: Cardinal;
  const ADice: TDiceNota): TArray<string>;
var
  Sitios: TArray<string>;
  Manos: TManosDeUnidades;
  Dice: TDiceNota;
  Reintento: Cardinal;
  Caja: ICajaDeNotas;
  Letras: string;
begin
  Result := nil;
  Letras := LetrasQueRevisar(ASitios, AManos);
  if Letras = '' then
    Exit;
  Sitios := ASitios;
  Manos := AManos;
  Dice := ADice;
  Reintento := AReintentoMs;
  Caja := TCajaDeNotas.Create;
  TInterlocked.Increment(GVigilantes); // antes de lanzarlo: quien mire ya lo cuenta
  TThread.CreateAnonymousThread(
    procedure
    var
      Notas: TArray<string>;
      Pendientes: string;
    begin
      try
      Pendientes := '';
      try
        Notas := RevisaLetrasDeRed(Sitios, Manos, Pendientes);
      except
        on E: Exception do
        begin
          Notas := [MsgFmt(SL_NET_REVISION_FALLO_FMT, [E.ClassName, E.Message])];
          Pendientes := '';
        end;
      end;
      // quien esperaba ya se fue (vencio el plazo): al log
      if not Caja.Pon(Notas) then
        DiTodas(Dice, Notas);
      // lo que tiene mapeo y no conecto porque la red no estaba: otra vez,
      // hasta que conecte. El hilo no se despierta para acabar con el
      // proceso: dormido, se va con el; despertarlo en la finalizacion lo
      // ponia a liberar lo suyo a la vez que la RTL (segunda revision)
      while Pendientes <> '' do
      begin
        TThread.Sleep(Reintento);
        try
          Notas := ReintentaLetrasDeRed(Sitios, Manos, Pendientes);
        except
          on E: Exception do
          begin
            Notas := [MsgFmt(SL_NET_REVISION_FALLO_FMT, [E.ClassName, E.Message])];
            Pendientes := '';
          end;
        end;
        DiTodas(Dice, Notas);
      end;
      finally
        TInterlocked.Decrement(GVigilantes);
      end;
    end).Start;
  if not Caja.Espera(APlazoMs, Result) then
    Result := [MsgFmt(SL_NET_PLAZO_FMT, [Letras, APlazoMs div 1000])];
end;

end.
