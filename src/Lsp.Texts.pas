unit Lsp.Texts;

{ ALL model-facing text in ONE place: the version string, tool descriptions,
  parameter descriptions, rejections and notices that guide the agent.

  Why centralized: these texts ARE the server's user interface - the model
  only knows what we tell it here. Scattered across units they drift, repeat
  and contradict each other; together they can be reviewed, made consistent
  and tuned without touching any logic.

  Conventions:
  - PURE ASCII, always. Sources are read with the encoding the IDE is
    configured for, and a non-ASCII byte in a literal becomes mojibake in the
    agent's screen when both disagree (measured, field round 2). Write
    "anade", not the accented form.
  - Names: SD_* = tool description, SP_* = parameter description,
    SR_* = rejection/refusal, SN_* = note/warning shown after an action.
  - A rejection says WHAT was refused, WHY, and THE LEGITIMATE WAY to do it.
    An agent that only hears "no" invents a workaround (measured twice in the
    field: build+run and trailing-dot bypasses). }

interface

const
  // ---------------------------------------------------------------------
  // Identity
  // ---------------------------------------------------------------------
  SERVER_NAME = 'delphi-lsp-mcp-service';
  SERVER_VERSION = '0.55.0-beta';

  // ---------------------------------------------------------------------
  // Virtual drive units (the path contract with the client)
  // ---------------------------------------------------------------------
  SN_VIRTUAL_DRIVES =
    'Server paths use VIRTUAL drive units - srvd:, srvc:, ... - which only ' +
    'exist inside this MCP: use them verbatim in every path argument and ' +
    'you will receive them back in results. They are NEVER your own local ' +
    'disks.';

  SN_WORKSPACE_LIBZONE_OFF =
    'La zona de biblioteca esta APAGADA en este servidor ([Security] ' +
    'LibraryZone=0): la lectura se limita a los roots, igual que la ' +
    'escritura. Las fuentes de la RTL y de los componentes NO son legibles ' +
    'desde aqui.';

  SN_WORKSPACE_NOTE =
    'These are paths on the REMOTE server that runs Delphi, not your local ' +
    'machine. Server drive letters travel as VIRTUAL units (srvd:, srvc:, ' +
    '...): use them verbatim in every path argument - they only resolve ' +
    'inside this MCP, never on your disk. Work only inside "roots"; ' +
    'anything outside is refused.';

  // ---------------------------------------------------------------------
  // Listing and build results (a stateless protocol means the agent only
  // knows what each result tells it - so results must leave it ready for
  // the next step, the same way a rejection offers the legitimate path)
  // ---------------------------------------------------------------------
  // No '..' anywhere in this text: results are asserted to carry no
  // traversal residue (R4-C), so even a cosmetic ellipsis is banned here.
  SN_LIST_HIDDEN_FMT =
    '%d entries inside IDE build/artifact folders (Win32, Win64, Debug, ' +
    'Release, dcu, __history) are not listed. They exist on disk: pass ' +
    'that folder itself as root to list its contents, or retrieve build ' +
    'output with delphi_package + delphi_fetch.';

  SN_BUILD_OUTPUT =
    'Retrieve it with delphi_package (zips its folder, dcu excluded) + ' +
    'delphi_fetch (chunked download with sha256).';

  // ---------------------------------------------------------------------
  // Access control
  // ---------------------------------------------------------------------
  SR_READ_ONLY_FMT =
    'RECHAZADO: acceso de SOLO LECTURA. La operacion "%s" ' +
    'modifica la maquina servidora y esta credencial no lo permite. ' +
    'Disponibles en este modo: leer, buscar, listar, navegar simbolos, ' +
    'diagnosticos, referencias, descargar, git de consulta y delphi_report ' +
    '(para contarnos cualquier problema).';

  SR_GIT_OPTION_FMT =
    'RECHAZADO: la opcion de git "%s" no esta permitida (puede escribir ' +
    'ficheros, leer fuera del repositorio o ejecutar un comando).';

  // The gate used to read an argument with an exact, case-SENSITIVE name while
  // the RTTI binder resolves it ignoring case and "_". Two keys that differ
  // only in those made the gate inspect one value and the tool receive the
  // other. Duplicates are never legitimate - no client emits them - so they
  // are refused instead of guessing which one wins.
  SR_ARG_DUPLICATE_FMT =
    'RECHAZADO: has mandado dos veces el parametro "%s" (las mayusculas y ' +
    'los "_" no lo hacen distinto). Manda cada parametro UNA sola vez, con ' +
    'el nombre exacto que da tools/list en "inputSchema".';

  // delphi_build composes a cmd.exe line (rsvars.bat && msbuild ...) and
  // platform/config/target travel through it UNQUOTED: a metacharacter there
  // IS a shell, and it would sail past AllowRun, the jail, the low-integrity
  // sandbox and the .dproj hazard scanner in a single call. delphi_config
  // already armoured the same token for the XML sink; this is its twin mouth.
  SR_BUILD_PLATFORM_FMT =
    'RECHAZADO: "%s" no es una plataforma Delphi valida. Mira las que tiene ' +
    'el proyecto con delphi_config command=view, y usa una de ellas tal cual.';

  SR_BUILD_TARGET_FMT =
    'RECHAZADO: "%s" no es un target valido. Usa Build (completo), Make ' +
    '(incremental), Clean o Deploy (compila y despliega: al PAServer del ' +
    'parametro profile en Linux/macOS, o empaqueta la app en Android). ' +
    'Tras cambiar de plataforma usa Build.';

  SN_BUILD_MANIFEST_NEW =
    'No .deployproj existed, so a MINIMAL deployment manifest was generated ' +
    'next to the project (the project output only, exec bit on). GUI apps ' +
    'need the richer manifest the IDE Deployment Manager writes (shared ' +
    'libraries, assets); this one covers console/simple binaries.';

  SN_BUILD_DEPLOYED_FMT =
    'Deployed through profile "%s". On the target machine the files are ' +
    'under the PAServer scratch directory (default ~/PAServer/scratch-dir' +
    ') in %s-%s/%s/ (PAServer names the folder <windows user>-<profile>) - ' +
    'executables arrive with their exec bit set, ready to run there. ' +
    'That folder is REWRITTEN on every deploy: whatever the app stored next ' +
    'to its binary (a data\ folder, a local database, a key file) is gone ' +
    'with it - copy it elsewhere before redeploying if a test needs it. ' +
    'deployedFiles counts what this run shipped; if it is missing, nothing ' +
    'was sent: check the manifest with delphi_config command=view ' +
    '(deployFiles) and add the missing entries with add-deployfile.';

  SN_BUILD_DEPLOY_EMPTY_ENTRY =
    'The deployment manifest has an entry with an EMPTY local file for this ' +
    'platform (msbuild: Local file "" not found, skipped). Open it with ' +
    'delphi_config command=view (deployFiles) and fix or remove that entry.';

  SN_BUILD_MANIFEST_FILLED_FMT =
    'The project''s .deployproj had NO files for %s (the IDE writes an empty ' +
    'group for a platform it never deployed): the project output was added ' +
    'for Debug and Release, like the IDE''s Deployment Manager would. Extra ' +
    'files (a component''s .so) go in with delphi_config add-deployfile.';

  SR_BUILD_CONFIG_FMT =
    'RECHAZADO: la configuracion "%s" lleva caracteres que el shell del ' +
    'build interpretaria. Una configuracion es un nombre simple (letras, ' +
    'digitos, espacio, ".", "_" y "-"): Debug, Release, o la que declare tu ' +
    'proyecto. Mira las declaradas con delphi_config command=view.';

  // delphi_delete/delphi_move park their target in a trash folder created
  // NEXT TO it. For a ROOT that folder lands in the root's PARENT - a write
  // OUTSIDE the jail - and the whole workspace disappears in one call. The
  // root is the jail, not content.
  SR_ROOT_ITSELF_FMT =
    'RECHAZADO: "%s" es un WORKSPACE ROOT (la jaula misma), no un fichero de ' +
    'trabajo: borrarlo o moverlo se llevaria el proyecto entero y dejaria la ' +
    'copia de seguridad FUERA de la jaula. Borra o mueve lo que hay DENTRO ' +
    '(delphi_list te lo ensena). Cambiar los roots es cosa del operador, en ' +
    'settings.ini [Workspace] Roots.';

  SR_JAIL_FMT =
    'RECHAZADO: "%s" esta FUERA de los workspaces permitidos. Este servidor ' +
    'solo opera dentro de: %s (configurado en DELPHI_MCP_ROOTS o ' +
    'settings.ini [Workspace] Roots).';

  SR_ROOTS_INVALID =
    'RECHAZADO: [Workspace] Roots esta configurado pero ninguna de sus ' +
    'rutas es valida (comillas de mas, unidad inexistente...). Por seguridad ' +
    'se rechaza todo hasta corregir settings.ini / DELPHI_MCP_ROOTS.';

  // An unserved "srvz:" used to be expanded to the REAL "Z:\", so the
  // rejection echoed a drive letter of the host - and the outbound mask only
  // covers served letters, so it came back raw. Probing srva: .. srvz: told
  // the client which drives the machine has (field round 10). Unserved units
  // never touch the filesystem now; this says so without naming anything the
  // client cannot already get from delphi_workspace.
  SR_UNIT_UNKNOWN_FMT =
    'RECHAZADO: "%s" no es una unidad de este servidor. Las unidades ' +
    'validas son: %s. Pide las rutas con delphi_workspace y usalas tal ' +
    'como te las devuelve el servidor.';

  // delphi_run is OFF by design: this is a pure DEVELOPMENT/COMPILE server,
  // it never executes programs. Running a compiled artifact belongs on the
  // CLIENT machine (or a real target device), not here - it would be both
  // pointless (nobody sees the process on the server) and the main way an
  // agent could do damage. Refused for EVERY credential, read-write included.
  // A build must never EXECUTE code on a compile-only server. If the project
  // carries shell-running / file-planting MSBuild tasks, refuse the build
  // (unless build scripts were opted into) - field round 7: upload could plant
  // a .dproj whose <Target><Exec> ran arbitrary commands at build time. An inert
  // custom <Target> (Message/PropertyGroup only) is NOT refused (field round 9).
  SR_BUILD_HAZARD_FMT =
    'RECHAZADO: el proyecto contiene %s. Este servidor solo COMPILA, nunca ' +
    'ejecuta, y esa tarea correria un programa o escribiria ficheros durante ' +
    'el build. Compila un .dproj sin tareas de ejecucion (un <Target> que solo ' +
    'imprime un mensaje o fija una propiedad SI se admite). Si es un proyecto ' +
    'de confianza que firma o copia en post-build, el operador lo habilita con ' +
    '[Security] AllowBuildScripts=1 (sin encender delphi_run).';

  SR_RUN_DISABLED =
    'RECHAZADO: la ejecucion en el servidor esta deshabilitada por diseno. ' +
    'Este es un servidor de compilacion (development): compila, nunca ' +
    'ejecuta. Para PROBAR un binario, descargalo con delphi_package + ' +
    'delphi_fetch y ejecutalo en TU maquina, o despliegalo a un target real ' +
    '(PAServer en Linux/macOS, o Android) - ahi corre en el cliente, no en ' +
    'el servidor. (El operador puede habilitarlo con [Security] AllowRun=1, ' +
    'pero no es el uso previsto.)';

  // ---------------------------------------------------------------------
  // vault_* (knowledge vault: Markdown notes linked with [[wikilinks]])
  // These descriptions ARE the doctrine the agent sees: lazy loading, write
  // in Spanish, log vs progress discipline, read the write-rules before
  // creating. What can be enforced by code lives in Mcp.Tools.Vault.
  // ---------------------------------------------------------------------
  SD_VAULT_SEARCH =
    'Busca en el vault de conocimiento (notas Markdown enlazadas con ' +
    '[[wikilinks]]). PROTOCOLO: al empezar una tarea, llama primero a ' +
    'vault_read SIN path para obtener las reglas y el indice; decide por las ' +
    'descripciones del indice que notas cargar con vault_read - carga ' +
    'perezosa, nunca leas el vault en masa.';

  SD_VAULT_READ =
    'Lee una nota del vault de conocimiento por ruta relativa. SIN path ' +
    'devuelve las reglas (AGENTS-VAULT.md) + el indice (MEMORY.md): hazlo al ' +
    'empezar. Los [[wikilinks]] del contenido refieren a otras notas - ' +
    'localizalas con vault_search target=files.';

  SD_VAULT_APPEND =
    'Anade contenido a una nota existente del vault (entradas de log, ' +
    'avances de progress). Escribe SIEMPRE en espanol. Formato log: entrada ' +
    'fechada bajo la seccion del dia. En progress.md respeta su estructura ' +
    'snapshot: lineas de estado vivas, el historico va en log - no acumules; ' +
    'si cierras un asunto, elimina su linea con vault_patch en lugar de ' +
    'anadir "hecho". El servidor guarda copia del original antes de escribir.';

  SD_VAULT_CREATE =
    'Crea una nota nueva en el vault. ANTES de crear: lee ' +
    'AGENTS-VAULT-WRITE.md (arbol de decision de donde va cada cosa y ' +
    'plantillas) y enlaza la nota desde el indice que corresponda con ' +
    '[[wikilinks]]. Escribe en espanol. No reorganices carpetas ni muevas ' +
    'notas existentes - eso requiere OK humano. Nunca sobreescribe: si la ' +
    'nota existe, se rechaza.';

  SD_VAULT_PATCH =
    'Edicion puntual de una nota: sustituye old_text (UNICO en el fichero) ' +
    'por new_text. Para tachar lineas cerradas de un progress o corregir un ' +
    'dato. Para anadir contenido usa vault_append; para reescrituras grandes, ' +
    'para y consulta al usuario. El servidor guarda copia del original antes ' +
    'de escribir.';

  // Handed to the model in the initialize response when a vault is configured
  // - unless the vault ships its own VAULT-INSTRUCTIONS.md, which wins. Short
  // on purpose: instructions travel in EVERY prompt of every client, so the
  // heavy doctrine stays behind vault_read (no path).
  SN_VAULT_INSTRUCTIONS =
    'Este servidor da acceso a un VAULT DE CONOCIMIENTO: notas Markdown ' +
    'enlazadas con [[wikilinks]] con las convenciones, patrones, decisiones y ' +
    'el estado de cada proyecto. PROTOCOLO al empezar cualquier tarea: ' +
    '(1) llama a vault_read SIN path - devuelve las reglas del vault y el ' +
    'indice de notas; (2) identifica el proyecto sobre el que trabajas y carga ' +
    'su context.md y su progress.md; (3) el resto de notas, solo bajo demanda ' +
    'cuando el indice indique que aplican (carga perezosa - nunca leas el ' +
    'vault en masa). Si el vault permite escritura, lee antes ' +
    'AGENTS-VAULT-WRITE.md y respeta el idioma del vault.';

  SD_VAULT_PROMPT =
    'Carga el arranque del vault de conocimiento: sus reglas y el indice de ' +
    'notas. Uselo al empezar, o para recargar el indice a mitad de una sesion ' +
    'larga.';

  SN_VAULT_PROMPT_HEADER =
    'Estas son las reglas y el indice del vault de conocimiento de este ' +
    'servidor. Trabaja con carga perezosa: carga solo las notas que el indice ' +
    'indique que aplican a tu tarea, con vault_read.';

  SR_VAULT_UNSET =
    'error: este servidor no tiene vault de conocimiento configurado ' +
    '([Vault] Path en settings.ini).';

  // No echo of the offending path on purpose: the outbound filter rewrites
  // server drive letters, so echoing "C:/Windows/win.ini" came back as
  // "srvc:/Windows/win.ini" - something the agent never sent, confusing to
  // debug (field round 8). The rule itself is what the agent needs.
  // The vault is reachable ONLY through the vault_* tools, wherever it lives -
  // including inside a workspace root. Otherwise delphi_edit could rewrite a
  // note behind the vault's back: no automatic backup, and the governance
  // files (rules and index) would stop being protected.
  SR_VAULT_NOT_CODE =
    'RECHAZADO: esa ruta pertenece al VAULT DE CONOCIMIENTO, que no se toca ' +
    'con las tools de codigo. Usa vault_read / vault_search para consultarlo ' +
    '(y vault_append / vault_create / vault_patch si este servidor permite ' +
    'escribir en el): asi queda copia de seguridad y se respetan sus reglas.';

  SR_VAULT_WOULD_EMPTY =
    'RECHAZADO: esa sustitucion dejaria la nota VACIA, y borrar conocimiento ' +
    'no es una operacion de este servidor (no hay delete ni reescritura ' +
    'total por diseno). Si de verdad hay que retirar la nota, diselo al ' +
    'usuario y que lo haga una persona.';

  SR_VAULT_JAIL =
    'RECHAZADO: esa ruta sale del vault. Usa una ruta RELATIVA dentro del ' +
    'vault (projects/x/context.md): sin unidades, sin rutas absolutas y sin ' +
    '"..". Localiza notas con vault_search target=files.';

  SR_VAULT_MORE_FMT =
    #10'--- Mostradas las lineas 1..%d de %d. Pide el resto con ' +
    'vault_read {offset: %d} (y limit si quieres trozos mas pequenos).';

  SN_VAULT_BOOTSTRAP =
    '# Arranque del vault: las reglas (AGENTS-VAULT.md) y el indice ' +
    '(MEMORY.md).'#10 +
    'Carga perezosa: usa el indice para decidir que notas abrir con ' +
    'vault_read; no leas el vault entero.'#10#10;

  // When rules + index do not fit in one result, the split is between FILES:
  // the first arrives whole and the second is asked for by name. Never half a
  // file - and it mirrors how the vault is read locally, one file per read.
  SN_VAULT_BOOTSTRAP_NEXT_FMT =
    #10'--- Falta %s (no cabe junto con lo anterior en una sola respuesta). ' +
    'Pidelo entero con vault_read {path: "%s"}.';

  SR_VAULT_READONLY =
    'RECHAZADO: el vault de conocimiento esta en SOLO LECTURA en este ' +
    'servidor ([Vault] ReadOnly=1). Puedes consultarlo con vault_read y ' +
    'vault_search.';

  SR_VAULT_GOVERNANCE =
    'RECHAZADO: AGENTS-VAULT.md, AGENTS-VAULT-WRITE.md y MEMORY.md son los ' +
    'ficheros de GOBIERNO del vault (sus reglas y su indice) y solo se tocan ' +
    'con supervision humana. Puedes leerlos (vault_read sin path). Si hace ' +
    'falta indexar una nota nueva, dilo en tu respuesta para que lo haga una ' +
    'persona.';


  // ---------------------------------------------------------------------
  // delphi_paserver (connection profiles against a live PAServer)
  // The profile file is written by paclient.exe itself (--local), so the
  // format - password encrypted included - is always the IDE's own, never
  // invented here. --passfile was measured and REJECTED for add-profile:
  // it stores the passfile PATH in the profile, leaving the password in
  // plain text on disk forever; --password stores it encrypted inside.
  // ---------------------------------------------------------------------
  SD_PASERVER =
    'The bridge for building and running on OTHER platforms (Linux, macOS) ' +
    'through the Platform Assistant (PAServer). command=packages lists the ' +
    'PAServer installers that ship with each Delphi install (download them ' +
    'with delphi_fetch and run them on the target machine); ' +
    'command=platforms shows which platforms this server can target; ' +
    'command=profiles lists the registered connection profiles and SDKs; ' +
    'command=add-profile registers a connection profile against a live ' +
    'PAServer (name, host, password; optional port, platform) with the ' +
    'password stored encrypted; command=test-connection with name dials ' +
    'the PAServer of that profile (full handshake, credentials included), ' +
    'and with host+port and NO name it is a raw TCP reachability probe - ' +
    'the quick "does this server reach my PAServer at all?" answer, no ' +
    'credentials involved; command=get-sdk pulls the platform SDK/sysroot ' +
    '(the libraries the linker needs) from the PAServer of profile "name" ' +
    'and registers it, so delphi_build can link for that platform - run it ' +
    'once per target (can take minutes; re-run after OS upgrades on the ' +
    'target). Building for the platform is delphi_build once profile and ' +
    'SDK exist; enabling a platform in a project is delphi_config.';

  SP_PASERVER_COMMAND =
    'platforms (what this server can target + profile/SDK status) | ' +
    'packages (PAServer installers to download and run on the target) | ' +
    'profiles (registered connection profiles and SDKs) | add-profile ' +
    '(register a connection profile: name, host, password; optional port, ' +
    'platform) | test-connection (with name: full handshake against that ' +
    'profile; with host+port and no name: raw TCP reachability probe) | ' +
    'get-sdk (pull the SDK/sysroot from the PAServer of profile "name" and ' +
    'register it for delphi_build; can take minutes) | remote-run (execute ' +
    '"exe" on the target of profile "name" and return its exit code and ' +
    'output - needs the mcp-runner script installed on the target; see the ' +
    'note it returns; it runs the program THAT PROJECT deployed and nothing ' +
    'else on that machine) | install-runner (copy the runner to the target of ' +
    'profile "name" so remote-run can work; it then needs ONE manual launch ' +
    'on the target - the answer gives the exact line). Default: platforms';
  SP_PASERVER_PROJECT =
    'remote-run: the .dproj whose DEPLOYED program you want to run. The ' +
    'server derives the path on the target itself ' +
    '(<user>-<profile>/<Project>/<Project>, what target=Deploy wrote): ' +
    'nothing else of the remote machine can be executed';
  SP_PASERVER_EXE =
    'remote-run OPTIONAL: another file OF THAT SAME deploy folder to run ' +
    'instead of the project binary - a plain file name, no path separators. ' +
    'Default: the project binary';
  SP_PASERVER_ARGS =
    'remote-run: optional command-line arguments for the program (no shell ' +
    'metacharacters)';
  SP_PASERVER_TIMEOUT =
    'remote-run: max milliseconds to wait for the program (default 30000, ' +
    'max 300000)';
  SP_PASERVER_NAME =
    'Profile name (letters, digits, "_", "-"): add-profile creates it, ' +
    'test-connection dials it';
  SP_PASERVER_HOST =
    'Host or IP where the target PAServer listens (add-profile, or ' +
    'test-connection without name for a raw TCP probe)';
  SP_PASERVER_PORT =
    'Port of the target PAServer (add-profile / test-connection). ' +
    'Default: 64211';
  SP_PASERVER_PASSWORD =
    'The PAServer password (add-profile). Used once to create the profile, ' +
    'stored encrypted, never shown back';
  SP_PASERVER_PLATFORM =
    'Platform of the profile: Win32 | Win64 | WinARM64EC | OSX64 | ' +
    'Linux64. Default: Linux64';

  SR_PASERVER_CMD =
    'error: command debe ser platforms | packages | profiles | add-profile ' +
    '| test-connection | get-sdk | install-runner | remote-run';

  SR_REMOTERUN_PROJECT_DENIED_FMT =
    'RECHAZADO: el proyecto "%s" no esta en la lista de proyectos que este ' +
    'servidor permite ejecutar en un target ([Security] RemoteRunProjects). ' +
    'Permitidos: %s.';

  SR_PASERVER_RUN_DISABLED =
    'RECHAZADO: la ejecucion remota esta APAGADA en este servidor. El ' +
    'operador la enciende con [Security] AllowRemoteRun=1 en el settings.ini ' +
    'que hay junto al ejecutable (o la variable DELPHI_MCP_ALLOW_REMOTE_RUN=1) ' +
    'y reinicia el servidor. Son dos cerrojos en serie y a proposito: este, y ' +
    'el runner que alguien tiene que arrancar en la maquina destino. ' +
    'install-runner y el resto de comandos siguen funcionando: copiar el ' +
    'script no ejecuta nada.';

  SR_PASERVER_RUN_NEEDS =
    'RECHAZADO: remote-run necesita "name" (el perfil PAServer) y "project" ' +
    '(el .dproj cuyo programa desplegado quieres ejecutar). El servidor ' +
    'deriva la ruta en el target: <usuario>-<perfil>/<Proyecto>/<Proyecto>. ' +
    'No se ejecuta ninguna otra cosa de la maquina remota. install-runner ' +
    'solo necesita "name".';

  SR_PASERVER_RUN_NOPROJ_FMT =
    'RECHAZADO: no existe el proyecto %s en este servidor. remote-run ' +
    'ejecuta lo que ese .dproj haya desplegado (delphi_build target=Deploy).';

  SR_PASERVER_RUN_EXENAME =
    'RECHAZADO: "exe" es opcional y, si se da, debe ser un NOMBRE de fichero ' +
    'de la carpeta de despliegue de ese proyecto (sin "/", sin "\\" y sin ' +
    '".."). Por defecto se ejecuta el binario del proyecto.';

  SR_REMOTERUN_NO_PACLIENT =
    'error: ninguna instalacion de RAD Studio de este servidor trae ' +
    'bin\paclient.exe: sin el no hay transporte a PAServer.';

  SR_REMOTERUN_NO_SCRIPT =
    'error: no encuentro runner\mcp-runner.py junto al ejecutable del ' +
    'servidor. El operador debe copiar la carpeta "runner" del repositorio ' +
    'al lado del exe y repetir install-runner.';

  SN_REMOTERUN_INSTALLED =
    'RUNNER COPIADO al target, en <scratch-dir>/_mcp-runner/mcp-runner.py. ' +
    'FALTA ARRANCARLO una vez: en la maquina destino, dentro de la scratch ' +
    'dir de PAServer (por defecto ~/PAServer/scratch-dir), ejecuta: ' +
    'nohup python3 _mcp-runner/mcp-runner.py >> _mcp-runner/runner.log 2>&1 &' +
    ' -- El runner crea sus carpetas (jobs, out, done) al arrancar y se ' +
    'queda vigilando; despues, remote-run ya funciona. Ese unico paso ' +
    'necesita una shell en el destino (una persona, o un agente que viva ' +
    'alli): es el opt-in a la ejecucion remota, deliberado.';

  SR_REMOTERUN_PUT_FMT =
    'error: no se pudo enviar el trabajo al target (paclient exit %d): %s. ' +
    'PAServer esta vivo? El perfil apunta al host correcto?';

  SR_REMOTERUN_TIMEOUT_FMT =
    'error: el target no devolvio resultado en %d s. Casi seguro NO tiene el ' +
    'runner instalado: en el target, dentro de la scratch dir de PAServer, ' +
    'debe existir "%s/mcp-runner" ejecutandose (script Python que lee ' +
    'jobs/*.json y escribe out/result-*.json). Sin runner no hay ejecucion ' +
    'remota: instalalo (te lo damos con delphi_fetch) y reintenta.';

  SR_REMOTERUN_NOT_STARTED_FMT =
    'error: el target no devolvio resultado en %d s, pero el runner SI esta ' +
    'copiado alli: falta ARRANCARLO. En la maquina destino, dentro de la ' +
    'scratch dir de PAServer: nohup python3 %s/mcp-runner.py >> ' +
    '%1:s/runner.log 2>&1 & -- Ese arranque necesita una shell en el destino ' +
    '(una persona o un agente que viva alli) y es el opt-in a la ejecucion ' +
    'remota. Si crees que si esta corriendo, mira %1:s/runner.log en el ' +
    'target: ahi se registra cada job.';

  SN_REMOTERUN_NOTE =
    'Ejecutado en el target via PAServer (buzon de ficheros: paclient no ' +
    'tiene exec propio). El runner solo ejecuta binarios dentro de la ' +
    'scratch dir del PAServer - la zona del deploy - nunca el resto de la ' +
    'maquina. exitCode/output vienen del programa; runnerError, si aparece, ' +
    'es un rechazo del runner (ruta fuera de la scratch, binario inexistente).';

  SR_SHELL_META_FMT =
    'RECHAZADO: el argumento contiene "%s", un metacaracter de shell que ' +
    'romperia la linea de comandos. Quitalo.';

  SR_PASERVER_SDK_PLATFORM_FMT =
    'RECHAZADO: get-sdk cubre hoy la plataforma Linux64 y el perfil "%s" es ' +
    'de %s. Para otras plataformas (macOS necesita un Mac real con PAServer) ' +
    'reportalo con delphi_report: es la senal para construirlas.';

  SR_PASERVER_SDK_PULL_FMT =
    'error: fallo el pull del SDK en "%s" (paclient exit %d): %s -- El ' +
    'sysroot puede haber quedado a medias; corrige la causa (PAServer vivo? ' +
    'ruta existente en el target?) y vuelve a lanzar get-sdk: los pulls son ' +
    'reanudables.';

  SN_PASERVER_SDK_OK =
    'SDK provisioned: the target libraries now live on this server and the ' +
    'platform SDK is registered. delphi_build picks it up automatically for ' +
    'this platform. Note: C++ headers are NOT pulled (this server links ' +
    'Delphi); re-run get-sdk after OS/toolchain upgrades on the target.';

  SR_PASERVER_NAME_FMT =
    'RECHAZADO: "%s" no vale como nombre de perfil. Usa letras, digitos, ' +
    '"_" o "-" (max 64): el nombre se convierte en un fichero ' +
    '<nombre>.profile en el servidor.';

  SR_PASERVER_HOST_FMT =
    'RECHAZADO: "%s" no vale como host. Usa un hostname o una IP (letras, ' +
    'digitos, ".", "-" y ":" para IPv6), sin espacios ni comillas.';

  SR_PASERVER_PORT_FMT =
    'RECHAZADO: "%s" no es un puerto valido (1-65535). El PAServer escucha ' +
    'por defecto en el 64211.';

  SR_PASERVER_PLATFORM_FMT =
    'RECHAZADO: "%s" no es una plataforma de paclient. Validas: Win32, ' +
    'Win64, WinARM64EC, OSX64, Linux64.';

  SR_PASERVER_PASSWORD =
    'RECHAZADO: la password lleva comillas dobles o caracteres de control, ' +
    'que romperian la linea de comandos de paclient. Configura en el ' +
    'PAServer una password sin esos caracteres y vuelve a llamar.';

  SR_PASERVER_NO_PACLIENT =
    'error: ninguna instalacion de RAD Studio de este servidor trae ' +
    'bin\paclient.exe, necesario para gestionar perfiles PAServer.';

  SR_PASERVER_NEED_FMT =
    'RECHAZADO: add-profile necesita "%s". Parametros: name (nombre del ' +
    'perfil), host (IP o hostname del PAServer), password (la del ' +
    'PAServer); opcionales port (default 64211) y platform (default ' +
    'Linux64).';

  SR_PASERVER_NO_PROFILE_FMT =
    'RECHAZADO: no existe el perfil "%s". Lista los registrados con ' +
    'command=profiles, o crea uno con command=add-profile (name, host, ' +
    'password; opcionales port y platform). Para saber solo si HAY RUTA ' +
    'hasta tu PAServer, llama a test-connection con host y port SIN name ' +
    '(sondeo TCP, sin credenciales).';

  SN_PASERVER_PROFILE_OK =
    'Profile stored with the password encrypted inside. Verify the link ' +
    'with command=test-connection, then delphi_build with this platform ' +
    'builds against the target PAServer.';

  SN_PASERVER_CONNECTED =
    'PAServer alive and credentials accepted. delphi_build can now target ' +
    'this platform through the profile.';

  SN_PASERVER_TCP_OK =
    'TCP route open: this server reaches that host:port. This only proves ' +
    'the route - the full PAServer handshake with credentials is ' +
    'test-connection with a profile name (add-profile first).';

  SN_PASERVER_TCP_FAIL =
    'No TCP route from this server to that host:port. Check, in order: the ' +
    'PAServer is running and listening there; if the target is a container ' +
    'or behind NAT, the port is published/forwarded on the reachable host ' +
    '(and then use THAT host ip here); firewalls on both sides allow the ' +
    'port.';

  // ---------------------------------------------------------------------
  // delphi_adb (Android devices hanging off THIS server's machine/network)
  // ---------------------------------------------------------------------
  SD_ADB =
    'Android devices for remote development: the phones/tablets hang off ' +
    'THIS server (USB or wifi adb), while you program from anywhere. ' +
    'command=discover finds devices ANNOUNCING wireless debugging on the ' +
    'server''s network (mDNS) and hands you each one''s ip:port - so you ' +
    'never need to know the address up front; command=devices lists what ' +
    'adb has ATTACHED (the same list the IDE shows as deploy targets); ' +
    'command=connect attaches one over the network (address ip:port from ' +
    'discover; the device shows an authorize prompt the first time); ' +
    'command=disconnect detaches it; command=install installs a built .apk ' +
    'on a device (apk path inside the workspace; optional device serial ' +
    'when several are attached). The adb used is the one from the IDE''s ' +
    'own Android SDK, discovered per install. Building the .apk is ' +
    'delphi_build target=Deploy (the deployment manifest is generated ' +
    'when the project has none). command=logcat hands ' +
    'you the device log (a bounded dump - the last lines, optionally ' +
    'filtered), so you can debug what your deployed app did on the device ' +
    'from anywhere. command=screenshot (the device screen to a PNG you ' +
    'then fetch) plus command=tap and command=key are your remote eyes and ' +
    'hands on the device - enough to drive the deployed app. Typical ' +
    'flow: discover -> connect -> devices -> delphi_build target=Deploy ' +
    '-> install -> run -> screenshot -> tap -> logcat.';

  SP_ADB_COMMAND =
    'discover (find devices announcing wireless debugging by mDNS, with ' +
    'their ip:port) | devices (list attached devices; default) | connect ' +
    '(attach over the network: address) | disconnect (detach: address) | ' +
    'install (put an .apk on a device: apk, optional device) | run ' +
    '(launch an installed app on the device: app, optional device - the ' +
    'IDE''s "Deploy and Run") | logcat (the device log, bounded dump: ' +
    'optional device, filter, lines) | screenshot (grab the device screen ' +
    'to a PNG on the server: out, optional device - then delphi_fetch it: ' +
    'your remote eyes) | tap (touch the screen: x, y in pixels measured on ' +
    'a screenshot, optional device) | key (press a navigation key: key, ' +
    'optional device)';
  SP_ADB_ADDRESS =
    'ip:port of the device for connect/disconnect (from command=discover, ' +
    'or the device''s wireless-debugging screen)';
  SP_ADB_DEVICE =
    'Device serial (from command=devices) when several are attached ' +
    '(connect/disconnect/install/logcat)';
  SP_ADB_APK =
    'Path of the .apk to install (inside the workspace)';
  SP_ADB_APP =
    'run: package name of the installed app to launch (e.g. ' +
    'com.embarcadero.MiApp - the build/install results state it)';
  SP_ADB_OUT =
    'screenshot: server path of the .png to write (then delphi_fetch it). ' +
    'logcat: optional .txt/.log path to dump into INSTEAD of answering ' +
    'inline - then read it in ranges with delphi_read. Inside the workspace';
  SP_ADB_X =
    'tap: X coordinate in pixels (measure on a screenshot)';
  SP_ADB_Y =
    'tap: Y coordinate in pixels (measure on a screenshot)';
  SP_ADB_KEY =
    'key: back | home | enter | appswitch | wakeup | up | down | left | ' +
    'right | tab';
  SP_ADB_FILTER =
    'logcat: only lines containing this text (e.g. your app tag or package). ' +
    'Optional';
  SP_ADB_LINES =
    'logcat: how many recent lines to capture (default 300, max 5000; 0 = ' +
    'the default). Inline answers carry at most the newest 400 - for a ' +
    'bigger dump pass out=<file.txt> and read it in ranges. Optional';

  SR_ADB_CMD =
    'error: command debe ser discover | devices | connect | disconnect | ' +
    'install | run | logcat | screenshot | tap | key';

  SR_ADB_NEED_OUT =
    'RECHAZADO: screenshot necesita "out" (ruta .png dentro del workspace ' +
    'donde dejar la captura; despues se descarga con delphi_fetch).';

  SR_ADB_OUT_PNG =
    'RECHAZADO: "out" debe terminar en .png.';

  SR_ADB_NEED_XY =
    'RECHAZADO: tap necesita "x" e "y" (pixeles de pantalla; midelos sobre ' +
    'un command=screenshot).';

  SR_ADB_XY_FMT =
    'RECHAZADO: "%s" no vale como coordenada de pantalla (solo digitos).';

  SR_ADB_KEY_FMT =
    'RECHAZADO: "%s" no es una tecla permitida. Usa back | home | enter | ' +
    'appswitch | wakeup | up | down | left | right | tab.';

  SR_ADB_ALLOWLIST_FMT =
    'RECHAZADO: el dispositivo "%s" no esta en la lista permitida de este ' +
    'servidor ([Adb] AllowedDevices en settings.ini). Fuera de esa lista, ' +
    'nada. El operador la amplia si procede.';

  SR_ADB_ALLOWLIST_DEVICE =
    'RECHAZADO: este servidor tiene lista de dispositivos permitidos ' +
    '([Adb] AllowedDevices): indica "device" explicitamente con uno de la ' +
    'lista (command=devices los enseña).';

  SN_ADB_GONE =
    'SIN CONEXION CON EL DISPOSITIVO. El adb por wifi se cae solo tras un ' +
    'rato de inactividad - es cosa del aparato, no de este servidor. ' +
    'Camino: reintenta command=connect al MISMO ip:port (en muchos ' +
    'dispositivos el puerto persiste); si no entra, que el developer ' +
    'reactive la depuracion inalambrica en el aparato y busca el puerto ' +
    'nuevo con command=discover (Android 11+ lo aleatoriza al reactivar). ' +
    'command=devices dice que hay enganchado AHORA MISMO.';

  SR_ADB_OUT_LOG =
    'RECHAZADO: el "out" de logcat debe terminar en .txt o .log.';

  SN_ADB_LOGFILE =
    'The dump is in this file ON THE SERVER. Read it in ranges with ' +
    'delphi_read (400 lines per call), search it with delphi_search, or ' +
    'download it to your machine with delphi_fetch.';

  SN_ADB_TAIL_FMT =
    '(logcat: %d lineas capturadas; van las %d MAS RECIENTES. Para el ' +
    'volcado completo repite con out=<fichero.txt> y leelo por rangos con ' +
    'delphi_read, o acota con filter.)';

  SN_ADB_SCREENSHOT =
    'The device screen is in this PNG on the server - download it with ' +
    'delphi_fetch. Coordinates measured on it are exactly what ' +
    'command=tap takes.';

  SR_ADB_NEED_APP =
    'RECHAZADO: run necesita "app" (el nombre del paquete instalado, p.ej. ' +
    'com.embarcadero.MiApp - lo declaran los resultados de build e install).';

  SR_ADB_APP_FMT =
    'RECHAZADO: "%s" no vale como nombre de paquete Android. Letras, ' +
    'digitos, ".", "_" y "-" (p.ej. com.embarcadero.MiApp).';

  SR_ADB_NO_SDK =
    'error: este servidor no tiene un SDK de Android configurado (no hay ' +
    'ningun .sdk con SDKAdbPath). Se instala una vez con el SDK Manager ' +
    'del IDE; despues esta tool usa su adb.';

  SR_ADB_NEED_ADDRESS =
    'RECHAZADO: connect/disconnect necesitan "address" (ip:puerto del ' +
    'dispositivo con depuracion inalambrica activa, p.ej. 192.168.1.50:5555).';

  SR_ADB_NEED_APK =
    'RECHAZADO: install necesita "apk" (ruta del .apk compilado, dentro del ' +
    'workspace). Compila con delphi_build platform=Android64 target=Deploy ' +
    '(el resultado declara donde queda el .apk).';

  SR_ADB_TARGET_FMT =
    'RECHAZADO: "%s" no vale como direccion o serial de dispositivo. Usa ' +
    'letras, digitos, ".", ":", "_" y "-" (como los que lista ' +
    'command=devices).';

  SN_ADB_DEVICES =
    'These devices hang off the SERVER machine. Attach one over the ' +
    'network with command=connect address=ip:port. Deploy an app to one: ' +
    'delphi_build platform=Android64 target=Deploy builds the .apk ' +
    '(generating the deployment manifest if the project has none), then ' +
    'command=install puts it on the device.';

  SN_ADB_DISCOVER =
    'Devices announcing wireless debugging on the server''s network. Take ' +
    'an ip:port and command=connect to it (the device shows an authorize ' +
    'prompt the first time). Nothing here means none is announcing - the ' +
    'device''s wireless-debugging screen must be OPEN, or the developer can ' +
    'read the ip:port off it and give it to you directly.';

  SR_ADB_LINES_FMT =
    'RECHAZADO: "%s" no es un numero de lineas valido para logcat (1-5000).';

  // ---- /files download route + delphi_fetch ----

  SD_FETCH =
    'Download a file FROM the server - the "get the deploy" tool: after ' +
    'delphi_build, fetch the exe (and any companion files listed with ' +
    'delphi_list) to run GUI apps on YOUR machine. Two ways: (1) the ' +
    '"download" field of the answer is a direct HTTP GET on this same ' +
    'server (/files?path=...): run it with curl and your same Bearer token - ' +
    'the standard way for any file, installers and binaries included; ' +
    '(2) base64 chunks inline, for small files or clients without a shell: ' +
    'loop offset until eof=true, concatenate the decoded chunks, verify the ' +
    'sha256 (whole file, returned on the offset=0 call). Files over 4 MB ' +
    'answer with the download link only; pass maxbytes<=1048576 explicitly ' +
    'to get inline chunks instead. Jailed to the workspace roots and the ' +
    'read-only library zone.';

  SN_FETCH_DOWNLOAD =
    'Direct download: GET this path on the SAME host:port you use for /mcp, ' +
    'with the SAME Authorization: Bearer header, e.g. ' +
    'curl -H "Authorization: Bearer <token>" -o <file> "http://<host>:<port><download>". ' +
    'The response carries X-File-SHA256 to verify with sha256sum.';

  SN_FETCH_BIG_FMT =
    'This file is %s: use the "download" link (curl) - no chunk was ' +
    'included. For inline base64 chunks instead, pass maxbytes=1048576 (or ' +
    'less) and loop offset until eof=true.';

  SR_FILES_NEED_PATH =
    'Falta el parametro path: GET /files?path=srvd:\...\fichero';

  SR_FILES_DIR =
    'RECHAZADO: es un directorio. /files descarga ficheros, nunca lista carpetas.';

  SR_FILES_MISSING =
    'No existe el fichero pedido.';

  // Appended to a READ refusal outside the jail: the library zone exists,
  // but only the folders the IDE registers (and their subfolders) - not their
  // parents.
  SN_READ_ZONE_HINT =
    'Para LEER, ademas de los roots vale la zona de biblioteca: las carpetas ' +
    'que el IDE registra en su Library Path (fuentes RTL/VCL/FMX y de ' +
    'componentes instalados), la raiz de instalacion de cada componente (un ' +
    'nivel por encima: Library, Redist, Examples) y sus subcarpetas. ' +
    'delphi_workspace las enumera.';

  // ---- delphi_config: search paths ----

  SP_CONFIG_PATH =
    'add/remove-searchpath: the unit search path to add or remove - a ' +
    'folder where the compiler looks for .pas/.dcu, e.g. the Source folder ' +
    'of an installed component (delphi_workspace lists the readable library ' +
    'zone). IDE macros like $(BDS) are accepted; relative paths resolve from ' +
    'the project folder. Must resolve inside the workspace or the library ' +
    'zone and exist. add/remove-unit: the .pas to register in / take out of ' +
    'the project (add/remove-deployfile: the file to ship).';

  SR_CONFIG_NEED_PATH =
    'Falta "path": la carpeta a anadir/quitar del search path (p.ej. la ' +
    'carpeta Source de un componente instalado). Si tu esquema de tools no ' +
    'tiene el parametro "path", el servidor se actualizo despues de tu ' +
    'conexion: reconecta la sesion MCP para recibir el esquema nuevo.';

  SR_CONFIG_PATH_CHARS =
    'RECHAZADO: el path lleva caracteres no permitidos (< > " ; & | o de ' +
    'control) o es demasiado largo. Una ruta por llamada, sin ";".';

  SR_CONFIG_PATH_MACRO_FMT =
    'RECHAZADO: no puedo resolver "%s" (macro desconocida o ruta invalida). ' +
    'Usa una ruta real o una macro del IDE como $(BDS).';

  SR_CONFIG_PATH_MISSING_FMT =
    'RECHAZADO: la carpeta "%s" no existe en el servidor. Busca la ' +
    'correcta con delphi_list (zona de biblioteca) antes de anadirla.';

  SN_CONFIG_PATH_ADDED_FMT =
    'ANADIDO "%s" al search path de %s (resuelve a %s). Los PropertyGroup de ' +
    'la plataforma se crearon como lo haria el IDE si no existian; copia ' +
    'previa del .dproj en __delphi-patch. Verifica con delphi_build ' +
    '{platform:"%s"}.';

  SN_CONFIG_PATH_PRESENT_FMT =
    '"%s" ya estaba en el search path de %s. Nada que cambiar.';

  SN_CONFIG_PATH_REMOVED_FMT =
    'QUITADO "%s" del search path de %s. Copia previa del .dproj en __delphi-patch.';

  SN_CONFIG_PATH_ABSENT_FMT =
    '"%s" no esta en el search path de %s. Mira los actuales con command=view.';

  SN_CONFIG_NO_PATHS =
    'The project declares no unit search paths of its own: the compiler ' +
    'finds units through the IDE library path of each platform. A platform ' +
    'added later gets none of that - add-searchpath fixes "unit not found" ' +
    'on one platform only.';

  // ---- delphi_config: deployment files ----

  SP_CONFIG_REMOTEDIR =
    'add-deployfile: destination folder on the target, relative to the ' +
    'deployment root (the IDE''s RemoteDir). Default: the project folder, ' +
    'next to the binary - or, for a .so on Android, the apk''s ' +
    'library\lib\<abi>\. No absolute paths, no "..".';

  SR_CONFIG_DEPLOY_NEED_PATH =
    'Falta "path": el fichero que debe viajar con el despliegue (p.ej. la ' +
    'libreria nativa que un componente carga en runtime). Si tu esquema de ' +
    'tools no tiene "path" ni "remotedir", el servidor se actualizo despues ' +
    'de tu conexion: reconecta la sesion MCP para recibir el esquema nuevo.';

  SR_CONFIG_DEPLOY_PLATFORM_FMT =
    'RECHAZADO: "%s" no es una plataforma Delphi valida (add/remove-deployfile ' +
    'la necesita: Linux64, OSX64, Android64...).';

  SR_CONFIG_DEPLOY_NOT_FILE_FMT =
    'RECHAZADO: "%s" es una carpeta. add-deployfile lleva FICHEROS, uno por llamada.';

  SR_CONFIG_DEPLOY_MISSING_FMT =
    'RECHAZADO: el fichero "%s" no existe en el servidor. Localizalo con ' +
    'delphi_list (zona de biblioteca) antes de anadirlo.';

  SR_CONFIG_REMOTEDIR_CHARS =
    'RECHAZADO: remotedir debe ser una carpeta relativa simple (sin "..", ' +
    'sin ":", sin barra inicial ni caracteres especiales), p.ej. MiApp\lib\.';

  SN_CONFIG_DEPLOY_ADDED_FMT =
    'ANADIDO al despliegue de %s: "%s" -> %s%s (Debug y Release). %sCopia ' +
    'previa del .deployproj en __delphi-patch. Despliega con delphi_build ' +
    'target=Deploy platform=%s.';

  SN_CONFIG_DEPLOY_GENERATED =
    'El proyecto no tenia manifiesto de despliegue: se genero el estandar ' +
    '(el binario) antes de anadir el fichero.';

  SN_CONFIG_DEPLOY_PRESENT_FMT =
    '"%s" ya viaja en el despliegue de %s. Nada que cambiar.';

  SN_CONFIG_DEPLOY_REMOVED_FMT =
    'QUITADO "%s" del despliegue de %s (%d entradas). Copia previa en __delphi-patch.';

  SN_CONFIG_DEPLOY_ABSENT_FMT =
    '"%s" no esta en el despliegue de %s. Mira las entradas con command=view.';

  SN_CONFIG_NO_DEPLOYPROJ =
    'No deployment manifest (.deployproj) next to the project yet: ' +
    'delphi_build target=Deploy generates the standard one (the binary), ' +
    'and add-deployfile adds extra files to it.';

  // ---- project units (Lsp.ProjectUnits: add-unit / remove-unit / create / delete / move) ----

  SR_UNIT_NEED_PROJECT =
    'Falta "project": el .dproj (o .dpr) del proyecto.';

  SR_UNIT_PROJECT_EXT_FMT =
    'RECHAZADO: "%s" no es un proyecto (.dproj o .dpr).';

  SR_UNIT_NO_DPR_FMT =
    'RECHAZADO: no existe el .dpr del proyecto (%s); las units se registran ' +
    'en el .dpr y sin el no hay programa.';

  SR_UNIT_NEED_PATH =
    'Falta "path": la unit .pas a registrar o quitar. Si tu cliente no ' +
    'muestra el parametro, reconecta la sesion MCP (el servidor se actualizo).';

  SR_UNIT_PAS_MISSING_FMT =
    'RECHAZADO: no existe %s. Para crear una unit nueva usa delphi_create ' +
    'kind=unit (o form-vcl / form-fmx).';

  SR_UNIT_NOT_PAS_FMT =
    'RECHAZADO: "%s" no es una unit .pas.';

  SR_UNIT_NO_HEADER_FMT =
    'RECHAZADO: %s no tiene cabecera "unit X;" - no es una unit Delphi.';

  SR_UNIT_HEADER_MISMATCH_FMT =
    'RECHAZADO: la cabecera dice "unit %s;" pero el fichero se llama %s. En ' +
    'Delphi deben coincidir; arregla uno de los dos con delphi_edit / delphi_move.';

  SR_UNIT_NO_USES_FMT =
    'RECHAZADO: no encuentro la clausula uses de %s.';

  SN_UNIT_ADDED_FMT =
    'ANADIDA la unit %s (%s) al proyecto %s: uses del .dpr + DCCReference ' +
    'del .dproj. Copias previas en __delphi-patch.';

  SN_UNIT_ADDED_FORM_FMT =
    'ANADIDA la unit %s (%s) con su form %s: %s al proyecto %s: uses del ' +
    '.dpr%s + DCCReference del .dproj. Copias previas en __delphi-patch.';

  SN_UNIT_CREATEFORM = ' + Application.CreateForm';

  SN_UNIT_PRESENT_FMT =
    'La unit %s ya estaba en %s. Nada que cambiar (entrada del .dproj refrescada).';

  SN_UNIT_NO_RUN_ANCHOR =
    'No hay Application.Run ni otro CreateForm en el .dpr: crea la instancia ' +
    'del form donde proceda (delphi_edit).';

  SN_UNIT_NO_ITEMGROUP =
    'El .dproj no tiene ItemGroup donde colgar el DCCReference; el IDE lo ' +
    'completara al abrir el proyecto (MSBuild compila igual por el uses).';

  SN_UNIT_NO_DPROJ =
    'El proyecto no tiene .dproj: solo se actualizo el .dpr.';

  SN_UNIT_REMOVED_FMT =
    'QUITADA la unit %s del proyecto %s (%s%s%s). El fichero %s sigue en ' +
    'disco; borralo con delphi_delete si ya no lo quieres. Copias previas en ' +
    '__delphi-patch.';

  SN_UNIT_ABSENT_FMT =
    'La unit %s no esta en el proyecto %s. Mira las units con command=view.';

  SN_UNIT_RENAMED_FMT =
    'REAPUNTADA la unit %s (%s) -> %s (%s) en el proyecto %s (uses del .dpr + ' +
    'DCCReference del .dproj).';

  SN_FILE_PROJECTS_UPDATED_FMT =
    '  proyectos actualizados (%d): %s';

  SN_FILE_PROJECTS_NONE =
    '  (ningun .dpr en la carpeta ni en la superior lo listaba; si otro ' +
    'proyecto lo usa, quitalo con delphi_config command=remove-unit)';

  SN_FILE_PROJECT_DENIED_FMT =
    '    %s: fuera de los workspaces permitidos, NO tocado (quita la unit ' +
    'con delphi_config command=remove-unit desde un proyecto dentro de la jaula).';

  SN_FILE_PARTIAL_FMT =
    'ERROR %s: %s'#10'ATENCION: antes del fallo ya se habian aplicado estos ' +
    'cambios (copias en __delphi-patch):%s';

  SN_FILE_DESIGNER_TOO_FMT =
    '  designer %s: %s';

  // ---- delphi_diagnostics ----

  SN_DIAG_IN_PROGRESS =
    '{"status":"in-progress","note":"El lint sigue en marcha en el LSP (las ' +
    'units grandes tardan mas de un minuto la primera vez). Vuelve a llamar a ' +
    'delphi_diagnostics con el mismo fichero: el lint NO se reinicia mientras ' +
    'el fichero no cambie y la siguiente llamada devuelve el resultado."}';

  // ---- delphi_styles ----

  SD_STYLES =
    'FMX STYLES of a project, by StyleName: the text .style files (what the ' +
    'Bitmap Style Designer exports and a style pipeline keeps as source of ' +
    'truth). command=view lists the styles of a file (StyleName, class, ' +
    'lines, parts); get shows one whole; set changes or adds ONE property of ' +
    'a style or of a part inside it (child=background/text), value written ' +
    'exactly as the file does (xAARRGGBB colors, floats with 18 decimals, ' +
    'quoted strings); clone copies a style under a new StyleName - the way to ' +
    'add a variant; lint checks the whole thing: duplicated StyleNames, ' +
    'StyleLookup values in the project''s .fmx/.pas that NO style defines ' +
    '(the platform default style counts), design tokens missing in a theme ' +
    'of a *Tokens.ini, .rc entries whose file is missing; build converts ' +
    'every text .style of the folder to .bin.style (the form an app embeds: ' +
    'embedded TEXT loads but does not resolve StyleLookup) and compiles the ' +
    'folder''s .rc to .res with brcc32. Binary styles are never edited. ' +
    'Edits keep encoding and leave a __delphi-patch copy.';

  SP_STYLES_PATH =
    'The text .style file (view/get/set/clone) or the styles FOLDER (lint/' +
    'build; a file is accepted too). Binary styles (FMX_STYLE / .bin.style) ' +
    'are refused for editing: edit the text one and run build.';

  SR_STYLES_NEED_PATH =
    'Falta "path": el .style de texto (view/get/set/clone) o la carpeta de ' +
    'estilos (lint/build). Si tu cliente no muestra el parametro, reconecta ' +
    'la sesion MCP (el servidor se actualizo).';

  SR_STYLES_MISSING_FMT =
    'RECHAZADO: no existe %s. Localiza los estilos con delphi_list pattern=*.style.';

  SR_STYLES_NEED_FILE =
    'RECHAZADO: view/get/set/clone necesitan UN fichero .style de texto, no una ' +
    'carpeta (delphi_list pattern=*.style la lista).';

  SR_STYLES_BINARY_FMT =
    'RECHAZADO: %s es un estilo BINARIO (producto de build). Edita el .style de ' +
    'texto del que sale y vuelve a ejecutar command=build.';

  SR_STYLES_NEED_STYLE =
    'Falta "style": el StyleName del estilo (command=view los lista).';

  SR_STYLES_NEED_PROP =
    'Falta "prop": la propiedad a cambiar, como aparece en el fichero ' +
    '(Fill.Color, Size.Height, Visible...). command=get muestra el estilo.';

  SR_STYLES_PROP_CHARS_FMT =
    'RECHAZADO: "%s" no es un nombre de propiedad (letras, digitos, puntos).';

  SR_STYLES_NEED_VALUE =
    'Falta "value": el valor tal como se escribe en un .style (xFFF6ECDB, ' +
    '44.000000000000000000, True, ''texto'', Center). Para quitar la propiedad ' +
    'usa delete=true.';

  SR_STYLES_VALUE_LINE =
    'RECHAZADO: value debe ser UNA linea. Los valores multilinea (colecciones, ' +
    'binarios) se editan con delphi_textedit sobre el fichero.';

  SR_STYLES_NEED_NAME =
    'Falta "name": el StyleName del estilo nuevo.';

  SR_STYLES_NAME_CHARS_FMT =
    'RECHAZADO: "%s" no vale como StyleName (letras, digitos, punto, guion).';

  SR_STYLES_NAME_TAKEN_FMT =
    'RECHAZADO: ya existe un estilo ''%s'' en el fichero. Elige otro nombre o ' +
    'cambia el existente con set.';

  SR_STYLES_NO_TEXT_FMT =
    'RECHAZADO: no hay ningun .style de TEXTO en %s (los .bin.style y los ' +
    'binarios no cuentan). Exporta el estilo como texto desde el Bitmap Style ' +
    'Designer o apunta a la carpeta correcta.';

  SR_STYLES_NO_CONVERTER =
    'RECHAZADO: falta DelphiStyleConvert.exe junto al servidor (el conversor ' +
    'texto<->binario). Avisa al operador: se despliega con el servidor.';

  SN_STYLES_VIEW_NOTE =
    'StyleLookup of a control resolves to one of these StyleNames (case-' +
    'insensitive). get shows a style; set changes one property; clone adds a ' +
    'variant. After editing run command=build so the app embeds the change.';

  SN_STYLES_PROP_SET_FMT =
    '%s: %s (estilo %s%s, %s). Copia previa en __delphi-patch. Recuerda ' +
    'command=build para regenerar el binario que embebe la app.';

  SN_STYLES_PROP_DELETED_FMT =
    'QUITADA la propiedad %s del estilo %s%s (%s). Copia previa en __delphi-patch.';

  SN_STYLES_PROP_ABSENT_FMT =
    'La propiedad %s no esta en el estilo %s%s (nada que quitar; command=get lo muestra).';

  SN_STYLES_CLONED_FMT =
    'CLONADO: nuevo estilo ''%s'' a partir de ''%s'' (lineas %d-%d de %s). ' +
    'Ajusta sus propiedades con set y regenera con build; en el .fmx se usa ' +
    'con StyleLookup = ''%0:s''.';

  SN_STYLES_DELETED_FMT =
    'BORRADO el estilo ''%s'' (lineas %d-%d de %s; quedan %d estilos). La ' +
    'copia previa del fichero esta en __delphi-patch (delphi_list la ' +
    'muestra): para deshacer, delphi_move de esa copia sobre el fichero. ' +
    'Regenera con build; un StyleLookup que lo usara queda sin estilo ' +
    '(command=lint lo dira).';

  SN_STYLES_LINT_NOTE =
    'lookupsWithoutStyle: a control with that StyleLookup will render with ' +
    'the default look (no error at runtime) - define the style (clone) or fix ' +
    'the name. duplicatedStyleNames: the last one wins silently. ' +
    'lookupsStandard are names the platform default style provides.';

  SN_STYLES_NO_DEFAULTS =
    'The platform default style names could not be extracted (converter ' +
    'missing): standard lookups such as buttonstyle may appear as missing.';

  SN_STYLES_BUILD_NOTE =
    'The .bin.style files are what the app embeds (.rc RCDATA -> .res). ' +
    'Rebuild the project afterwards (delphi_build target=Build) so the new ' +
    '.res goes in; MSBuild reuses an old .res otherwise.';

  // ---- delphi_messages ----

  SD_MESSAGES =
    'Your MAILBOX: messages the operator leaves for you (the way back of ' +
    'delphi_report). command=read delivers every pending message addressed ' +
    'to your agent id or to everyone, once; check only lists what waits. ' +
    'While mail waits, every tool answer ends with a MENSAJES PENDIENTES ' +
    'line - read it then: it may change what you are doing.';

  SN_MESSAGES_PENDING_FMT =
    #10'MENSAJES PENDIENTES: %d (buzon: %s). Leelos con delphi_messages ' +
    'command=read agent=<tu id>.';

  SN_MESSAGES_NONE_FMT =
    'Sin mensajes para "%s" ni para todos.';

  SN_MESSAGES_NONE_NO_AGENT =
    'Sin mensajes para todos. Si tienes un id de agente (el "agent" de ' +
    'delphi_report), pasalo en agent= para ver tu buzon propio.';

  SN_MESSAGES_CHECK_FMT =
    'Mensajes pendientes: %d (command=read los entrega):';

  SN_MESSAGES_DELIVERED =
    '(entregados; no volveran a aparecer. Si piden algo, hazlo y, si ' +
    'procede, responde con delphi_report.)';

  // ---- delphi_build: F2613 helper ----

  SN_BUILD_MISSING_UNITS_NOTE =
    'Unidades que el compilador no encuentra y donde vive su .pas en la zona ' +
    'de biblioteca del servidor. Registra la carpeta para esta plataforma con ' +
    'delphi_config command=add-searchpath platform=<plataforma> path=<carpeta> ' +
    'y repite la build. Sin candidatos: el componente no esta instalado o no ' +
    'trae fuente para esta plataforma (delphi_components platform=<plataforma>, ' +
    'y si falta, delphi_report).';

  // ---- delphi_rename_symbol ----

  SD_RENAME =
    'SEMANTIC RENAME of a Delphi symbol - PREVIEW ONLY in this version, by ' +
    'design. Point at the identifier (path + 0-based line/character, same ' +
    'convention as delphi_definition) and give newname: the answer lists ' +
    'every CONFIRMED occurrence (each one re-resolved against the same ' +
    'definition), the files touched, and whether the rename is APPLICABLE. ' +
    'The rule is strict on purpose: one single unverified reference, a hit ' +
    'in a .dfm/.fmx (form bindings break), a hit inside a string literal ' +
    '(FindComponent/RTTI/StyleLookup by name), a symbol whose definition ' +
    'lives outside the workspace (RTL/components), or a collision with the ' +
    'new name = applicable=false with the reasons. mode=apply is refused ' +
    'for now: it will arrive over delphi_changeset once preview has been ' +
    'validated in the field. Meanwhile, an applicable=true preview gives ' +
    'you the exact change list to stage yourself with delphi_changeset.';

  SP_RENAME_PATH =
    'The .pas/.dpr with the symbol (any occurrence works)';

  SP_RENAME_LINE =
    'Zero-based line of the identifier (same convention as delphi_definition)';

  SP_RENAME_CHARACTER =
    'Zero-based column inside the identifier';

  SP_RENAME_NEWNAME =
    'The new identifier (legal Delphi name, no reserved words)';

  SP_RENAME_MODE =
    'preview (default; never writes) | apply (refused for now - arrives ' +
    'over delphi_changeset after field validation)';

  SR_RENAME_MODE =
    'error: mode debe ser preview (apply llegara sobre delphi_changeset).';

  SR_RENAME_NEED_PATH =
    'RECHAZADO: falta "path" (el fichero con el simbolo).';

  SR_RENAME_NEED_NEWNAME =
    'RECHAZADO: falta "newname" (el identificador nuevo).';

  SR_RENAME_APPLY_NOT_YET =
    'RECHAZADO: mode=apply aun no existe, a proposito: el preview tiene que ' +
    'validarse en campo antes de escribir nada. Si el preview te da ' +
    'applicable=true, su lista changes es exactamente lo que puedes montar ' +
    'tu mismo con delphi_changeset (stage edit por linea + preview + commit).';

  SR_RENAME_BAD_IDENT_FMT =
    '"%s" no es un identificador Delphi valido (letra o _ inicial, luego ' +
    'letras/digitos/_).';

  SR_RENAME_RESERVED_FMT =
    '"%s" es una palabra reservada de Delphi.';

  SR_RENAME_SAME_NAME =
    'El nombre nuevo es igual al actual.';

  SR_RENAME_LIBRARY =
    'La definicion del simbolo vive FUERA de los workspace roots (RTL o ' +
    'componente instalado): eso no se renombra desde aqui.';

  SR_RENAME_UNVERIFIED_FMT =
    '%d referencias candidatas NO confirmadas semanticamente. La regla es ' +
    'estricta: una sola sin confirmar = no aplicable (un falso positivo ' +
    'renombrado es un homonimo roto en silencio).';

  SR_RENAME_DESIGNER_FMT =
    '%d apariciones en designers (.dfm/.fmx): renombrar un miembro publicado ' +
    'rompe el binding del form (el IDE solo lo repara interactivamente).';

  SR_RENAME_STRINGS_FMT =
    '%d apariciones dentro de literales de cadena (FindComponent, RTTI por ' +
    'nombre, StyleLookup...): un rename textual las dejaria apuntando a un ' +
    'nombre que ya no existe y el compilador no avisa.';

  SR_RENAME_COLLISION_FMT =
    'El nombre nuevo "%s" ya aparece %d veces en los ficheros afectados: ' +
    'posible colision u homonimo.';

  SN_RENAME_DESIGNER_HIT_FMT =
    '%d apariciones en %s';

  SN_RENAME_PREVIEW_NOTE =
    'Preview: NOTHING was written. applicable=true means every occurrence ' +
    'is semantically confirmed and no designer/string/collision hit exists; ' +
    'stage the changes with delphi_changeset (one edit per line, then ' +
    'preview + commit there). applicable=false lists the blockers - fix ' +
    'them or do the rename by hand with the evidence given.';

  // ---- delphi_designer ----

  SD_DESIGNER =
    'FORMS AND COMPONENTS, structured - never guess what a class publishes ' +
    'or what a form contains. command=info class=TButton: every property ' +
    'the framework really publishes for that class (kind and type; events ' +
    'apart), from RTTI tables generated at release time. prop class=X ' +
    'prop=Y: one property in detail, with the legal members when it is an ' +
    'enum/set. tree path=<.dfm|.fmx>: the component tree (name, class, ' +
    'line). get path=... component=<Name>: that component''s block verbatim. ' +
    'lint path=...: unknown classes, properties the class does not publish, ' +
    'enum values that do not exist. Text designers only (binary TPF0 is ' +
    'refused, as everywhere). Read-only: editing a form is phase 2 and will ' +
    'go through delphi_changeset; today use delphi_edit on the .dfm/.fmx ' +
    'with the property line as anchor, then this lint to verify.';

  SP_DESIGNER_COMMAND =
    'info (what a class publishes) | prop (one property in detail) | tree ' +
    '(component tree of a text .dfm/.fmx) | get (one component''s block) | ' +
    'lint (designer lint on demand). Default: info';

  SP_DESIGNER_PATH =
    'tree/get/lint: the .dfm or .fmx file (text form; binary TPF0 refused)';

  SP_DESIGNER_CLASS =
    'info/prop: the component class, e.g. TButton, TEdit, TLayout';

  SP_DESIGNER_PROP =
    'prop: the property name, e.g. Align, Caption, TextSettings';

  SP_DESIGNER_COMPONENT =
    'get: the component Name as it appears in the form (object <Name>: <Class>)';

  SP_DESIGNER_FRAMEWORK =
    'info/prop: vcl | fmx. Optional when path is given (.dfm=vcl, .fmx=fmx); ' +
    'default vcl';

  SP_DESIGNER_FILTER =
    'info optional: only properties whose name contains this text';

  SR_DESIGNER_CMD =
    'error: command debe ser info | prop | tree | get | lint';

  SR_DESIGNER_FRAMEWORK =
    'RECHAZADO: framework debe ser vcl o fmx.';

  SR_DESIGNER_NEED_CLASS =
    'RECHAZADO: falta "class" (la clase del componente, p.ej. TButton).';

  SR_DESIGNER_NEED_PROP =
    'RECHAZADO: falta "prop" (la propiedad, p.ej. Align).';

  SR_DESIGNER_NEED_PATH =
    'RECHAZADO: falta "path" (el .dfm o .fmx).';

  SR_DESIGNER_NEED_COMPONENT =
    'RECHAZADO: falta "component" (el Name del componente en el form).';

  SR_DESIGNER_NOT_FORM =
    'RECHAZADO: eso no es un designer (.dfm/.fmx).';

  SR_DESIGNER_BINARY =
    'RECHAZADO: designer BINARIO (TPF0). Este servidor no lo toca ni lo ' +
    'interpreta: abrelo en el IDE y guardalo como texto si quieres operarlo ' +
    'desde aqui.';

  SR_DESIGNER_EMPTY =
    'RECHAZADO: el fichero no contiene ningun object.';

  SR_DESIGNER_CLASS_FMT =
    'RECHAZADO: la clase "%s" no esta en la tabla %s de este servidor (no ' +
    'la publica el framework o el componente no esta enlazado en las tablas ' +
    'generadas). delphi_components lista los packages instalados.';

  SR_DESIGNER_PROP_FMT =
    'RECHAZADO: %s no es una propiedad publicada de %s. command=info la ' +
    'lista entera.';

  SR_DESIGNER_COMPONENT_FMT =
    'RECHAZADO: no hay ningun componente "%s" en ese form (command=tree los ' +
    'lista).';

  SN_DESIGNER_INFO_NOTE =
    'Published properties from the framework''s own RTTI (inherited ' +
    'included). A property absent here does NOT stream in a .dfm/.fmx: do ' +
    'not write it.';

  SN_DESIGNER_TREE_NOTE =
    'Component tree of the TEXT designer. get shows one component; lint ' +
    'checks classes, properties and enum values against the framework tables.';

  SN_DESIGNER_LINT_OK_FMT =
    'LINT LIMPIO: %s no tiene clases desconocidas, propiedades no publicadas ' +
    'ni valores de enum invalidos.';

  SN_DESIGNER_LINT_BAD_FMT =
    '%d avisos del designer en %s (clase desconocida, propiedad no publicada ' +
    'o valor de enum inexistente):';

  // ---- delphi_changeset ----

  SD_CHANGESET =
    'MULTI-FILE TRANSACTIONS: when one change touches several files, either ' +
    'the whole batch lands or none of it. Flow: command=begin (returns an ' +
    'id) -> stage one operation per call (kind=edit|create|delete|move; ' +
    'nothing touches disk yet) -> preview (resolves every edit anchor and ' +
    'fingerprints every file the batch will touch) -> commit (fingerprints ' +
    're-checked - a file changed since preview refuses the WHOLE batch -, ' +
    'byte snapshots taken, operations applied in order; any failure restores ' +
    'every file byte-exact and reports which operation failed). rollback ' +
    'discards a staged batch; status lists open changesets. Edits use the ' +
    'delphi_edit contract: old = ONE full line, unique in the file (atline ' +
    'pins a duplicate). A changeset expires after 30 minutes unused. Use it ' +
    'for renames, refactors and any change where a half-applied batch would ' +
    'leave the project broken; for one file, plain delphi_edit is simpler.';

  SP_CHANGESET_COMMAND =
    'begin (new changeset -> id) | stage (add ONE operation) | preview ' +
    '(resolve anchors + fingerprint files; required before commit) | commit ' +
    '(apply all or nothing) | rollback (discard) | status (list open ones)';

  SP_CHANGESET_ID =
    'The changeset id returned by begin (every command except begin/status)';

  SP_CHANGESET_KIND =
    'stage: edit (replace ONE line by anchor) | create (new file, never ' +
    'overwrites) | delete (the WHOLE FILE is removed; the snapshot is the ' +
    'way back) | delete-line (remove ONE line by atline - the only way to ' +
    'remove a BLANK line, which has no usable anchor) | move (rename/move, ' +
    'destination must not exist)';

  SP_CHANGESET_PATH =
    'stage: the file the operation touches (inside the workspace roots)';

  SP_CHANGESET_DEST =
    'stage kind=move: the destination path';

  SP_CHANGESET_OLD =
    'stage kind=edit: the anchor - ONE full line copied verbatim from ' +
    'delphi_read, unique in the file';

  SP_CHANGESET_NEW =
    'stage kind=edit: the replacement text (may span several lines)';

  SP_CHANGESET_CONTENT =
    'stage kind=create: the whole content of the new file';

  SP_CHANGESET_ATLINE =
    'stage kind=edit optional: 1-based line number to pin the anchor when ' +
    'the same line appears more than once. REQUIRED for kind=delete-line. ' +
    'Line numbers are rebased automatically against what earlier operations ' +
    'of the same changeset did to that file';

  SR_CHANGESET_CMD =
    'error: command debe ser begin | stage | preview | commit | rollback | status';

  SR_CHANGESET_TOO_MANY =
    'RECHAZADO: ya hay 8 changesets abiertos. Cierra alguno (commit o ' +
    'rollback) o espera a que caduquen (30 min sin uso).';

  SR_CHANGESET_UNKNOWN =
    'RECHAZADO: ese changeset no existe (o caduco a los 30 min sin uso). ' +
    'command=status lista los abiertos; command=begin abre uno nuevo.';

  SR_CHANGESET_KIND =
    'RECHAZADO: kind debe ser edit | create | delete | move.';

  SR_CHANGESET_NEED_PATH =
    'RECHAZADO: stage necesita "path" (el fichero que toca la operacion).';

  SR_CHANGESET_NEED_DEST =
    'RECHAZADO: kind=move necesita "dest" (el destino).';

  SR_CHANGESET_EDIT_NEEDS =
    'RECHAZADO: kind=edit necesita "old" (UNA linea completa copiada de ' +
    'delphi_read) y opcionalmente "new" (el reemplazo) y "atline".';

  SR_CHANGESET_DELLINE_NEEDS =
    'RECHAZADO: kind=delete-line necesita "atline" (el numero de linea, ' +
    '1-based) porque una linea EN BLANCO no tiene ancla usable. "old" es ' +
    'opcional y, si lo das, tiene que coincidir con esa linea.';

  SR_CHANGESET_EMPTY =
    'RECHAZADO: el changeset no tiene operaciones. stage anade una por llamada.';

  SR_CHANGESET_NOT_PREVIEWED =
    'RECHAZADO: commit exige un preview LIMPIO previo (unresolved=0) y ' +
    'posterior al ultimo stage. Llama a command=preview y revisa el resultado.';

  SR_CHANGESET_FILE_CHANGED_FMT =
    'RECHAZADO: FILE_CHANGED - estos ficheros cambiaron despues del preview: ' +
    '%s. Nada se ha tocado. Repite preview (los fingerprints se recalculan) ' +
    'y vuelve a commit.';

  SR_CHANGESET_ROLLED_BACK_FMT =
    'ROLLBACK COMPLETO: fallo la operacion %d de %d y TODOS los ficheros han ' +
    'vuelto byte a byte a como estaban antes del commit. Causa: %s -- El ' +
    'changeset queda cerrado; corrige y monta otro.';

  SN_CHANGESET_BEGUN_FMT =
    'CHANGESET %s abierto. stage anade operaciones (una por llamada), ' +
    'preview las resuelve, commit aplica todo o nada.';

  SN_CHANGESET_STAGED_FMT =
    'STAGED %s de %s (operacion %d del changeset). Nada tocado aun: preview ' +
    'cuando termines de anadir.';

  SN_CHANGESET_DISCARDED =
    'Changeset descartado. No se habia tocado ningun fichero.';

  SN_CHANGESET_PREVIEW_OK =
    'Preview limpio: todas las anclas resuelven. commit aplica todo o nada; ' +
    'si un fichero cambia antes del commit, se rechaza entero.';

  SN_CHANGESET_PREVIEW_BAD =
    'Hay operaciones sin resolver (anchor NO ENCONTRADA o AMBIGUA): ' +
    'corrigelas (rollback y re-stage, o fija atline). commit esta bloqueado ' +
    'hasta un preview limpio.';

  SN_CHANGESET_COMMITTED_FMT =
    'COMMIT COMPLETO: %d operaciones aplicadas sobre %d ficheros. Los ' +
    'backups por fichero de __delphi-patch siguen existiendo como siempre.';

  // ---- delphi_components ----

  SD_COMPONENTS =
    'What this server''s RAD Studio has INSTALLED to program with: every ' +
    'component/design package REGISTERED in the IDE (Known Packages - the ' +
    'same list the IDE loads into its palette), whatever the install ' +
    'channel: GetIt, a vendor installer or manual. Each line is the ' +
    'package''s description plus its .bpl file; disabled packages are ' +
    'marked, IDE-plumbing packages are excluded. Read-only by design - ' +
    'there is no install command; if a library you need is missing, say ' +
    'so with delphi_report. The base RTL units are always available and ' +
    'never appear here.';

  SP_COMPONENTS_FILTER =
    'Optional: only entries whose description or file name contains this ' +
    'text (case-insensitive), e.g. "FMX", "TMS", "JEDI".';

  SP_COMPONENTS_PLATFORM =
    'Optional: a platform (Win32|Win64|Linux64|Android64|OSX64|iOSDevice64...) ' +
    'to see instead the IDE''s Library Search Path FOR THAT PLATFORM, expanded, ' +
    'plus the component install roots other platforms register and this one ' +
    'does not - the list to walk when a build on a new platform fails with ' +
    'F2613 (unit not found): delphi_config add-searchpath to the Source folder.';

  SR_COMPONENTS_PLATFORM_FMT =
    'Plataforma "%s" no reconocida. Validas: Win32, Win64, Win64x, WinARM64EC, ' +
    'OSX64, OSXARM64, Linux64, Android, Android64, iOSDevice64, iOSSimARM64.';

  SN_COMPONENTS_PLATFORM_HEAD_FMT =
    'Library Search Path del IDE para %s (RAD Studio %s): %d carpetas registradas';

  SN_COMPONENTS_PLATFORM_COMPLETE_FMT =
    'Todos los componentes registrados en otras plataformas lo estan tambien en %s.';

  SN_COMPONENTS_PLATFORM_MISSING_FMT =
    '%d componentes registrados en otras plataformas y NO en %s (candidatos ' +
    'cuando una build falle con F2613 "Unit X not found"):';

  SN_COMPONENTS_PLATFORM_HINT =
    'Un componente sin Lib\<plataforma> compila desde fuente: delphi_config ' +
    'command=add-searchpath platform=<plataforma> path=<raiz>\Source (la ' +
    'carpeta que contenga los .pas; mirala con delphi_list). Si solo trae ' +
    '.dcu/.so de otras plataformas, no sirve para esta: delphi_report.';

  SR_COMPONENTS_MISSING =
    'No se encontro ninguna instalacion de RAD Studio en el servidor - ' +
    'sin IDE no hay packages que listar.';

  SN_COMPONENTS_NONE_FMT =
    'Ningun package registrado contiene "%s". Lista completa: llama sin filter.';

  SN_COMPONENTS_NOTE =
    'These design packages are registered in the SERVER''s RAD Studio: ' +
    'their components and units are available to projects built here. ' +
    'Base RTL/VCL/FMX are always present and not listed. No install ' +
    'command exists by design - report a missing library with delphi_report.';

  SN_BUILD_ANDROID_NEW =
    'No .deployproj existed, so the standard Android deployment manifest ' +
    'was generated next to the project (generated AndroidManifest + styles/' +
    'strings/colors, default icons and splash artwork, the compiled ' +
    'library), plus an AndroidManifest.template.xml seed and fallback ' +
    'version properties in the .dproj (package com.embarcadero.<project>, ' +
    'minSdk 23) when the project had none. Files the IDE Deployment ' +
    'Manager already wrote are never overwritten.';

  SN_BUILD_APK_NOTE =
    'This is the built .apk (debug-signed, sideloadable). msbuild does not ' +
    'install Android apps (DeviceId only auto-installs on iOS): put it on ' +
    'a device hanging off this server with delphi_adb command=install ' +
    'apk=<path> (optional device=<serial>), open it with command=run ' +
    'app=<package>, and watch it with command=logcat.';

  // ---------------------------------------------------------------------
  // delphi_report (feedback channel - works at EVERY access level)
  // ---------------------------------------------------------------------
  SD_REPORT =
    'Report a problem, limitation or suggestion about THIS MCP server ' +
    'directly to its maintainers. Use it whenever a tool refuses something ' +
    'you believe is legitimate, an answer looks wrong, a message is ' +
    'confusing, or you had to work around a missing capability - that ' +
    'feedback is what fixes the server. Each report is stored as its own ' +
    'timestamped markdown file in a reports folder next to the server ' +
    'executable, with the server version and the date; pass a short stable ' +
    '"agent" id and your reports get their own subfolder, separate from ' +
    'other agents. Available at EVERY access level, read-only included. Be ' +
    'concrete: what you tried, what happened, what you expected.';

  SP_REPORT_MESSAGE =
    'The report itself: what you tried, what happened, what you expected. ' +
    'Markdown welcome, several paragraphs are fine';
  SP_REPORT_TITLE =
    'Optional one-line summary (becomes part of the file name)';
  SP_REPORT_KIND =
    'Optional: bug | limitation | suggestion | question (default: bug)';
  SP_REPORT_FROM =
    'Optional: who is reporting (agent/model name, project) - helps us read ' +
    'the history later';
  // The client still never supplies a path: the value is slugged to ASCII
  // letters/digits/dashes before it becomes a folder name, same normalizer
  // as the title. Also the seed of a wider client identity (future use).
  SP_REPORT_AGENT =
    'Optional short id of the reporting agent (e.g. "hermes"): its reports ' +
    'are stored in a folder of that name, separate from other agents. Keep ' +
    'it STABLE across your reports. Letters, digits and dashes; anything ' +
    'else is normalized away';

  SR_REPORT_EMPTY =
    'RECHAZADO: delphi_report necesita "message" con la descripcion del ' +
    'problema. Cuenta que intentaste, que paso y que esperabas.';

  // delphi_report is the ONE write a read-only (even anonymous) credential may
  // perform, so it is also the one place such a client could grow the server's
  // disk. A report is prose written by an agent: a generous cap still fits any
  // honest report - the field audit's longest was 45 KB - while turning "fill
  // the disk in one call" into something the operator would notice.
  SR_REPORT_TOO_BIG_FMT =
    'RECHAZADO: el reporte ocupa %d KB y el limite son %d KB. Cuenta lo ' +
    'esencial (que intentaste, que paso, que esperabas) y parte lo demas en ' +
    'varios reportes: se acumulan, no se sobreescriben.';

  SN_REPORT_OK_FMT =
    'GRACIAS - reporte guardado como %s (v%s).'#10 +
    'Lo leeremos con calma junto a los demas. Si descubres mas detalles, ' +
    'manda otro reporte: se acumulan, no se sobreescriben.';

implementation

end.
