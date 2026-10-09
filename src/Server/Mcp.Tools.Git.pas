unit Mcp.Tools.Git;

{ delphi_git: las ordenes de git de la lista blanca sobre un repositorio de
  esta maquina - el compositor de la linea (ArgvSeguro, GitLinea), el
  lanzador UNICO (GitCorre), las puertas de los remotos, de los envios y de
  la configuracion del repo, y sus respuestas (GitExito / GitFallo, la
  pagina de la salida).

  Sale de Mcp.Tools.Workspace el 8-oct-2026 (la 1.18.0, la version de la
  limpieza), movida sin cambiar una linea: "donde esta git" se contestaba
  "en Workspace", que nadie adivina. Las puertas de los argumentos libres
  (GitArgDenied, GitRemoteDenied, ShellArgDenied) y la clasificacion en
  consulta o escritura viven en Lsp.Args; la jaula, en Lsp.Guard. }

interface

uses
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Texts,   // SchemaDescription texts live there, and attributes are interface-level
  Lsp.Attributes;  // [RutaDelServidor]: que parametro es una ruta NUESTRA

type
  TDelphiGitParams = class
  private
    FRepo: string;
    FCommand: string;
    FArgs: string;
    FCreate: Boolean;
    FMessage: string;
    FPath: string;
    FRef: string;
    FOffset: Integer;
  public
    [SchemaDescription(SP_WS_REPO)]
    [Required]
    [RutaDelServidor]
    property Repo: string read FRepo write FRepo;
    [SchemaDescription(SP_WS_COMMAND)]
    [Required]
    property Command: string read FCommand write FCommand;
    [SchemaDescription(SP_WS_ARGS)]
    property Args: string read FArgs write FArgs;
    [SchemaDescription(SP_WS_CREATE)]
    property Create: Boolean read FCreate write FCreate;
    [SchemaDescription(SP_WS_MESSAGE)]
    property Message: string read FMessage write FMessage;
    [SchemaDescription(SP_WS_PATH)]
    [RutaDelServidor]
    property Path: string read FPath write FPath;
    [SchemaDescription(SP_WS_REF)]
    property Ref: string read FRef write FRef;
    [SchemaDescription(SP_WS_OFFSET_GIT)]
    property Offset: Integer read FOffset write FOffset;
  end;

  TDelphiGitTool = class(TMCPToolBase<TDelphiGitParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiGitParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.StrUtils,
  System.IOUtils,
  System.RegularExpressions,
  Winapi.Windows,
  MCPServer.Registration,
  MCPServer.Logger,
  Lsp.BuildRunner,
  Lsp.Guard,
  Lsp.Patch,     // EscribeTexto: la puerta de escribir, con el temporal como lugar
  Lsp.Codificacion, // ekUtf8
  Lsp.NetDrives,
  Lsp.Sandbox,
  Lsp.Rutas,
  Lsp.Casa,
  Lsp.ProcessLaunch, // TrocearArgs y EnComillas: la linea de git
  Lsp.Args,
  Lsp.Lugares,
  Lsp.Mascara;

// la tool git va por delante de sus compositores
function GitExito(const ACuerpo: string; AExit: Integer): string; forward;
function GitFallo(ACodigo: Cardinal; const ASalida: string): string; forward;

{ TDelphiGitTool }

constructor TDelphiGitTool.Create;
begin
  inherited;
  FName := 'delphi_git';
  FDescription := SD_WS_GIT;
end;

{ Los argumentos LIBRES del usuario, recompuestos desde el argv que valida la
  puerta (TrocearArgs) con su inversa EnComillas: git.exe recibe EXACTAMENTE
  los tokens que GitArgDenied/GitRemoteDenied aprobaron, sin que la puerta
  tenga que adivinar como trocea el CRT de Windows la cadena cruda. Es la
  parte (a) del arreglo del 26-sep-2026: el ejecutor obliga a git a leer lo
  que leyo la puerta, en vez de pasar la cadena tal cual y confiar en que los
  dos parsers coincidan. }
function ArgvSeguro(const AArgs: string): string;
var
  Tok: string;
begin
  Result := '';
  for Tok in TrocearArgs(AArgs) do
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + EnComillas(Tok);
  end;
end;

{ True si los argumentos de un commit o un tag traen el MENSAJE (-m, -m<texto>,
  -am, --message, --message=): el mensaje va en "message", que llega a git por
  -F byte a byte, y los dos juntos acababan en el exit 129 de git sin un
  codigo nuestro (Hermes, validacion de la 1.16.0). }
function MensajeEnArgsGit(const AArgs: string): Boolean;
begin
  for var Tok in TrocearArgs(AArgs) do
    if Tok.StartsWith('-m') or SameText(Tok, '-am') or (Tok = '--message') or
       Tok.StartsWith('--message=') then
      Exit(True);
  Result := False;
end;

{ Las RUTAS de un comando de git que las lleva (stash push -- <rutas>,
  restore <rutas>): cada trozo desde ADesde es un fichero o carpeta DE ESTE
  repo, con su nombre tal cual (sin opciones ni comodines), y sale como
  :(literal)<relativa> entre comillas, listo para la linea de git. Con
  AEscribeFicheros cada ruta pasa por la puerta del escritor (stash push
  reescribe el fichero; restore --staged solo toca el indice). '' = bien;
  si no, la negativa con los textos de ESE comando (AComando: 'stash' o
  'restore'; cada texto sale por su helper, aqui dentro). Era el bucle de
  stash push y restore iba a ser su gemelo (1.7.6). ACarpetas: la carpeta de
  cada ruta (ella misma si es una carpeta), para quien tiene que soltar lo
  nuestro de ahi antes de que git la reescriba. }
function RutasDeGit(const ARepo, AArgs: string; const ATrozos: TArray<string>;
  ADesde: Integer; AEscribeFicheros: Boolean; const AComando: string;
  out ARutas: string; out ACarpetas: TArray<string>): string;
var
  Base, Ruta, Rel: string;
  I: Integer;
begin
  Result := '';
  ARutas := '';
  ACarpetas := nil;
  Base := IncludeTrailingPathDelimiter(TPath.GetFullPath(ARepo));
  for I := ADesde to High(ATrozos) do
  begin
    if (I = ADesde) and (ATrozos[I] = '--') then
      Continue;
    // Rutas, no opciones: -u, -k, -p, --worktree... cambian lo que se guarda
    // y lo que se toca, y ninguna hace falta.
    if ATrozos[I].StartsWith('-') or (ATrozos[I].Trim = '') then
      if SameText(AComando, 'restore') then
        Exit(MsgFmt(SR_GIT_RESTORE_ARGS_FMT, [AArgs.Trim]))
      else
        Exit(MsgFmt(SR_GIT_STASH_ARGS_FMT, [AArgs.Trim]));
    // Una ruta de ESTE repo, con su nombre tal cual: un comodin no es un
    // nombre en Windows, y lo que GetFullPath no entiende no es una ruta.
    Ruta := '';
    try
      if not (ATrozos[I].Contains('*') or ATrozos[I].Contains('?')) then
        Ruta := SinBarraFinal(TPath.GetFullPath(
          TPath.Combine(Base, ATrozos[I].Replace('/', '\'))));
    except
      Ruta := '';
    end;
    if (Ruta = '') or not StartsText(Base, IncludeTrailingPathDelimiter(Ruta)) then
      if SameText(AComando, 'restore') then
        Exit(MsgFmt(SR_GIT_RESTORE_RUTA_FMT, [ATrozos[I], ARepo]))
      else
        Exit(MsgFmt(SR_GIT_STASH_RUTA_FMT, [ATrozos[I], ARepo]));
    // Devolver un fichero a HEAD es ESCRIBIRLO: la pregunta de todo
    // escritor, por la ruta real de cada uno.
    if AEscribeFicheros then
    begin
      Result := EscrituraDenegada(Ruta);
      if Result <> '' then
        Exit;
    end;
    Rel := Ruta.Substring(Length(Base)).Replace('\', '/');
    if Rel = '' then
      Rel := '.'; // la carpeta del propio repo
    // :(literal): el nombre es el nombre, sin comodines ni magia.
    ARutas := ARutas + ' ' + EnComillas(':(literal)' + Rel);
    // la carpeta de la ruta, UNA vez cada una (dos ficheros de la misma
    // carpeta eran dos avisos, uno detras de otro)
    if not TDirectory.Exists(Ruta) then
      Ruta := ExtractFileDir(Ruta);
    if not MatchText(Ruta, ACarpetas) then
      ACarpetas := ACarpetas + [Ruta];
  end;
end;

{ LA LINEA de git, por UN compositor: git.exe, -C con la carpeta de la
  llamada - por el compositor de la casa (EnComillas), como todo argumento -,
  lo que lo fija (AFijado: --git-dir...) y el comando. Se componia a mano en
  cada sitio, con -C "%s": una carpeta acabada en barra invertida se comia
  la comilla de cierre y el resto de la linea entraba en el argumento de -C
  (medido en la 1.7.6: GIT-036, "cannot change to ..."; cuarta revision de
  la 1.7.7). }
function GitLinea(const ARepo, AFijado, AResto: string): string;
begin
  // La orden de red no hereda una recursion a remotos de submodulos sin juzgar.
  var Comando := PrimerTrozo(AResto, [' ']);
  var Resto := AResto;
  if MatchText(Comando, ['fetch', 'pull', 'push']) then
    Resto := Comando + ' --no-recurse-submodules' + Copy(AResto, Length(Comando) + 1, MaxInt);
  // Nunca ejecutar los hooks ni el monitor de un repo del workspace.
  // El directorio del servidor no admite escrituras de los clientes.
  // La regla general tambien manda en switch/restore y en los hijos de Git.
  Result := 'git.exe -c submodule.recurse=false -c core.fsmonitor=false ' +
    '-c commit.gpgsign=false -c tag.gpgsign=false -c core.hooksPath=' +
    EnComillas(ServerTempDir('git-hooks-off')) + ' -C ' +
    EnComillas(ARepo) + AFijado + ' ' + Resto;
end;

{ git, LANZADO por un solo sitio: la linea del compositor por el lanzador de
  la casa. Y el servidor SIN git lo dice aqui. CreateProcess no encuentra
  git.exe (error 2) y la llamada acababa en "[SYS-006 INTERNAL]
  ... CreateProcess failed (2)", que no dice ni que falta ni de quien es el
  arreglo (medido el 30-sep-2026 en una maquina sin git: init y status). Se
  decide con el fallo del lanzamiento DE VERDAD y no preguntando antes si
  git esta: quien lo busca por su cuenta no lo busca como CreateProcess.
  Sigue siendo una excepcion - quien pregunta para juzgar no toma un fallo
  por un "no hay" -, con el mensaje ya etiquetado. }
function GitCorre(const ARepo, AFijado, AResto: string; ATimeoutMs: Integer;
  out ACodigo: Cardinal): string;
begin
  try
    Result := RunCapturedIn(GitLinea(ARepo, AFijado, AResto), '', ATimeoutMs,
      ACodigo, EntornoSinConfiguracion(['GIT_TERMINAL_PROMPT=0', 'GCM_INTERACTIVE=never']));
  except
    on E: EOSError do
    begin
      // solo el 2, que es el medido: git se lanza por su nombre a secas y
      // un 3 no tiene de donde salir. Un git que ESTA y no arranca (5,
      // 193) no es "no hay git": sigue con el mensaje de siempre
      if E.ErrorCode = ERROR_FILE_NOT_FOUND then
        raise Exception.Create(MsgFmt(SR_GIT_NO_HAY_GIT_FMT, [E.ErrorCode]));
      raise;
    end;
  end;
end;

{ La configuracion LOCAL tambien manda programas aunque args sea limpio.
  Se lee sin includes: una inclusion del repo puede sacar la lectura de la
  jaula y esconder un filtro. La configuracion del servidor sigue siendo suya. }

function DireccionDeRemotoDenegada(const ACmd, ADireccion, ABase: string;
  out ACarpeta: string; out ANoEsta: Boolean): string; forward;

function RemotosDelRepo(const ARepo, AFijado: string;
  out ANombres: TArray<string>): Boolean; forward;

{ Medido con objetos LFS ausentes: estas ordenes materializan el arbol.
  Los filtros clean de add/commit/status no descargan objetos. }
function GitMaterializaArbol(const ACmd, AArgs: string): Boolean;
var
  Trozos: TArray<string>;
begin
  Result := MatchText(ACmd, ['clone', 'switch', 'merge', 'pull']);
  if ACmd = 'stash' then
  begin
    Trozos := TrocearArgs(AArgs);
    Result := Length(Trozos) = 0;
    if Length(Trozos) > 0 then
      Result := MatchText(Trozos[0], ['push', 'pop']);
  end
  else if ACmd = 'worktree' then
    Result := SameText(AArgs.Trim, 'add');
end;

function ConfiguracionGitDenegada(const ARepo, ARaiz: string;
  AExaminarLfs: Boolean; var AFijado: string): string;
var
  Salida, RutaLfs, Endpoint: string;
  Codigo: Cardinal;
  HayLfs, HayFuenteLfs: Boolean;
  NombresLfs: TArray<string>;

  function NombreDelEndpoint(const ALinea: string): string;
  var
    P: Integer;
  begin
    if ALinea.StartsWith('Endpoint (') then
    begin
      P := Pos(')', ALinea);
      if P > 11 then Exit(Copy(ALinea, 11, P - 11));
    end;
    if Length(NombresLfs) = 1 then Exit(NombresLfs[0]);
    Result := '(default: git-lfs)';
  end;

  function EndpointLfsDenegado(const ADireccion, ARemoto: string): string;
  var
    Carpeta, Base: string;
    NoEsta: Boolean;
  begin
    Base := ARaiz;
    if Base = '' then Base := ARepo;
    // El endpoint LFS se juzga con EL MISMO juez que un remoto: la red por
    // los hosts de GitRemotes, la carpeta por la puerta de carpetas del
    // workspace. Su valor nunca se muestra: la negativa nombra el remoto.
    if DireccionDeRemotoDenegada('lfs', ADireccion, Base, Carpeta, NoEsta) <> '' then
      Result := MsgFmt(SR_GIT_LFS_ENDPOINT_FMT, [ARemoto])
    else
      Result := '';
  end;

  function RevisaConfiguracion(const ATexto: string; ASoloLocal: Boolean): string;
  var
    Registro, Clave, Valor: string;
    Registros: TArray<string>;
    P: Integer;
  begin
    Result := '';
    Registros := ATexto.Split([#0], TStringSplitOptions.ExcludeEmpty);
    if Odd(Length(Registros)) then
      Exit(MsgText(SR_GIT_CONFIG_NO_VERIFICABLE));
    for var I := 0 to Length(Registros) div 2 - 1 do
    begin
      if IndexStr(Registros[I * 2],
        ['system', 'global', 'local', 'worktree', 'command']) < 0 then
        Exit(MsgText(SR_GIT_CONFIG_NO_VERIFICABLE));
      if not ASoloLocal or
         (IndexStr(Registros[I * 2], ['local', 'worktree']) >= 0) then
      begin
        Registro := Registros[I * 2 + 1];
        P := Pos(#10, Registro);
        // Una clave sin valor es un booleano true valido en la sintaxis de git.
        if P = 0 then
        begin
          Clave := LowerCase(Registro);
          Valor := 'true';
        end
        else
        begin
          Clave := LowerCase(Copy(Registro, 1, P - 1));
          Valor := Copy(Registro, P + 1, MaxInt);
        end;
        // El valor no sale en el rechazo: podria llevar credenciales.
        // LISTA BLANCA: claves conocidas sin programas ni rutas de lectura.
        // No se permiten familias enteras: gc.*, diff.* o remote.* crecen.
        var Permitida := MatchText(Clave, [
          'core.repositoryformatversion', 'core.filemode', 'core.bare',
          'core.logallrefupdates', 'core.symlinks', 'core.ignorecase',
          'core.autocrlf', 'core.eol', 'core.safecrlf', 'core.precomposeunicode',
          'core.protectntfs', 'core.protecthfs', 'core.worktree',
          'user.name', 'user.email', 'user.signingkey',
          'commit.gpgsign', 'tag.gpgsign', 'extensions.worktreeconfig',
          'extensions.objectformat', 'fetch.recursesubmodules',
          'push.recursesubmodules', 'submodule.recurse', 'push.default']);
        var Partes := Clave.Split(['.']);
        if Length(Partes) >= 3 then
        begin
          var Familia := Partes[0];
          var Campo := Partes[High(Partes)];
          if Familia = 'remote' then
            Permitida := MatchText(Campo, ['url', 'pushurl', 'fetch', 'push',
              'mirror', 'tagopt', 'prune', 'prunetags'])
          else if Familia = 'branch' then
            Permitida := MatchText(Campo, ['remote', 'pushremote', 'merge', 'description'])
          else if Familia = 'submodule' then
            Permitida := MatchText(Campo, ['url', 'path', 'active', 'ignore',
              'branch', 'fetchrecursesubmodules']);
        end;
        // LFS es el UNICO programa local admitido, con su comando estandar EXACTO.
        if Clave = 'filter.lfs.clean' then
          Permitida := Valor = 'git-lfs clean -- %f'
        else if Clave = 'filter.lfs.smudge' then
          Permitida := Valor = 'git-lfs smudge -- %f'
        else if Clave = 'filter.lfs.process' then
          Permitida := Valor = 'git-lfs filter-process'
        else if Clave = 'filter.lfs.required' then
          Permitida := SameText(Valor, 'true');
        // El endpoint pasa por EL juez de direcciones de los remotos.
        if MatchText(Clave, ['lfs.url', 'lfs.pushurl']) or
           ((Length(Partes) >= 3) and (Partes[0] = 'remote') and
            MatchText(Partes[High(Partes)], ['lfsurl', 'lfspushurl'])) then
        begin
          Permitida := True;
          if AExaminarLfs then
          begin
            var Remoto := NombreDelEndpoint('');
            if Partes[0] = 'remote' then
              Remoto := Copy(Clave, 8, Length(Clave) - 8 - Length(Partes[High(Partes)]));
            Result := EndpointLfsDenegado(Valor, Remoto);
            if Result <> '' then Exit;
          end;
        end
        else if Clave = 'lfs.repositoryformatversion' then
          Permitida := Valor = '0';
        if not Permitida then
          Exit(MsgFmt(SR_GIT_CONFIG_PROGRAMA_FMT, [Clave]));
      end;
    end;
  end;

  function RevisaFuenteLfs(const AArgumento: string): string;
  begin
    Salida := GitCorre(ARepo, AFijado,
      'config --no-includes --null --list --show-scope ' + AArgumento, 60000, Codigo);
    if Codigo <> 0 then
      Exit(MsgText(SR_GIT_CONFIG_NO_VERIFICABLE));
    Result := RevisaConfiguracion(Salida, False);
  end;

begin
  Result := '';
  Salida := GitCorre(ARepo, AFijado,
    'config --no-includes --null --list --show-scope', 60000, Codigo);
  if Codigo <> 0 then
    Exit(MsgText(SR_GIT_CONFIG_NO_VERIFICABLE));
  HayLfs := ContainsText(Salida, 'filter.lfs.');
  HayFuenteLfs := False;
  NombresLfs := nil;
  if AExaminarLfs and not RemotosDelRepo(ARepo, AFijado, NombresLfs) then
    Exit(MsgText(SR_GIT_CONFIG_NO_VERIFICABLE));
  Result := RevisaConfiguracion(Salida, True);
  if Result <> '' then Exit;
  if not AExaminarLfs then Exit;
  if ARaiz <> '' then
  begin
    RutaLfs := TPath.Combine(ARaiz, '.lfsconfig');
    if TFile.Exists(RutaLfs) then
    begin
      HayFuenteLfs := True;
      if (ReadPathDenied(RutaLfs) <> '') or EsEnlace(RutaLfs) then
        Exit(MsgFmt(SR_GIT_CONFIG_PROGRAMA_FMT, ['.lfsconfig']));
      Result := RevisaFuenteLfs('--file ' + EnComillas(RutaLfs));
      if Result <> '' then Exit;
    end;
    // Se midio la precedencia: fichero de trabajo, indice y despues HEAD.
    if not HayFuenteLfs then
    begin
      Salida := GitCorre(ARepo, AFijado, 'ls-files --stage -- .lfsconfig', 60000, Codigo);
      if Codigo <> 0 then Exit(MsgText(SR_GIT_CONFIG_NO_VERIFICABLE));
      if Salida.Trim <> '' then
      begin
        HayFuenteLfs := True;
        Result := RevisaFuenteLfs('--blob :.lfsconfig');
        if Result <> '' then Exit;
      end;
    end;
  end;
  // HEAD sirve tambien a un bare y a clone --no-checkout.
  if not HayFuenteLfs then
  begin
    Salida := GitCorre(ARepo, AFijado, 'rev-parse --verify --quiet HEAD', 60000, Codigo);
    if Codigo = 0 then
    begin
      Salida := GitCorre(ARepo, AFijado, 'ls-tree --name-only HEAD -- .lfsconfig', 60000, Codigo);
      if Codigo <> 0 then Exit(MsgText(SR_GIT_CONFIG_NO_VERIFICABLE));
      if Salida.Trim <> '' then
      begin
        Result := RevisaFuenteLfs('--blob HEAD:.lfsconfig');
        if Result <> '' then Exit;
      end;
    end
    else if Codigo <> 1 then
      Exit(MsgText(SR_GIT_CONFIG_NO_VERIFICABLE));
  end;
  if not HayLfs then Exit;
  // El programa estandar interpreta la precedencia; no hacemos otro lector.
  // Su salida (rutas y posibles credenciales) nunca se devuelve al agente.
  Salida := GitCorre(ARepo, AFijado, 'lfs env', 60000, Codigo);
  if Codigo <> 0 then Exit(MsgText(SR_GIT_CONFIG_NO_VERIFICABLE));
  Endpoint := '';
  for var Linea in Salida.Split([#10]) do
    if Linea.StartsWith('Endpoint') then
    begin
      var P := Pos('=', Linea);
      if P = 0 then Exit(MsgText(SR_GIT_CONFIG_NO_VERIFICABLE));
      var Direccion := Copy(Linea, P + 1, MaxInt).Trim;
      P := Pos(' (auth=', Direccion);
      if P > 0 then Direccion := Copy(Direccion, 1, P - 1);
      if Direccion = '' then Continue;
      Result := EndpointLfsDenegado(Direccion, NombreDelEndpoint(Linea));
      if Result <> '' then Exit;
      if Endpoint = '' then Endpoint := Direccion;
    end;
  // Fijarlo evita que un checkout cambie .lfsconfig durante la misma orden.
  // La precedencia de -c lfs.url se midio contra .lfsconfig y remote.*.lfsurl.
  AFijado := AFijado + ' -c ' + EnComillas('lfs.url=' + Endpoint) +
    ' -c ' + EnComillas('lfs.pushurl=' + Endpoint);
end;

{ DONDE VIVE el repo de ARepo (o de una carpeta de dentro), preguntado a git:
  su carpeta de git (AGitDir: la de ESTA copia de trabajo), la comun (AComun:
  la del repo principal, cuando ARepo es un worktree enlazado) y la raiz del
  arbol de trabajo (ARaiz: '' en un repo bare y dentro de la propia .git).
  Con barras de Windows. False si git no lo da: ASalida y ACodigo son
  entonces su respuesta ("not a git repository").

  Es la pregunta de la JAULA de git (la tool no deja trabajar en un repo que
  vive fuera de las raices) y la de quien suelta lo nuestro antes de que git
  reescriba el arbol; worktree add ya preguntaba la raiz.

  git contesta una carpeta por linea y su salida llega mezclada con la de
  errores: cuentan SOLO las lineas que son una carpeta que existe, en su
  orden. Un aviso de git con exit 0 hacia la raiz de varias lineas, y no
  casaba con nada, en silencio. }
function DondeViveElRepo(const ARepo: string; out AGitDir, AComun, ARaiz,
  ASalida: string; out ACodigo: Cardinal): Boolean;
var
  Linea, Ruta: string;
  Carpetas: TArray<string>;
begin
  AGitDir := '';
  AComun := '';
  ARaiz := '';
  ASalida := GitCorre(ARepo, '', 'rev-parse --absolute-git-dir ' +
    '--git-common-dir --show-toplevel', 60000, ACodigo);
  Carpetas := nil;
  for Linea in ASalida.Split([#10]) do
  begin
    Ruta := Linea.Trim.Replace('/', '\');
    if Ruta = '' then
      Continue;
    try
      // la comun llega RELATIVA a ARepo (..\..\.git) fuera de un worktree
      // enlazado (medido, git 2.53)
      Ruta := SinBarraFinal(
        TPath.GetFullPath(TPath.Combine(ARepo, Ruta)));
      // git contesta la ruta REAL: bajo una raiz declarada en una letra de
      // red es su UNC, y la puerta juzga por la forma declarada. Se le da
      // escrita asi (Lsp.Lugares.FormaDeclarada; era GIT-041, 30-sep-2026)
      Ruta := FormaDeclarada(Ruta, ARepo);
      if TDirectory.Exists(Ruta) then
        Carpetas := Carpetas + [Ruta];
    except
      // lo que no es una ruta es un aviso de git
    end;
  end;
  // las tres, o las dos primeras cuando no hay arbol de trabajo (git sale
  // entonces con 128 y las ha dado igual)
  Result := (Length(Carpetas) = 2) or (Length(Carpetas) = 3);
  if not Result then
    Exit;
  AGitDir := Carpetas[0];
  AComun := Carpetas[1];
  if Length(Carpetas) = 3 then
    ARaiz := Carpetas[2];
end;

{ Las opciones que ADMITEN los comandos de red (fetch, pull, push). Una lista
  de lo que vale, no de lo que no: la opcion que no esta aqui no pasa. Las de
  la BAJADA para fetch y pull; pull lleva ademas --ff-only, siempre. }
const
  OPCIONES_DE_BAJADA = '--tags, --no-tags, --prune, --depth=<n>, --unshallow';
  OPCIONES_DE_FETCH = OPCIONES_DE_BAJADA + ', --all';
  OPCIONES_DE_PUSH = '--tags, -u, --set-upstream, --dry-run';

function OpcionDeRed(const ACmd, AOpcion: string): Boolean;
begin
  if ACmd = 'push' then
    Exit(IndexStr(AOpcion, ['--tags', '-u', '--set-upstream', '--dry-run']) >= 0);
  Result := (IndexStr(AOpcion, ['--tags', '--no-tags', '--prune', '--unshallow']) >= 0) or
    TRegEx.IsMatch(AOpcion, '^--depth=\d+$') or
    ((ACmd = 'pull') and (AOpcion = '--ff-only')) or
    ((ACmd = 'fetch') and (AOpcion = '--all'));
end;

{ Los trozos de args que no son opciones, en su orden: el remoto y lo que se
  trae o se envia. Por los trozos que lee la puerta (TrocearArgs). }
function TrozosSinGuion(const AArgs: string): TArray<string>;
var
  Trozo: string;
begin
  Result := nil;
  for Trozo in TrocearArgs(AArgs) do
    if not Trozo.StartsWith('-') then
      Result := Result + [Trozo];
end;

{ UN NOMBRE de rama, de tag o de commit, y nada mas que un nombre. Con
  AConRevision vale tambien la forma relativa (HEAD~3, v1^): para NOMBRAR
  una version que ya esta en el repo. }
function EsNombreDeRef(const ANombre: string; AConRevision: Boolean): Boolean;
begin
  if AConRevision then
    Result := TRegEx.IsMatch(ANombre, '^[A-Za-z0-9][A-Za-z0-9._/~^-]*$')
  else
    Result := TRegEx.IsMatch(ANombre, '^[A-Za-z0-9][A-Za-z0-9._/-]*$');
end;

{ LO QUE push ENVIA: los trozos sin guion de detras del remoto. push ANADE
  al remoto; lo que ya hay alli no se reescribe ni se borra por esta tool
  (David, 29-sep-2026: "nada de destruccion remota"). Una lista de lo que
  vale: cada trozo es un nombre (main, v1.7.7) o dos con dos puntos en medio
  (local:remoto) - a la izquierda una version que ya esta en el repo, a la
  derecha el nombre que tendra alli. True si hay uno que no (AMalo).

  Medido ese dia por la tool, con --force y --delete ya negados por su
  nombre: args="origin +main", con las historias divergidas, reescribia la
  rama del remoto, y args="origin :sobra" la borraba. }
function EnvioQueNoVale(const AArgs: string; out AMalo: string): Boolean;
var
  Trozos: TArray<string>;
  I, P: Integer;
  Vale: Boolean;
begin
  Result := False;
  AMalo := '';
  Trozos := TrozosSinGuion(AArgs);
  // (el primero es el remoto: lo juzga RemotoDenegado)
  for I := 1 to High(Trozos) do
  begin
    P := Trozos[I].IndexOf(':');
    if P >= 0 then
      Vale := EsNombreDeRef(Trozos[I].Substring(0, P), True) and
        EsNombreDeRef(Trozos[I].Substring(P + 1), False)
    else
      Vale := EsNombreDeRef(Trozos[I], False);
    if not Vale then
    begin
      AMalo := Trozos[I];
      Exit(True);
    end;
  end;
end;

{ Lo que git contesta a una pregunta, linea a linea (las que traen algo).
  False si git sale con error o no contesta en su plazo: quien pregunta para
  JUZGAR no toma un fallo por un "no hay" (cuarta revision de la 1.7.7: una
  pregunta que fallaba acababa en "se puede"). Por eso las preguntas se
  hacen de forma que "no hay" salga con 0: el que se queda sin plazo sale
  con 1, que es tambien con lo que git config dice que una clave no esta. }
function GitContesta(const ARepo, AFijado, APregunta: string;
  out ALineas: TArray<string>): Boolean;
var
  Salida, Linea: string;
  Codigo: Cardinal;
begin
  ALineas := nil;
  Salida := GitCorre(ARepo, AFijado, APregunta, 60000, Codigo);
  Result := Codigo = 0;
  if Result then
    for Linea in Salida.Split([#10]) do
      if Linea.Trim <> '' then
        ALineas := ALineas + [Linea.Trim];
end;

{ Una direccion de RED con su esquema. La lista es la de clone. }
function EsUrlDeRed(const ADireccion: string): Boolean;
begin
  Result := ADireccion.StartsWith('https://') or ADireccion.StartsWith('http://') or
    ADireccion.StartsWith('git://') or ADireccion.StartsWith('ssh://');
end;

{ QUE ES la direccion de un remoto. Una lista de lo que vale:
    drRed      una direccion de red: con su esquema (EsUrlDeRed) o en la
               forma corta de ssh, [usuario@]maquina:ruta
    drCarpeta  una carpeta (ACarpeta, tal como viene): su ruta, o
               file:///<unidad>:/<ruta> sin nada codificado, que es la forma
               de file:// que se lee igual aqui que en git
    drOtra     lo demas, que no se admite
  Medido el 29-sep-2026 por la tool (cuarta revision): git DECODIFICA los
  %xx de un file:// y aqui se leian tal cual - "mi%20repo.git" era para el
  juez una carpeta y para git otra -, y un remoto del repo con su direccion
  en file://C:/... (dos barras) pasaba por direccion de red: fetch traia la
  historia de una carpeta de fuera de las raices y push escribia en ella. }
type
  TDireccionDeRemoto = (drRed, drCarpeta, drOtra);

function ClaseDeDireccion(const ADireccion: string; out ACarpeta: string): TDireccionDeRemoto;
begin
  ACarpeta := '';
  if StartsText('file:', ADireccion) then
  begin
    if not TRegEx.IsMatch(ADireccion, '^file:///[A-Za-z]:/[^%]*$') then
      Exit(drOtra);
    ACarpeta := ADireccion.Substring(8);
    Exit(drCarpeta);
  end;
  if EsUrlDeRed(ADireccion) then
    Exit(drRed);
  if ADireccion.Contains('://') then
    Exit(drOtra);
  // la forma corta de ssh ([usuario@]maquina:ruta) la decide EL MISMO lector
  // de host que el resto (GitUrlHost con scp corto): un solo juez, sin regex
  // gemela aqui, y asi no discrepan (C:\ o C:/ no es una maquina).
  if GitUrlHost(ADireccion, True) <> '' then
    Exit(drRed);
  ACarpeta := ADireccion;
  Result := drCarpeta;
end;

{ Los remotos del repo, por su nombre. False si git no lo dice. }
function RemotosDelRepo(const ARepo, AFijado: string; out ANombres: TArray<string>): Boolean;
begin
  Result := GitContesta(ARepo, AFijado, 'remote', ANombres);
end;

{ UNA CARPETA que hace de remoto, juzgada: '' = se puede usar. La puerta de
  lectura para traer, la de escritura para enviar. Pasa la carpeta y pasa EL
  REPO QUE VIVE ALLI, con sus tres carpetas, como el de la llamada
  (DondeViveElRepo): una carpeta de dentro de las raices cuyo .git es un
  puntero - un worktree enlazado - sirve y escribe el repo al que apunta.
  Medido el 29-sep-2026 por la tool (cuarta revision): con un worktree de
  dentro de un repo de fuera por remoto, fetch traia la historia de fuera y
  push escribia una rama alli. }
function CarpetaDeRemotoDenegada(const ACmd, ACarpeta: string;
  out ANoEsta: Boolean): string;

  function Puerta(const ASitio: string): string;
  begin
    if ACmd = 'push' then
      Result := PathDenied(ASitio, True)
    else
      Result := ReadPathDenied(ASitio, True);
    if Result <> '' then
      Result := MsgFmt(SR_GIT_REMOTO_FUERA_FMT, [ACmd, ASitio,
        IfThen(ACmd = 'push', 'write', 'read')]);
  end;

var
  GitDir, Comun, Raiz, Salida, Sitio: string;
  Codigo: Cardinal;
begin
  ANoEsta := False;
  Result := Puerta(ACarpeta);
  if Result <> '' then
    Exit;
  // UNA CARPETA QUE ESTA. git abre mas cosas que una carpeta - el fichero
  // puntero de un worktree enlazado, o una ruta a la que el le pone el
  // sufijo .git -, y lo que abre entonces no es lo que aqui se ha mirado.
  // Medido el 29-sep-2026 por la tool (el revisor de este mismo arreglo):
  // con el remoto en "<worktree>\.git", que es un fichero, fetch traia la
  // historia del repo de fuera y push escribia una rama alli.
  // (de lo que NO esta, solo despues de la puerta: de una ruta de fuera no
  // se dice ni si existe)
  if not TDirectory.Exists(ACarpeta) then
  begin
    ANoEsta := True;
    Exit(MsgFmt(SR_GIT_REMOTO_ILEGIBLE_FMT, [ACmd, ACarpeta]));
  end;
  if not DondeViveElRepo(ACarpeta, GitDir, Comun, Raiz, Salida, Codigo) then
    Exit(GitFallo(Codigo, Salida));
  for Sitio in TArray<string>.Create(GitDir, Comun, Raiz) do
    if Sitio <> '' then
    begin
      Result := Puerta(Sitio);
      if Result <> '' then
        Exit;
    end;
end;

function DireccionDeRemotoDenegada(const ACmd, ADireccion, ABase: string;
  out ACarpeta: string; out ANoEsta: Boolean): string;
begin
  Result := '';
  ACarpeta := '';
  ANoEsta := False;
  case ClaseDeDireccion(ADireccion, ACarpeta) of
    drRed:
      begin
        if GitUrlHost(ADireccion, True) = '' then
          Exit(MsgFmt(SR_GIT_REMOTO_ILEGIBLE_FMT, [ACmd, ADireccion]));
        Result := GitRemoteDenied(EnComillas(ADireccion), True);
      end;
    drCarpeta:
      begin
        try
          ACarpeta := SinBarraFinal(TPath.GetFullPath(
            TPath.Combine(ABase, ACarpeta.Replace('/', '\'))));
        except
          Exit(MsgFmt(SR_GIT_REMOTO_ILEGIBLE_FMT, [ACmd, ADireccion]));
        end;
        Result := CarpetaDeRemotoDenegada(ACmd, ACarpeta, ANoEsta);
      end;
  else
    Result := MsgFmt(SR_GIT_REMOTO_ILEGIBLE_FMT, [ACmd, ADireccion]);
  end;
end;

{ EL REMOTO de una llamada de red, juzgado: '' = se puede usar.

  El remoto es adonde git va a leer (fetch, pull) o a escribir (push). En la
  llamada se da por el NOMBRE que tiene en el repo o por su direccion, y una
  direccion es una de dos cosas (ClaseDeDireccion): de RED, o una CARPETA,
  que pasa por la jaula (CarpetaDeRemotoDenegada). Lo que no es ni lo uno ni
  lo otro se niega.

  Un nombre se cambia por sus direcciones - TODAS las que tenga: git envia a
  cada una - y se juzgan esas. Sin remoto en la llamada, git usa uno de los
  del repo: se juzgan todos. Cada direccion de red pasa por la lista de
  hosts, proceda de la llamada o del repo. Tiene que ser una direccion que
  esa lista entiende: con su esquema, o con usuario.

  Si git no contesta a lo que se le pregunta para juzgar, no se usa.

  Medido el 29-sep-2026 por la tool: con una carpeta de fuera de las raices,
  por su ruta o por su nombre, fetch traia su historia y push escribia ramas
  alli. La lista de hosts solo entiende direcciones de red, y una carpeta no
  la miraba nadie. }
function RemotoDenegado(const ACmd, ARepo, AFijado, ABase, AArgs: string): string;
var
  Trozos, Nombres, Mirar, Lineas: TArray<string>;
  Nombre, Direccion, Carpeta, Pregunta: string;
  EscritaEnLaLlamada, NoEsta: Boolean;
begin
  Result := '';
  Pregunta := 'remote get-url --all ';
  if ACmd = 'push' then
    Pregunta := 'remote get-url --push --all ';
  if not RemotosDelRepo(ARepo, AFijado, Nombres) then
    Exit(MsgFmt(SR_GIT_REMOTO_SIN_RESPUESTA_FMT, [ACmd]));
  // el remoto de la llamada: su primer trozo que no es una opcion
  Trozos := TrozosSinGuion(AArgs);
  EscritaEnLaLlamada := (Length(Trozos) > 0) and (IndexStr(Trozos[0], Nombres) < 0);
  if EscritaEnLaLlamada then
    Mirar := nil
  else if Length(Trozos) > 0 then
    Mirar := [Trozos[0]]
  else
    Mirar := Nombres;
  var Direcciones: TArray<string> := nil;
  if EscritaEnLaLlamada then
    Direcciones := [Trozos[0]];
  for Nombre in Mirar do
  begin
    if not GitContesta(ARepo, AFijado, Pregunta + EnComillas(Nombre), Lineas) or
       (Length(Lineas) = 0) then
      Exit(MsgFmt(SR_GIT_REMOTO_SIN_RESPUESTA_FMT, [ACmd]));
    Direcciones := Direcciones + Lineas;
  end;
  for Direccion in Direcciones do
  begin
    Result := DireccionDeRemotoDenegada(ACmd, Direccion, ABase, Carpeta, NoEsta);
    if NoEsta and EscritaEnLaLlamada then
      Result := MsgFmt(SR_GIT_REMOTO_NO_ESTA_FMT, [Direccion,
        IfThen(Length(Nombres) = 0, '(none)', string.Join(', ', Nombres)),
        Carpeta]);
    if Result <> '' then Exit;
  end;
end;

{ LO QUE push ENVIA CUANDO NO SE LE DICE: sin nombres en la llamada lo
  decide la configuracion del repo, y tambien se juzga. '' = vale. Un repo
  ESPEJO (remote.<n>.mirror) envia a la fuerza y quita del remoto lo que
  aqui ya no esta; un remote.<n>.push dice que enviar, y tiene que ser de
  nombres, como lo que se escribe en la llamada. Medido el 29-sep-2026 por
  la tool (cuarta revision): desde un repo espejo, push a secas borro del
  remoto una rama. }
function EnvioConfiguradoDenegado(const ARepo, AFijado, AArgs: string): string;
var
  Trozos, Nombres, Lineas, Todas: TArray<string>;
  Nombre, Linea, Malo, Clave: string;
begin
  Result := '';
  Trozos := TrozosSinGuion(AArgs);
  if Length(Trozos) > 1 then
    Exit; // con nombres en la llamada mandan ellos (EnvioQueNoVale)
  if not RemotosDelRepo(ARepo, AFijado, Nombres) then
    Exit(MsgFmt(SR_GIT_REMOTO_SIN_RESPUESTA_FMT, ['push']));
  if Length(Trozos) = 1 then
  begin
    if IndexStr(Trozos[0], Nombres) < 0 then
      Exit; // una direccion: no tiene configuracion en el repo
    Nombres := [Trozos[0]];
  end;
  // La configuracion ENTERA, de una vez: sale con 0 haya lo que haya, y de
  // sus lineas cuentan las de cada remoto (un aviso de git mezclado en la
  // salida no empieza por el nombre de una clave).
  if not GitContesta(ARepo, AFijado, 'config --list', Todas) then
    Exit(MsgFmt(SR_GIT_REMOTO_SIN_RESPUESTA_FMT, ['push']));
  for Nombre in Nombres do
  begin
    // espejo: lo dice git, que sabe leer sus si y sus no (true, yes, on, 1)
    if not GitContesta(ARepo, AFijado, 'config --type=bool --default false --get ' +
         EnComillas('remote.' + Nombre + '.mirror'), Lineas) then
      Exit(MsgFmt(SR_GIT_REMOTO_SIN_RESPUESTA_FMT, ['push']));
    if IndexStr('true', Lineas) >= 0 then
      Exit(MsgFmt(SR_GIT_PUSH_CONFIG_FMT, [Nombre, 'mirror', Nombre]));
    Clave := 'remote.' + Nombre + '.push=';
    for Linea in Todas do
      if Linea.StartsWith(Clave) and
         EnvioQueNoVale('remoto ' + Linea.Substring(Length(Clave)), Malo) then
        Exit(MsgFmt(SR_GIT_PUSH_CONFIG_FMT, [Nombre,
          'push = ' + Linea.Substring(Length(Clave)), Nombre]));
  end;
end;

const
  TOPE_SALIDA_GIT = 30000; // caracteres de una pagina de la respuesta de git

{ Las lineas de AOutput desde la ADesde (0-based) que caben en una pagina, y
  si queda algo, la nota que dice cuales son y como pedir el resto. Corta
  siempre en un salto; una linea mas larga que la pagina, sola, se corta y
  se dice (GIT-055): la siguiente pagina empieza en la otra, y su cola se
  perdia sin aviso (revision de la 1.13.0) }
function PaginaDeSalidaGit(const AOutput: string; ADesde: Integer): string;
var
  Lineas: TArray<string>;
  Sb: TStringBuilder;
  K: Integer;
  Cortadas: string;
begin
  if (ADesde <= 0) and (Length(AOutput) <= TOPE_SALIDA_GIT) then
    Exit(AOutput);
  Lineas := AOutput.Split([#10]);
  if (Length(Lineas) > 0) and (Lineas[High(Lineas)] = '') then
    SetLength(Lineas, Length(Lineas) - 1); // el salto del final no es una linea
  if ADesde >= Length(Lineas) then
    Exit(MsgFmt(SN_GIT_OFFSET_FUERA_FMT, [ADesde, Length(Lineas)]));
  Cortadas := '';
  Sb := TStringBuilder.Create;
  try
    K := ADesde;
    while (K < Length(Lineas)) and
          ((K = ADesde) or (Sb.Length + Length(Lineas[K]) + 1 <= TOPE_SALIDA_GIT)) do
    begin
      Sb.Append(Copy(Lineas[K], 1, TOPE_SALIDA_GIT)).Append(#10);
      if Length(Lineas[K]) > TOPE_SALIDA_GIT then
        Cortadas := Cortadas + IfThen(Cortadas <> '', ', ') + IntToStr(K + 1);
      Inc(K);
    end;
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
  if Cortadas <> '' then
    Result := Result + MsgFmt(SN_GIT_LINEA_CORTADA_FMT, [Cortadas, TOPE_SALIDA_GIT]) + #10;
  if K < Length(Lineas) then
    Result := Result + MsgFmt(SN_GIT_PAGINA_FMT, [ADesde + 1, K, Length(Lineas), K]);
end;

function TDelphiGitTool.ExecuteWithParams(const Params: TDelphiGitParams): string;
var
  Cmd, GitArgs, Repo, Output, MsgFile: string;
  ExitCode: Cardinal;
  Destino, Enlace: string; // worktree
  GitDir, Comun, Raiz: string; // donde vive el repo (DondeViveElRepo)
  Fijado: string; // --git-dir y --work-tree: git trabaja donde la puerta miro
  SeQuitan: TArray<string>; // las carpetas que git puede quitar: lo nuestro, fuera
  Sitio: string;
begin
  MsgFile := '';
  SeQuitan := nil;
  GitDir := '';
  Comun := '';
  Raiz := '';
  Fijado := '';
  Repo := Params.Repo;
  if Repo = '' then
    Exit(MsgText(SR_GIT_MISSING_REPO));
  // En un proyecto de REFERENCIA (ReadOnlyRoots) vale la mitad de CONSULTA
  // de git - la misma clasificacion que la credencial de solo lectura, en
  // UNA funcion (Lsp.Args.GitCommandIsQuery). Lo demas pasa por la puerta
  // de escritura y sale con el motivo de referencia.
  if (ReadOnlyRootOf(Repo) <> '') and
     GitCommandIsQuery(Params.Command, Params.Args, Params.Message) then
    Result := ReadPathDenied(Repo, True)
  // el destino de un clone es un sitio donde se ESCRIBE: la puerta de
  // escritura (jaula + carpetas muertas), como su gemela worktree add. Se
  // clonaba dentro de __delphi-temp, __delphi-patch o __history (septima)
  else if SameText(Params.Command.Trim, 'clone') then
    Result := WriteTargetDenied(Repo)
  else
    Result := PathDenied(Repo, True);
  if Result <> '' then
    Exit;
  if TFile.Exists(Repo) then
    Repo := TPath.GetDirectoryName(Repo);
  // clone is the one command whose target directory may not exist yet: it
  // is created (inside the jail, already checked above) right before git
  // runs, and a failed clone removes it only if THIS clone created it. Se
  // creaba aqui arriba: un rechazo de la URL la dejaba, y la limpieza de
  // abajo borraba una carpeta vacia que ya estaba (la raiz vacia de otro
  // workspace; sexta revision).
  var CreadaPorElClone := False;
  var AncestroDelClone := ''; // lo que el clone cree debajo es suyo
  if not SameText(Params.Command.Trim, 'clone') and not TDirectory.Exists(Repo) then
    Exit(MsgFmt(SR_GIT_DIR_NOT_FOUND_FMT, [Repo]));

  // UNA lista de metacaracteres (Lsp.Args.ShellArgDenied): la tool tenia
  // su copia (novena revision)
  if ShellArgDenied(Params.Args) <> '' then
    Exit(MsgText(SR_GIT_SHELL_METACHARS_ARGS));
  // The message never goes through a shell (git is spawned with a direct
  // command line): normal punctuation is welcome. Line breaks are refused
  // ONLY for the commands that embed the message in the command line -
  // commit and tag write it to a file and pass -F, so there a multi-line
  // message is exactly what you want: subject, blank line, body with the
  // WHY. Refusing it left every agent-made history as one-line subjects
  // (field report 2026-08-25).
  if (Params.Message.Contains(#13) or Params.Message.Contains(#10)) and
     not MatchText(Params.Command.Trim, ['commit', 'tag']) then
    Exit(MsgText(SR_GIT_MESSAGE_LINES));
  // Dangerous git options (--output, --no-index, -c, ...) are filtered at the
  // single gate (Lsp.Guard.ToolCallDenied), before this handler runs.

  Cmd := Params.Command.Trim.ToLower;
  // lo que no va con el comando se dice (Lsp.Guard.ParametroQueNoVa): commit
  // con path hacia un commit de TODO el indice (octava revision). Solo los
  // parametros de UN comando; args es de todos y lo mira el filtro
  // stash y worktree tienen SUBcomando (el primer trozo de args): la tabla
  // era por comando, y stash list admitia message, worktree list path y
  // worktree remove ref (novena revision)
  var ModoGit := Cmd;
  if Cmd = 'stash' then
  begin
    var TrozosSub := TrocearArgs(Params.Args);
    // (sin IfThen: evalua las dos ramas y TrozosSub[0] sin trozos era un AV)
    ModoGit := 'stash push';
    if Length(TrozosSub) > 0 then
      ModoGit := 'stash ' + LowerCase(TrozosSub[0]);
  end
  else if Cmd = 'worktree' then
    ModoGit := 'worktree ' + Params.Args.Trim.ToLower;
  var SuyosGit: string;
  var SobraGit := ParametroQueNoVa(ModoGit, [
      'status', 'offset', 'diff', 'offset', 'log', 'offset', 'show', 'offset',
      'branch', 'offset', 'add', '',
      'pull', '', 'fetch', '', 'ls-remote', 'offset', 'init', '', 'merge', '', 'push', '',
      'commit', 'message', 'clone', 'message', 'config', 'message',
      'stash push', 'message', 'stash pop', '', 'stash list', 'offset',
      'tag', 'message offset', 'switch', 'create', 'restore', '',
      'worktree add', 'path ref', 'worktree list', 'offset', 'worktree remove', 'path'],
    ['message', Params.Message, '', 'path', Params.Path, '', 'ref', Params.Ref, '',
     'create', IfThen(Params.Create, 'true'), '',
     'offset', IfThen(Params.Offset <> 0, IntToStr(Params.Offset)), ''], SuyosGit);
  if SobraGit <> '' then
  begin
    // como viaja en el cable: command=stash args=pop, no "command=stash pop"
    // (un agente lo repetia literal y caia en GIT-034; r11b H5)
    var Muestra := Cmd;
    if ModoGit <> Cmd then
      Muestra := Cmd + ' args=' + Copy(ModoGit, Length(Cmd) + 2, MaxInt);
    Exit(MsgFmt(SR_GIT_NO_VA_CON_COMANDO_FMT, [SobraGit, Muestra, Muestra, ONinguno(SuyosGit)]));
  end;
  // offset, solo con una CONSULTA: branch y tag listan sin argumentos (su
  // nota GIT-053 lo ofrece) y escriben con ellos
  if (Params.Offset <> 0) and not GitCommandIsQuery(Cmd, Params.Args, Params.Message) then
    Exit(MsgFmt(SR_GIT_OFFSET_SOLO_CONSULTA_FMT, [Cmd]));
  // Un comando que no es de la lista se dice ANTES de preguntar nada a git
  // (la lista de abajo acaba en el mismo texto: esta es la que manda, y un
  // comando nuevo que no se apunte aqui no funciona - cerrado).
  if not MatchText(Cmd, ['status', 'diff', 'log', 'show', 'branch', 'add',
       'commit', 'clone', 'pull', 'fetch', 'init', 'config', 'switch', 'merge',
       'stash', 'restore', 'push', 'tag', 'worktree', 'ls-remote']) then
    Exit(MsgFmt(SR_GIT_UNKNOWN_COMMAND_FMT, [Params.Command]));

  // LA JAULA DEL REPO. git no trabaja sobre la carpeta que se le da: sube
  // desde ella hasta dar con el repo, y lee y reescribe ESE arbol entero. La
  // puerta de arriba miraba solo la carpeta: con la raiz del repo por encima
  // de las raices de la sesion, status y diff ensenaban lo de fuera, y
  // stash, switch y commit lo reescribian (medido el 29-sep-2026: una sesion
  // con mono\a por unica raiz reescribio mono\b y escribio en mono\.git).
  // Las TRES carpetas del repo pasan por la misma puerta que paso la suya -
  // la raiz del arbol, su carpeta de git y la comun (la del repo principal
  // de un worktree enlazado) -, y git corre FIJADO a ellas: trabaja donde
  // la puerta miro, no donde el encuentre un repo al volver a buscar. clone
  // hace su repo. init tambien REINICIALIZA el .git que ya exista: su
  // fichero gitdir puede apuntar fuera, y pasa por la misma puerta.
  if (Cmd <> 'clone') and ((Cmd <> 'init') or
     TFile.Exists(TPath.Combine(Repo, '.git')) or
     TDirectory.Exists(TPath.Combine(Repo, '.git'))) then
  begin
    if not DondeViveElRepo(Repo, GitDir, Comun, Raiz, Output, ExitCode) then
      Exit(GitFallo(ExitCode, Output));
    for Sitio in TArray<string>.Create(Raiz, GitDir, Comun) do
      if Sitio <> '' then
      begin
        if (ReadOnlyRootOf(Sitio) <> '') and
           GitCommandIsQuery(Params.Command, Params.Args, Params.Message) then
          Result := ReadPathDenied(Sitio, True)
        else
          Result := PathDenied(Sitio, True);
        if Result <> '' then
          Exit(MsgFmt(SR_GIT_REPO_FUERA_FMT, [Params.Repo, Sitio]));
      end;
    // por el compositor de la casa (EnComillas), como todo argumento
    Fijado := ' --git-dir=' + EnComillas(GitDir);
    if Raiz <> '' then
      Fijado := Fijado + ' --work-tree=' + EnComillas(Raiz)
    else
      // SIN arbol de trabajo (un repo bare, o "repo" apuntando a la propia
      // .git): --bare. Con --git-dir solo, git toma el directorio actual por
      // arbol de trabajo: status ensenaba el contenido de .git como si
      // fueran los fuentes y switch escribia los ficheros de la rama DENTRO
      // de .git (medido con git a pelo el 29-sep-2026, tercera revision).
      // Con --bare contesta lo que contesta sin fijar: log y branch van, y
      // lo que necesita un arbol dice que no lo tiene.
      Fijado := Fijado + ' --bare';
    // EL REMOTO antes que su endpoint LFS: un pull desde una carpeta de
    // fuera se niega por el remoto (GIT-044), no por el endpoint que de el
    // deriva. La puerta del remoto va delante de la de la configuracion.
    if MatchText(Cmd, ['pull', 'fetch', 'push', 'ls-remote']) then
    begin
      Result := RemotoDenegado(Cmd, Repo, Fijado, IfThen(Raiz <> '', Raiz, Repo),
        Params.Args);
      if (Result = '') and (Cmd = 'push') then
        Result := EnvioConfiguradoDenegado(Repo, Fijado, Params.Args);
      if Result <> '' then
        Exit;
    end;
    Result := ConfiguracionGitDenegada(Repo, Raiz, GitMaterializaArbol(Cmd, Params.Args), Fijado);
    if Result <> '' then
      Exit;
  end;
  if Cmd = 'status' then
    GitArgs := 'status --porcelain=v1 -b ' + ArgvSeguro(Params.Args)
  else if Cmd = 'diff' then
    GitArgs := 'diff ' + ArgvSeguro(Params.Args)
  else if Cmd = 'ls-remote' then
  begin
    for var Trozo in TrocearArgs(Params.Args) do
      if Trozo.StartsWith('-') and
         (IndexStr(Trozo, ['--heads', '--tags', '--refs', '--symref', '--exit-code']) < 0) then
        Exit(MsgFmt(SR_GIT_RED_OPCION_FMT, [Cmd, Trozo,
          '--heads, --tags, --refs, --symref, --exit-code']));
    GitArgs := 'ls-remote ' + ArgvSeguro(Params.Args);
  end
  else if Cmd = 'log' then
  begin
    GitArgs := 'log --oneline -20 ' + ArgvSeguro(Params.Args);
  end
  else if Cmd = 'show' then
    GitArgs := 'show --stat --format=medium ' + ArgvSeguro(Params.Args)
  else if Cmd = 'branch' then
    GitArgs := 'branch -vv ' + ArgvSeguro(Params.Args)
  else if Cmd = 'add' then
  begin
    if Params.Args.Trim = '' then
      Exit(MsgText(SR_GIT_ADD_NEEDS_ARGS_PATHS));
    GitArgs := 'add ' + ArgvSeguro(Params.Args);
  end
  else if Cmd = 'commit' then
  begin
    if MensajeEnArgsGit(Params.Args) then
      Exit(MsgText(SR_GIT_MENSAJE_EN_ARGS));
    if Params.Message.Trim = '' then
      Exit(MsgText(SR_GIT_COMMIT_NEEDS_MESSAGE));
    // -F <file>: the message reaches git byte-exact. Embedding it in the
    // command line mangled double quotes (measured in the field: " -> '').
    // Temporal DEL SERVIDOR, y de los que importan: lleva el mensaje que
    // escribe quien llama. Vivia en el %TEMP% de la MAQUINA, fuera de toda
    // jaula; se borra siempre (mas abajo), pero mientras existe no tiene por
    // que estar donde lo vea cualquiera. Por el nombrador (Lsp.Casa).
    CrearCarpeta(ServerTempDir('git'));
    MsgFile := NombreDeMensajeGit;
    // por la puerta de escribir, con el temporal como lugar: UTF-8 sin BOM
    EscribeTexto(MsgFile, Params.Message, ltTemporal, ekUtf8);
    GitArgs := Format('commit -F "%s" %s', [MsgFile, ArgvSeguro(Params.Args)]);
  end
  else if Cmd = 'clone' then
  begin
    // The URL travels in "message" (args screens metacharacters, and a URL
    // legitimately carries ':' '/' '@'). Destination = repo (jailed).
    var Url := Params.Message.Trim;
    if Url = '' then
      Exit(MsgText(SR_GIT_CLONE_NEEDS_REPOSITORY_URL));
    if not EsUrlDeRed(Url) then
      Exit(MsgText(SR_GIT_CLONE_URLS_ACCEPTED));
    if ShellArgDenied(Url) <> '' then
      Exit(MsgText(SR_GIT_SHELL_METACHARS_URL));
    if Url.Contains('--upload-pack') or Url.Contains('--config') or
       Url.StartsWith('-') then
      Exit(MsgText(SR_GIT_URL_NOT_ALLOWED));
    if TDirectory.Exists(TPath.Combine(Repo, '.git')) then
      Exit(MsgFmt(SR_GIT_YA_ES_REPOSITORIO_FMT, [Repo]));
    // El destino se crea AQUI, pasadas todas las negativas: un rechazo no
    // deja nada, y si el clone falla se quita solo si lo creo el.
    if not TDirectory.Exists(Repo) then
    begin
      AncestroDelClone := PrimerAncestroQueExiste(Repo);
      CrearCarpeta(Repo);
      CreadaPorElClone := True;
    end;
    // clone into "." of the (jailed, existing) destination directory. The "--"
    // separator guarantees the URL is a POSITIONAL, never parsed as an option,
    // whatever it contains - defence in depth over the leading-"-" check above
    // (field round 9: git network args travel fairly verbatim). User args go
    // BEFORE "--" so legitimate options (--depth, --branch) still apply; they
    // were already vetted for dangerous flags at the single gate (GitArgDenied).
    // Primero los objetos: ningun filtro ve un endpoint aun sin juzgar.
    GitArgs := Format('clone --no-checkout %s -- %s .', [ArgvSeguro(Params.Args), EnComillas(Url)]);
  end
  else if Cmd = 'pull' then
  begin
    // SIEMPRE --ff-only, como merge: pull es bajar e integrar, y lo segundo
    // lo hacia como git quisiera. Con las historias divergidas y sin ninguna
    // opcion dejaba un commit de mezcla; con --rebase reescribia la
    // historia, y con --squash dejaba el arbol a medias (medido el
    // 29-sep-2026). Y la opcion del que llama iba DETRAS y ganaba: de las
    // opciones, solo las de la bajada (por los trozos que lee la puerta).
    for var Trozo in TrocearArgs(Params.Args) do
      if Trozo.StartsWith('-') and not OpcionDeRed(Cmd, Trozo) then
        Exit(MsgFmt(SR_GIT_PULL_ARGS_FMT, [Trozo]));
    GitArgs := 'pull --ff-only ' + ArgvSeguro(Params.Args);
    SeQuitan := [Raiz]; // reescribe el arbol: puede quitar carpetas
  end
  else if Cmd = 'fetch' then
  begin
    for var Trozo in TrocearArgs(Params.Args) do
      if Trozo.StartsWith('-') and not OpcionDeRed(Cmd, Trozo) then
        Exit(MsgFmt(SR_GIT_RED_OPCION_FMT, [Cmd, Trozo, OPCIONES_DE_FETCH]));
    GitArgs := 'fetch ' + ArgvSeguro(Params.Args);
  end
  else if Cmd = 'init' then
    GitArgs := 'init ' + ArgvSeguro(Params.Args)
  else if Cmd = 'config' then
  begin
    // Only the commit identity, so a remote agent can commit on a fresh
    // repo/machine. Anything else in git config stays off-limits.
    if not (SameText(Params.Args.Trim, 'user.name') or
            SameText(Params.Args.Trim, 'user.email')) then
      Exit(MsgText(SR_GIT_CONFIG_ONLY_ACCEPTS_USER));
    if Params.Message.Trim = '' then
      Exit(MsgText(SR_GIT_CONFIG_NEEDS_VALUE));
    GitArgs := 'config ' + Params.Args.Trim.ToLower + ' ' +
      EnComillas(Params.Message);
  end
  else if Cmd = 'switch' then
  begin
    // Changing branch is what a real workflow needs and what was missing:
    // an agent could CREATE a branch and never move to it (review
    // 2026-08-25). Only the branch form: "switch <branch>" or, with
    // create=true, "switch -c <branch>". The file-restoring forms of
    // checkout (checkout -- <path>) are NOT here on purpose - those DISCARD
    // work, and discarding has its own command with its own words.
    if Params.Args.Trim = '' then
      Exit(MsgText(SR_GIT_SWITCH_NEEDS));
    if Params.Create then
      GitArgs := 'switch -c ' + ArgvSeguro(Params.Args) // el arbol se queda como esta
    else
    begin
      GitArgs := 'switch ' + ArgvSeguro(Params.Args);
      SeQuitan := [Raiz]; // la otra rama puede no tener la carpeta de un proyecto
    end;
  end
  else if Cmd = 'merge' then
  begin
    if Params.Args.Trim = '' then
      Exit(MsgText(SR_GIT_MERGE_NEEDS));
    // --ff-only: a merge that would need a commit (and could conflict half
    // way) is refused rather than left half-done. Real conflicts are a
    // human's business, not an agent's guess.
    // ...which only held while the caller could not ADD options: user args
    // landed after --ff-only, so `--no-ff <branch>` won and left the repo in
    // MERGING with conflict markers and no way back through this tool
    // (measured 2026-08-25). A branch name, or --abort. Nothing else.
    SeQuitan := [Raiz]; // lo que entra (o lo que se deshace) puede quitar carpetas
    if SameText(Params.Args.Trim, '--abort') then
      GitArgs := 'merge --abort'
    else if Params.Args.Trim.StartsWith('-') or
            (Params.Args.Trim.Split([' ', #9],
              TStringSplitOptions.ExcludeEmpty)[0] <> Params.Args.Trim) then
      Exit(MsgText(SR_GIT_MERGE_ARGS))
    else
      GitArgs := 'merge --ff-only ' + ArgvSeguro(Params.Args.Trim);
  end
  else if Cmd = 'stash' then
  begin
    // push (default) / pop / list: park work to change branch and get it
    // back. Never "stash drop" - that destroys.
    // Y push con RUTAS es como se DESCARTAN los cambios de unos ficheros
    // sin destruirlos: vuelven a HEAD y lo de antes queda en el stash, de
    // donde pop lo devuelve. Faltaba: devolver dos .res a HEAD obligo a
    // salir a la consola (muro, 26-sep-2026).
    var Trozos := TrocearArgs(Params.Args);
    var Sub := 'push';
    if Length(Trozos) > 0 then
      Sub := Trozos[0].ToLower;
    if MatchText(Sub, ['pop', 'list']) and (Length(Trozos) = 1) then
    begin
      GitArgs := 'stash ' + Sub;
      // list solo ENSENA; pop reescribe el arbol con lo aparcado
      if Sub = 'pop' then
        SeQuitan := [Raiz];
    end
    else if Sub = 'push' then
    begin
      GitArgs := 'stash push';
      if Params.Message.Trim <> '' then
        GitArgs := GitArgs + ' -m ' + EnComillas(Params.Message.Trim);
      // las rutas, por el helper de los comandos con rutas (RutasDeGit):
      // cada una pasa por la puerta del escritor (se reescribe el fichero)
      var Rutas: string;
      var Carpetas: TArray<string>;
      Result := RutasDeGit(Repo, Params.Args, Trozos, 1, True, 'stash', Rutas, Carpetas);
      if Result <> '' then
        Exit;
      // Vuelve a HEAD lo que se aparca, y lo que HEAD no tiene se va: con
      // rutas, solo bajo sus carpetas; sin ellas, en todo el arbol.
      SeQuitan := [Raiz];
      if Rutas <> '' then
      begin
        GitArgs := GitArgs + ' --' + Rutas;
        SeQuitan := Carpetas;
      end;
    end
    else
      Exit(MsgFmt(SR_GIT_STASH_ARGS_FMT, [Params.Args.Trim]));
  end
  else if Cmd = 'restore' then
  begin
    // SIEMPRE --staged: deshacer un add. Solo rutas (una o mas; . = todo),
    // sin opciones: --worktree/--source tocarian el arbol, y para descartar
    // cambios esta stash push -- <rutas>. Hermes (28-sep-2026): sin rm ni
    // reset en la lista, tras un add no habia forma de deshacer el staging
    // y borro el .git para volver a empezar. El indice es del repo (la
    // puerta ya paso por Repo): las rutas no vuelven a preguntar.
    var Trozos := TrocearArgs(Params.Args);
    var Rutas: string;
    var Carpetas: TArray<string>; // el indice no quita carpetas: no se usan
    Result := RutasDeGit(Repo, Params.Args, Trozos, 0, False, 'restore', Rutas, Carpetas);
    if Result <> '' then
      Exit;
    if Rutas = '' then
      Exit(MsgFmt(SR_GIT_RESTORE_ARGS_FMT, [Params.Args.Trim]));
    GitArgs := 'restore --staged --' + Rutas;
  end
  else if Cmd = 'push' then
  begin
    // uses the SERVER's stored credentials/remotes - consistent with the
    // centralized model (the repo lives next to the compiler)
    for var Trozo in TrocearArgs(Params.Args) do
      if Trozo.StartsWith('-') and not OpcionDeRed(Cmd, Trozo) then
        Exit(MsgFmt(SR_GIT_RED_OPCION_FMT, [Cmd, Trozo, OPCIONES_DE_PUSH]));
    // ...y lo que se envia, nombres: push anade, no reescribe ni borra
    var Malo: string;
    if EnvioQueNoVale(Params.Args, Malo) then
      Exit(MsgFmt(SR_GIT_PUSH_NOMBRE_FMT, [Malo]));
    GitArgs := 'push ' + ArgvSeguro(Params.Args);
  end
  else if Cmd = 'tag' then
  begin
    if MensajeEnArgsGit(Params.Args) then
      Exit(MsgText(SR_GIT_MENSAJE_EN_ARGS));
    if Params.Message.Trim <> '' then
    begin
      // -F makes it annotated (like -m) and keeps quotes byte-exact;
      // args = tag name (and options)
      CrearCarpeta(ServerTempDir('git'));
      MsgFile := NombreDeMensajeGit;
      EscribeTexto(MsgFile, Params.Message, ltTemporal, ekUtf8);
      GitArgs := Format('tag -F "%s" %s', [MsgFile, ArgvSeguro(Params.Args)]);
    end
    else
      GitArgs := 'tag ' + ArgvSeguro(Params.Args); // no args = list tags
  end
  else if Cmd = 'worktree' then
  begin
    // OTRA version del repo al lado, sin tocar el arbol de nadie: con lo que
    // un agente REMOTO compara con una version anterior sin salirse del MCP
    // (1.4.0; David, 26-sep-2026: 'lo que nos falta para que el agente remoto
    // pueda revisar'). Como clone: la carpeta la elige el agente dentro de sus
    // raices. Sin carpetas temporales ni limpiezas al arrancar (David): la
    // quita quien la pone, y list se la ensena.
    var Sub := Params.Args.Trim.ToLower;
    if Sub = 'list' then
      GitArgs := 'worktree list'
    else if (Sub = 'add') or (Sub = 'remove') then
    begin
      if Params.Path.Trim = '' then
        Exit(MsgText(SR_GIT_WORKTREE_PATH));
      Destino := SinBarraFinal(TPath.GetFullPath(Params.Path.Trim));
      // Crear o quitar una copia de trabajo es ESCRIBIR alli: la pregunta de
      // todo escritor, por la ruta real, y nunca en una carpeta muerta.
      Result := EscrituraDenegada(Destino);
      if Result = '' then
        Result := WriteTargetDenied(Destino);
      if Result <> '' then
        Exit;
      if Sub = 'add' then
      begin
        if TDirectory.Exists(Destino) or TFile.Exists(Destino) then
          Exit(MsgFmt(SR_GIT_WORKTREE_EXISTS_FMT, [Destino]));
        if not EsNombreDeRef(Params.Ref.Trim, True) then
          Exit(MsgText(SR_GIT_WORKTREE_REF));
        // Nunca DENTRO del propio repo: el arbol principal la veria como una
        // carpeta sin seguimiento, y un add -A se la llevaria.
        // Por la ruta REAL de los dos: git da nombres largos y el agente
        // puede pasar la forma 8.3 (medido: C:\Users\DFONTA~1 frente a
        // C:/Users/dfontanet - el texto no casaba y lo dejaba dentro).
        var RaizReal := SinBarraFinal(RealPath(Raiz));
        var DestinoReal := SinBarraFinal(RealPath(Destino));
        if (Raiz <> '') and
           (SameText(DestinoReal, RaizReal) or
            StartsText(IncludeTrailingPathDelimiter(RaizReal), DestinoReal)) then
          Exit(MsgFmt(SR_GIT_WORKTREE_INSIDE_FMT, [Raiz]));
        GitArgs := Format('worktree add --detach "%s" %s', [Destino, Params.Ref.Trim]);
      end
      else
      begin
        // Solo lo que git lista como worktree de ESTE repo, y nunca el
        // principal (el primero): remove no sirve para borrar otra cosa.
        var Lista := GitCorre(Repo, Fijado, 'worktree list --porcelain', 60000, ExitCode);
        var Listado := False;
        var DestinoReal := SinBarraFinal(RealPath(Destino));
        var Primero := True;
        for var Linea in Lista.Split([#10]) do
          if Linea.StartsWith('worktree ') then
          begin
            // por la ruta real, como arriba: git lista nombres largos
            if not Primero and SameText(DestinoReal, SinBarraFinal(
                 RealPath(Linea.Substring(9).Trim.Replace('/', '\')))) then
              Listado := True;
            Primero := False;
          end;
        if not Listado then
          Exit(MsgFmt(SR_GIT_WORKTREE_NOT_LISTED_FMT, [Destino]));
        // git worktree remove ATRAVIESA un enlace de dentro y borra lo que hay
        // detras (medido el 26-sep-2026: un junction en una carpeta ignorada
        // dejo vacia una victima de fuera). Con un enlace dentro no se quita.
        Enlace := '';
        RecorreSinEnlaces(Destino,
          procedure(const APath: string)
          begin
          end,
          procedure(const APath: string)
          begin
            if Enlace = '' then
              Enlace := APath;
          end);
        if Enlace <> '' then
          Exit(MsgFmt(SR_GIT_WORKTREE_LINK_FMT, [Enlace]));
        // Lo NUESTRO, fuera antes de que git la borre: con un DelphiLSP vivo
        // en el worktree (un hover basta) git borraba el contenido, no podia
        // con la carpeta y salia con 255 (medido el 29-sep-2026). Se suelta
        // abajo, junto al git y con el cerrojo de escritura ya cogido.
        SeQuitan := [Destino];
        // Sin --force: con cambios, git se niega y lo dice.
        GitArgs := Format('worktree remove "%s"', [Destino]);
      end;
    end
    else
      Exit(MsgText(SR_GIT_WORKTREE_ARGS));
  end
  else
    Exit(MsgFmt(SR_GIT_UNKNOWN_COMMAND_FMT, [Params.Command]));

  if MatchText(Cmd, ['clone', 'pull', 'fetch', 'push', 'ls-remote']) then
    TLogger.Warning(MsgFmt(SL_GIT_NETWORK_FMT,
      [Cmd, Repo, Params.Message]));

  // Lo que REESCRIBE el arbol en local (switch, merge, stash, reset,
  // restore, worktree...) toma el cerrojo de escritura, como todo escritor:
  // un delphi_edit entre medias se perdia con OK. Las de RED no: clone crea
  // una carpeta nueva, fetch y push no tocan el arbol, y pull -que si lo
  // toca- tarda lo que tarde la red y pararia toda edicion del servidor:
  // es la excepcion, y esta escrita (septima revision). Las consultas no
  // escriben.
  var ConCerrojo := not GitCommandIsQuery(Params.Command, Params.Args, Params.Message) and
    not MatchText(Cmd, ['clone', 'pull', 'fetch', 'push']);
  // Lo que REESCRIBE el arbol puede QUITAR carpetas: una rama sin la carpeta
  // de un proyecto, y git borraba sus ficheros, no podia con la carpeta -el
  // motor de ese proyecto la tiene de directorio de trabajo- y la dejaba
  // vacia, con exit=0 (medido el 29-sep-2026). Los motores de lo que se
  // reescribe se paran antes (SeQuitan: lo apunta cada comando, arriba,
  // donde sabe lo que hace - una consulta como stash list, o switch con
  // create, no paran a nadie); vuelven a arrancar en la siguiente peticion.
  //
  // pull es red Y arbol. Lo de la red se hace ANTES, con un fetch: sin
  // marca, porque dura lo que dure la red y en ese rato nadie podria
  // arrancar un motor en el repo. El pull de despues encuentra lo suyo ya
  // bajado y es casi todo local: ese va con la marca, como los demas. (Se
  // soltaba y se quitaba la marca antes de empezar: el motor que arrancaba
  // durante la red volvia a retener su carpeta.) Solo el pull sin opciones:
  // con ellas (--depth, --tags...) el fetch previo bajaria otra cosa.
  if SameText(Cmd, 'pull') and (Raiz <> '') then
  begin
    // por los trozos que lee la puerta (TrocearArgs), no por el texto
    var ConOpciones := False;
    for var Trozo in TrocearArgs(Params.Args) do
      if Trozo.StartsWith('-') then
        ConOpciones := True;
    if not ConOpciones then
    begin
      var Previo: Cardinal;
      GitCorre(Repo, Fijado, 'fetch ' + ArgvSeguro(Params.Args), 600000, Previo);
      // si falla, el pull lo dira con sus palabras
    end;
  end;
  // (el try de fuera no sangra lo de dentro, como el de RunCore: es solo la
  // regla del clone que no ocurrio, abajo)
  var GitCorrio := False;
  try
  if ConCerrojo then
    EnterFileEdit;
  try
    for Sitio in SeQuitan do
      if Sitio <> '' then
        SueltaLoNuestroBajo(Sitio);
    try
      try
        Output := GitCorre(Repo, Fijado, GitArgs,
          IfThen(MatchText(Cmd, ['push', 'clone', 'pull', 'fetch', 'ls-remote']), 600000, 60000),
          ExitCode);
        GitCorrio := True;
        if (Cmd = 'clone') and (ExitCode = 0) then
        begin
          // El repo ya existe, pero su arbol todavia no se ha materializado.
          if not DondeViveElRepo(Repo, GitDir, Comun, Raiz, Output, ExitCode) then
            Exit(GitFallo(ExitCode, Output));
          Fijado := ' --git-dir=' + EnComillas(GitDir);
          if Raiz <> '' then Fijado := Fijado + ' --work-tree=' + EnComillas(Raiz)
          else Fijado := Fijado + ' --bare';
          Result := ConfiguracionGitDenegada(Repo, Raiz, GitMaterializaArbol(Cmd, Params.Args), Fijado);
          if Result <> '' then
          begin
            ExitCode := 1;
            Exit;
          end;
          // Un bare o --no-checkout no pide arbol. Un clone vacio tampoco.
          if (Raiz <> '') and not MatchText('--no-checkout', TrocearArgs(Params.Args)) and
             not MatchText('-n', TrocearArgs(Params.Args)) then
          begin
            GitCorre(Repo, Fijado, 'rev-parse --verify --quiet HEAD', 60000, ExitCode);
            if ExitCode = 0 then
              Output := GitCorre(Repo, Fijado, 'checkout --force', 600000, ExitCode)
            else if ExitCode = 1 then
            begin
              ExitCode := 0;
              Output := '';
            end;
          end;
        end;
      finally
        if (MsgFile <> '') and TFile.Exists(MsgFile) then
          BorraFichero(MsgFile, ltTemporal); // por la puerta de borrar, con su lugar
      end;
    finally
      for Sitio in SeQuitan do
        if Sitio <> '' then
          YaNoSeQuita(Sitio);
    end;
  finally
    if ConCerrojo then
      LeaveFileEdit;
  end;
  finally
    // A clone that did not happen must not leave its empty destination lying
    // around for the caller to clean up by hand (field round 10).
    // Todas las que creo (n1\n2\n3 dejaba n1\n2), vacias y por la puerta de
    // escritura: la regla de la foto (septima revision). Y el que no llego
    // ni a lanzar git - un servidor sin git, GIT-050 - tampoco ocurrio: se
    // iba por la excepcion y dejaba sus carpetas (medido el 30-sep-2026).
    if (not GitCorrio or (ExitCode <> 0)) and SameText(Cmd, 'clone') and CreadaPorElClone then
      QuitaCarpetasCreadas(Repo, AncestroDelClone);
  end;
  // Una pagina de la respuesta: la de una orden que solo LEE se puede pedir
  // entera, por lineas (offset); se cortaba a 30000 caracteres y no habia
  // forma de ver el resto (muro de la lista del 4-oct-2026). La de una que
  // escribe, no: repetirla con offset la volveria a ejecutar
  if GitCommandIsQuery(Cmd, Params.Args, Params.Message) then
    Output := PaginaDeSalidaGit(Output, Params.Offset)
  else if Length(Output) > TOPE_SALIDA_GIT then
    Output := Copy(Output, 1, TOPE_SALIDA_GIT) + #10 + MsgText(SF_GIT_TRUNCATED);
  // Un git que dice que no (exit<>0) es un fallo: salia como exito y el
  // agente no lo distinguia de uno que funciono (revision 27-sep-2026). Su
  // salida va detras, que es la que explica que paso.
  // diff con --quiet / --exit-code contesta exit=1 cuando HAY diferencias: es
  // su respuesta, no un fallo (tercera revision: salia GIT-036 DENIED). Con
  // --no-index no: un fichero que no esta tambien da 1 (medido).
  var DiffConCambios := SameText(Cmd, 'diff') and (ExitCode = 1) and
    (ContainsText(Params.Args, '--quiet') or ContainsText(Params.Args, '--exit-code')) and
    not ContainsText(Params.Args, '--no-index');
  if DiffConCambios then
    Result := GitExito(MsgText(SN_GIT_DIFF_HAY_CAMBIOS) +
      IfThen(Output.Trim <> '', #10 + Output.Trim, ''), 1)
  else if ExitCode <> 0 then
    Result := GitFallo(ExitCode, Output)
  else
    Result := GitExito(Output.Trim, 0);
  // Una respuesta que es solo "exit=0" no se distingue de una que se ha roto
  // por el camino, y lo primero que hace quien la recibe es repetirla. El
  // silencio de git SIGNIFICA cosas distintas segun la orden, asi que se
  // dice cual (medido 2026-09-20 pidiendo el diff de un arbol limpio).
  if (ExitCode = 0) and (Output.Trim = '') then
  begin
    if SameText(Cmd, 'diff') then
      Result := GitExito(MsgText(SN_GIT_DIFF_CLEAN), 0)
    else if GitCommandIsQuery(Cmd, Params.Args, Params.Message) then
    begin
      // Una consulta vacia dice LO QUE RECIBIO git (sin la -C del repo ni la
      // configuracion de la casa): "log -S<texto>" vacio parecia que el texto
      // se perdia por el camino, y era que el fichero decia otra cosa (Hermes,
      // validacion de la 1.16.0). Solo en las que leen: en las que escriben,
      // callar ya es el exito y el eco repetiria URLs y valores.
      Result := GitExito(MsgFmt(SN_GIT_CONSULTA_VACIA_FMT, [GitArgs.Trim]), 0);
      if SameText(Cmd, 'log') then
        for var Trozo in TrocearArgs(Params.Args) do
          if Trozo.StartsWith('-S') or Trozo.StartsWith('-G') then
          begin
            Result := Result + #10 + MsgText(SN_GIT_PICKAXE_VACIO);
            Break;
          end;
    end
    else
      Result := GitExito(MsgFmt(SN_GIT_SILENT_OK_FMT, [Cmd]), 0);
  end;
  // Un worktree nuevo es de quien lo pidio: se lo dice, con como quitarlo.
  if (ExitCode = 0) and (Cmd = 'worktree') and SameText(Params.Args.Trim, 'add') then
    Result := Result + #10 + MsgFmt(SN_GIT_WORKTREE_ADDED_FMT, [Destino]);
  // git's own hints recommend exactly what this tool refuses (--no-ff,
  // rebase, "specify the URL from the command-line"): say so, or the reader
  // follows the advice printed last (field round 10).
  // Un merge que no puede ir en fast-forward muere con exit 128 y "Not
  // possible to fast-forward": git no sugiere nada y la respuesta era el
  // codigo a pelo (abierto menor del 22-sep). Se dice que significa.
  if (ExitCode <> 0) and MatchText(Cmd, ['merge', 'pull']) and Output.Contains('fast-forward') then
    Result := Result + #10 + MsgText(SN_GIT_MERGE_DIVERGED);
  if (ExitCode <> 0) and not DiffConCambios and (Output.Contains('--no-ff') or Output.Contains('rebase') or
     Output.Contains('specify the URL')) then
    Result := Result + #10 + MsgText(SN_GIT_HINT_OVERRIDE);
  // El CONTENIDO de un diff, de un show o de un log - las lineas de un
  // fichero o de un mensaje de commit, que empiezan por +, - o espacio -
  // viaja como esta en el disco: el barrido de unidades las reescribia
  // (Lsp.Mascara.EnmascaraSalvoContenido). Lo que dice git - cabeceras,
  // avisos, que si pueden nombrar una ruta del servidor - sigue enmascarado.
  if ((ExitCode = 0) or DiffConCambios) and MatchText(Cmd, ['diff', 'show', 'log']) then
    Result := EnmascaraSalvoContenido(Result, '+- ');
end;

{ La respuesta de git que acabo bien: "exit=0" y lo que dijo. El formato que
  leen los agentes y las baterias, compuesto en UN sitio (estaba a mano tres
  veces). La que acabo mal es SR_GIT_EXIT_FMT. }
function GitExito(const ACuerpo: string; AExit: Integer): string;
begin
  Result := 'exit=' + IntToStr(AExit) + #10 + ACuerpo;
end;

{ La que acabo MAL: GIT-036, lo que dijo git y las pistas que salen de lo que
  dijo - lo que el agente SI puede hacer, o de quien es el arreglo cuando no
  es suyo. Las tres salidas que acaban en GIT-036 (la carpeta de un remoto,
  la jaula del repo y la orden misma) pasan por aqui: las pistas iban solo en
  la ultima, y el "dubious ownership" de un NAS sale en la jaula, antes de la
  orden (Hermes, 5-oct-2026). Las pistas que dependen de la orden (merge,
  pull) se quedan con la orden. }
function GitFallo(ACodigo: Cardinal; const ASalida: string): string;
begin
  Result := MsgFmt(SR_GIT_EXIT_FMT, [ACodigo, ASalida.Trim]);
  // A fresh repo has no author identity and commit dies with exit 128:
  // the fix is already whitelisted, say so (measured 2026-08-24).
  if ASalida.Contains('Author identity unknown') then
    Result := Result + #10 + MsgText(SN_GIT_PISTA_CONFIGURA_IDENTIDAD);
  if ASalida.Contains('dubious ownership') then
    Result := Result + #10 + MsgText(SN_GIT_PISTA_PROPIEDAD_DUDOSA);
end;

initialization
  TMCPRegistry.RegisterTool('delphi_git',
    function: IMCPTool begin Result := TDelphiGitTool.Create; end);

end.
