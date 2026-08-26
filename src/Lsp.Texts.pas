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
  SERVER_VERSION = '0.82.0-beta';

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
  SN_PROJECTS_NO_MATCH_FMT =
    'Ningun proyecto se llama asi ("%s"). Hay %d en el workspace; llama sin ' +
    '"name" para verlos todos.';

  SR_PROJECTS_NO_ROOT_FMT =
    'error: la carpeta de trabajo "%s" no existe en este servidor. No es que ' +
    'no haya proyectos: es que ahi no hay nada. Mira delphi_workspace para ' +
    'ver cuales son las carpetas de verdad.';

  SN_SEARCH_CAPPED_FMT =
    'Te doy %d de %d coincidencias: el resto NO se listan. Afina la busqueda ' +
    '(un patron mas concreto, o "path" a una subcarpeta) antes de sacar ' +
    'conclusiones de este listado.';

  SR_CREATE_UNIT_NEED_PROJECT =
    'RECHAZADO: kind=unit necesita "project" (la ruta del .dpr o .dproj al ' +
    'que anadir la unit); la carpeta sale de ahi, NO de "dir". Ojo: "dir" si ' +
    'lo usan los kind=project-*, que es lo que despista.';

  SN_COMPONENTS_FILTER_IGNORED_FMT =
    '(He IGNORADO filter="%s": con platform= esto te da las rutas de ' +
    'biblioteca de esa plataforma, que es otra pregunta. Para buscar entre ' +
    'los paquetes instalados, llama sin platform.)';

  SN_REPORT_KIND_FMT =
    #10'(OJO: "%s" no es un kind de los que manejo, asi que lo he archivado ' +
    'como "bug". Los que hay: bug, limitation, suggestion, question.)';

  SR_DIAG_NOT_SOURCE_FMT =
    'RECHAZADO: %s no es un fuente Delphi (%s). El linter solo opina sobre ' +
    '.pas, .dpr, .dpk e .inc; sobre cualquier otra cosa te contestaba "sigue ' +
    'en marcha, vuelve a llamar" para siempre, y eso era mentira: no iba a ' +
    'terminar nunca.';

  SR_REFS_NO_DEFINITION_FMT =
    'RECHAZADO: el compilador no resuelve "%s" en esa posicion, asi que no ' +
    'hay nada contra lo que anclar las referencias. Casi siempre es porque ' +
    'estas apuntando a texto que no es un simbolo: dentro de una cadena, en ' +
    'un comentario, sobre una palabra reservada, o a un identificador de ' +
    'otra unit que este proyecto no compila. Apunta DENTRO del identificador ' +
    'en una linea de codigo de verdad (delphi_read te da linea y columna). Y ' +
    'si el proyecto no tiene configuracion utilizable, tambien puede pasar: ' +
    'delphi_config command=view te dice si la tiene.';

  SR_LSP_LINE_RANGE_FMT =
    'error: la linea %d no existe en %s, que tiene %d lineas. Recuerda que ' +
    'aqui las lineas van desde 0 (la ultima es la %d), mientras que ' +
    'delphi_read las numera desde 1.';

  SR_LSP_CHAR_RANGE_FMT =
    'error: la columna %d no existe en la linea %d, que tiene %d caracteres: ' +
    '"%s". Las columnas tambien van desde 0, y hay que apuntar DENTRO del ' +
    'identificador.';

  SR_LSP_NEGATIVE_FMT =
    'error: linea %d y columna %d: no hay posiciones negativas.';

  SP_SYMBOLS_PATH =
    'Un fichero Delphi (.pas/.dpr) para sus simbolos completos... o una ' +
    'CARPETA, y entonces te doy de golpe lo que OFRECE cada unit de ahi ' +
    'dentro (su seccion interface: tipos, clases, rutinas, propiedades y su ' +
    'uses), sin cuerpos. Eso es lo que hace falta para orientarse en codigo ' +
    'que no has escrito tu, y cuesta UNA llamada en vez de una por fichero.';

  SN_SYMBOLS_DIGEST_NOTE =
    'Esto es el RESUMEN: solo lo que cada unit declara en su interface, leido ' +
    'como texto y sin el motor semantico. Para el detalle de una unit (con ' +
    'rangos y anidamiento) llama con el fichero; para leerla entera, ' +
    'delphi_read. Si una unit no aparece o algo sale raro, no te fies del ' +
    'resumen para editar: lee el fichero.';

  SP_SYMBOLS_MODE =
    'Solo para un FICHERO: "summary" = el esqueleto (cada seccion con sus ' +
    'miembros y su linea; los contenedores dicen cuantos llevan dentro), ' +
    '"full" = el arbol LSP completo con rangos. Vacio = automatico: full ' +
    'si el arbol es pequeno, summary si es grande (la respuesta dice cual ' +
    'toco y cuanto pesaba el completo).';

  SP_SYMBOLS_FILTER =
    'Busca por nombre dentro del arbol de un fichero (subcadena, da igual ' +
    'mayusculas): devuelve SOLO los simbolos que casan, con su kind, su ' +
    'linea 0-based y en que contenedor viven. Ignora mode. Es la forma ' +
    'barata de encontrar un metodo sin traerte el arbol entero.';

  SN_SYMBOLS_SUMMARY_NOTE =
    'Esto es el RESUMEN del arbol (lineas 0-based). Los contenedores dicen ' +
    'cuantos miembros llevan (+N dentro): pide filter="nombre" para dar ' +
    'con uno concreto, o mode="full" para el arbol completo con rangos.';

  SN_SYMBOLS_AUTO_FMT =
    'El arbol completo pesaba %d caracteres, asi que te doy el resumen. ' +
    'Con mode="full" lo tienes entero; con filter="nombre" solo lo que ' +
    'buscas.';

  SP_CONFIG_SECTION =
    'Solo para view: summary (defecto: marco, configuraciones, plataformas ' +
    'activas y recuentos) | platforms (cada plataforma con su estado y sus ' +
    'motivos) | searchpaths (rutas por grupo) | deploy (ficheros por ' +
    'plataforma) | units (todas las units del proyecto) | all (todo junto, ' +
    'grande).';

  SN_CONFIG_SECTIONS =
    'Esto es el resumen. El detalle, por secciones: section=platforms | ' +
    'searchpaths | deploy | units. section=all lo trae todo junto (grande).';

  SR_LSP_NO_FILE_FMT =
    'RECHAZADO: no existe %s. (Antes esto salia como "Error executing ' +
    'tool", que en este servidor significa "me he roto por dentro" y no era ' +
    'el caso: el fichero simplemente no esta.)';

  SR_LSP_NOT_SOURCE_FMT =
    'RECHAZADO: %s no es un fuente Delphi (%s), asi que no hay simbolos que ' +
    'sacar; antes te devolvia una lista vacia, que parecia decir que la unit ' +
    'no tiene nada. Esta tool trabaja sobre .pas, .dpr, .dpk e .inc.';

  SP_PATCH_EDITS =
    'VARIAS ediciones sobre ESTE MISMO fichero, en una sola llamada y TODO O ' +
    'NADA: un array JSON [{"old":"...","new":"...","atline":12}, ...] que se ' +
    'aplica EN ORDEN. Cada entrada admite dos formas de ancla: UNA LINEA ' +
    '(igual que una edicion suelta) o un BLOQUE de varias lineas seguidas en ' +
    '"old", que se busca entero y en orden - util para sustituir el cuerpo de ' +
    'un metodo de una pieza. Si el ancla aparece mas de una vez, desempata ' +
    'con "occurrence": 1, 2... (mejor que "atline" dentro de una tanda: los ' +
    'numeros de linea SE MUEVEN segun las entradas anteriores anaden o quitan ' +
    'lineas, y "occurrence" no). "delete": true quita la linea. Si una ' +
    'entrada falla, el fichero vuelve byte a byte a como estaba y te digo ' +
    'cual fallo. Si el cambio toca VARIOS ficheros, eso es delphi_changeset. ' +
    'Cuando mandas "edits" se ignoran old/new/atline.';

  SR_PATCH_BLOCK_SHORT =
    'RECHAZADO: ese "old" de varias lineas se queda en una sola despues de ' +
    'quitarle el salto final. Para una linea suelta no hace falta nada ' +
    'especial: mandala tal cual.';

  SR_PATCH_BLOCK_MISSING_FMT =
    'RECHAZADO: no encuentro ese bloque de %d lineas. La primera que busco ' +
    'es "%s". El bloque se compara ENTERO y en orden (los espacios de los ' +
    'extremos de cada linea dan igual, el contenido no): reelee con ' +
    'delphi_read y copialo de ahi.';

  SR_PATCH_BLOCK_AMBIGUOUS_FMT =
    'RECHAZADO: ese bloque aparece %d veces (empieza por "%s"), asi que no se ' +
    'a cual te refieres. Anade "occurrence": 1, 2... a esa entrada, o alarga ' +
    'el bloque hasta que sea unico.';

  SN_PATCH_BLOCK_OK_FMT =
    'bloque de %d lineas sustituido (empezaba en la linea %d)';

  SR_PATCH_EDITS_JSON =
    'RECHAZADO: "edits" tiene que ser un array JSON de objetos, por ejemplo ' +
    '[{"old":"  FLista: TList;","new":"  FLista: TObjectList<TCosa>;"}]. Si ' +
    'lo mandas desde una linea de comandos, metelo en un fichero y usa la ' +
    'forma @fichero, que la consola no te lo destroce.';

  SR_PATCH_EDITS_EMPTY =
    'RECHAZADO: "edits" viene vacio. Sin operaciones no hay nada que aplicar.';

  SR_PATCH_EDITS_TOOMANY =
    'RECHAZADO: son demasiadas ediciones de una vez (el tope es 50). Si de ' +
    'verdad hay que tocar tantas lineas del mismo fichero, casi seguro que lo ' +
    'que quieres es reescribirlo entero: delphi_changeset con delete + create.';

  SR_PATCH_EDITS_NOFILE_FMT =
    'RECHAZADO: no existe %s.';

  SR_PATCH_EDITS_ROLLED_FMT =
    'ROLLBACK: fallo la edicion %d de %d y el fichero ha vuelto byte a byte a ' +
    'como estaba. NADA se ha aplicado, ni siquiera las anteriores. Esto es lo ' +
    'que paso:'#10'%s'#10'Corrige esa entrada (relee el fichero con ' +
    'delphi_read y copia el ancla literal) y vuelve a mandarlas todas.';

  SN_PATCH_EDITS_OK_FMT =
    'APLICADAS %d ediciones sobre %s, todas o ninguna:'#10'%s'#10'Copia ' +
    'previa del fichero en __delphi-patch (una por dia y fichero: la primera ' +
    'del dia es el original de antes de todo esto).';

  SN_EDIT_DUP_ABOVE_FMT =
    'OJO: la linea %d (justo ENCIMA) es identica a la primera que acabas de ' +
    'insertar: "%s". Casi siempre significa que has mandado el ancla ' +
    'repetida dentro de "new". Compila igual y no se ve; mira el fichero.';

  SN_EDIT_DUP_BELOW_FMT =
    'OJO: la linea %d (justo DEBAJO) es identica a la ultima que acabas de ' +
    'insertar: "%s". Suele ser el ancla mandada dos veces dentro de "new".';

  SR_READ_RANGE_FMT =
    'RECHAZADO: el rango va al reves (desde=%d, hasta=%d) y el fichero tiene ' +
    '%d lineas, asi que no hay nada que devolver. Antes te contestaba con el ' +
    'cuerpo vacio, que parecia decir que ese tramo estaba en blanco. ' +
    'Intercambia los dos numeros.';

  SN_LIST_HIDDEN_FMT =
    '%d entradas no se listan, y no todas por el mismo motivo: %d estan en ' +
    'carpetas de compilacion (Win32, Win64, Debug, Release, dcu, __history), ' +
    '%d son de la fontaneria de git (.git) y %d son copias de la papelera ' +
    '(__delphi-patch). Existen en el disco: para ver las de compilacion pasa ' +
    'esa carpeta como root, o baja el resultado con delphi_package + ' +
    'delphi_fetch; para ver la papelera, includetrash=true.';

  SN_LIST_DEFAULT_MASK =
    'Sin "pattern" solo se listan ficheros de Delphi (*.pas, *.dpr, *.dpk, ' +
    '*.inc, *.dfm, *.fmx, *.dproj, *.groupproj). Si hay .txt, .json, .bat o ' +
    'lo que sea, estan ahi pero no salen: pide pattern=* para verlo todo.';

  SN_LIST_CAPPED =
    'La lista viene recortada a 500 entradas ("total" dice cuantas hay). ' +
    'Acota con pattern (*.pas) o baja a una subcarpeta.';

  SR_LIST_ROOT_IS_FILE_FMT =
    'RECHAZADO: "%s" es un FICHERO, no una carpeta, asi que no hay nada que ' +
    'listar. Para verlo por dentro usa delphi_read; para su carpeta, pasa la ' +
    'carpeta.';

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

  SR_AGENT_CONFINED_FMT =
    'RECHAZADO: el servidor esta en modo confinado y tu (agente "%s") solo ' +
    'puedes ESCRIBIR dentro de tu carpeta <root>\%s\... (o en una carpeta ' +
    'compartida que haya declarado el operador). Leer puedes leerlo todo; ' +
    'escribir, solo lo tuyo. Crea/edita bajo tu carpeta, o pide al operador que ' +
    'marque esa carpeta como compartida.';

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
    'localizalas con vault_search target=files. OJO: el vault que sirve este ' +
    'servidor es el que su operador ha expuesto (VaultRoot del settings.ini), ' +
    'que puede ser una COPIA y no la carpeta viva del usuario: si algo suena ' +
    'desactualizado, preguntalo antes de darlo por bueno.';

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
    #10'--- Mostradas las lineas %d..%d de %d. Pide el resto con ' +
    'vault_read {offset: %d} (y limit si quieres trozos mas pequenos).';

  SR_VAULT_TARGET_FMT =
    'error: target="%s" no existe. Solo hay dos: files (busca en los NOMBRES ' +
    'de las notas, con glob: *.md, *delphi*) y content (busca DENTRO del ' +
    'texto, con expresion regular). Por defecto, files.';

  SR_VAULT_SHOWN_FMT =
    #10'--- Mostradas las lineas %d..%d de %d (hasta el final).';

  SR_VAULT_PAST_END_FMT =
    'error: offset %d mas alla del final: "%s" tiene %d lineas. Pide desde ' +
    'offset=1 o desde una linea que exista.';

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
    'platform - the host must be one the operator allows in [Security] ' +
    'RemoteHosts, because registering a profile IS declaring where this ' +
    'machine may connect) | remove-profile (delete a profile by name; they ' +
    'live outside the workspace, so there is no trash for them) | ' +
    'test-connection (with name: full handshake against that profile; with ' +
    'host+port and no name: raw TCP reachability probe, same host rule) | ' +
    'get-sdk (pull the SDK/sysroot from the PAServer of profile "name" and ' +
    'register it for delphi_build; can take minutes) | remote-run (execute ' +
    '"exe" on the target of profile "name" and return its exit code and ' +
    'output - needs the mcp-runner script installed on the target; see the ' +
    'note it returns; it runs the program THAT PROJECT deployed and nothing ' +
    'else on that machine) | start-runner (start the runner on the target of ' +
    'profile "name" - no shell needed there: PAServer runs the launcher) | ' +
    'install-runner (copy the runner to the target of ' +
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
    '| test-connection | get-sdk | install-runner | start-runner | remote-run';

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
    'Ahora arrancalo con command=start-runner (mismo perfil): no hace falta ' +
    'shell en el destino, PAServer ejecuta el lanzador. El runner crea sus ' +
    'carpetas (jobs, out, done), se queda vigilando y sobrevive a la sesion; ' +
    'despues, remote-run ya funciona.';

  SR_REMOTERUN_START_NOSTATUS =
    'error: el target no devolvio estado del arranque. PAServer esta vivo? ' +
    'Prueba delphi_paserver command=install-runner y repite start-runner.';

  SR_REMOTERUN_START_FAILED_FMT =
    'error: el runner NO arranco en el target. Lo que dijo la maquina: %s -- ' +
    'Comprueba que existe python3 alli y que install-runner dejo ' +
    'mcp-runner.py en _mcp-runner.';

  SN_REMOTERUN_STARTED_FMT =
    'RUNNER EN MARCHA en el target del perfil "%s". Estado que devolvio la ' +
    'maquina: %s -- Ya puedes usar command=remote-run. El runner sobrevive a ' +
    'la sesion (setsid) pero NO a un reinicio del target: si el target se ' +
    'reinicia, vuelve a lanzar start-runner.';

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
    'lista (command=devices los enumera).';

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
    'previa del .deployproj en __delphi-patch. Para desplegar de verdad hace ' +
    'falta un PERFIL DE CONEXION del IDE: delphi_build target=Deploy ' +
    'platform=%s solo funciona si el usuario de este servidor tiene uno ' +
    'configurado (si no, msbuild responde "Missing profile name" hasta en ' +
    'Win32). En remoto, delphi_paserver hace el despliegue de verdad; en ' +
    'local, el .deployproj queda escrito y el IDE lo usara al abrir el ' +
    'proyecto.';

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
    'add-deployfile writes one (with the binary in it) and adds your file. ' +
    'Note that RUNNING a deployment needs an IDE connection profile on this ' +
    'machine: without one, delphi_build target=Deploy fails with "Missing ' +
    'profile name" even for Win32. delphi_paserver is what deploys remotely.';

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

  SN_UNIT_REMOVED_GONE_FMT =
    'QUITADA la unit %s del proyecto %s (%s%s%s). El fichero %s va a la ' +
    'papelera con este mismo borrado. Copias previas en __delphi-patch.';

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

  SR_FILE_DELETE_LOCKED_FMT =
    'NO he borrado "%s" y NO he tocado NADA: algo tiene la carpeta abierta y ' +
    'moverla entera ha fallado (%s). El contenido sigue INTACTO en su sitio; no ' +
    'hay copia a medias en la papelera que pueda confundirte. Suele ser un .exe ' +
    'de un build anterior todavia corriendo, el IDE con el proyecto abierto, o ' +
    'un proceso git. Cierra lo que la bloquea y reintenta. (Yo no mato procesos ' +
    'de esta maquina: puede haber alguien trabajando al otro lado.)';

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
    'add a variant; delete removes a whole style by StyleName (the copy in ' +
    '__delphi-patch is the way back); lint checks the whole thing: ' +
    'duplicated StyleNames, ' +
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
    'RECHAZADO: %s es un estilo BINARIO (el producto de command=build), y ' +
    'este servidor no sabe LEERLO: el formato es un DFM compilado, no texto, ' +
    'asi que no puedo ni listarte sus StyleName. Trabaja sobre el .style de ' +
    'texto del que sale (mismo nombre sin el .bin) y vuelve a ejecutar ' +
    'command=build. Si tu unica copia es el binario, dilo con delphi_report.';

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
    'line - read it then: it may change what you are doing.'#10 +
    'HONESTLY, ABOUT PRIVACY: the box is indexed by the agent id YOU declare, ' +
    'and nothing ties that id to whoever is calling - everyone here shares ' +
    'one token. So anyone using this server can list, and consume, the mail ' +
    'of any id they can guess, and a consumed message does not reach the one ' +
    'it was for (it is still in messages\_entregados, so the operator can ' +
    'put it back). Treat this as a shared noticeboard, not as private post: ' +
    'read YOUR id, and do not go through other people''s. Nothing secret ' +
    'should be sent through here.';

  SN_MESSAGES_PENDING_ALL_FMT =
    #10#10'MENSAJES PENDIENTES: %d para TODOS los agentes (te incluye). ' +
    'Leelos con delphi_messages command=read agent=<tu id>.';

  SN_MESSAGES_PENDING_SOME_FMT =
    #10'(Hay ademas %d mensaje(s) para agentes concretos; si esperas correo: ' +
    'delphi_messages command=check agent=<tu id>.)';

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

  SR_RENAME_HOMONYMS_FMT =
    'Hay %d aparicion(es) del mismo nombre que el motor resuelve a OTRA ' +
    'definicion (mira "lookalikes"). Puede que sean de verdad otra cosa y no ' +
    'haya que tocarlas... o puede que sean ESTA, vista desde un proyecto ' +
    'distinto con otra configuracion: eso es lo que paso en el campo, y el ' +
    'rename dijo que si mientras dejaba un proyecto sin compilar. Mira una ' +
    'por una antes de aplicar nada; "scope" te dice donde he buscado.';

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

  SN_RENAME_QUALIFIED_FMT =
    'La definicion es una cabecera CUALIFICADA ("%s"): al renombrarla cambia ' +
    'SOLO la parte del metodo, nunca el nombre de la clase.';

  SN_RENAME_PREVIEW_NOTE =
    'Preview: NOTHING was written. applicable=true means every occurrence ' +
    'is semantically confirmed and no designer/string/collision hit exists; ' +
    'stage the changes with delphi_changeset (one edit per line, then ' +
    'preview + commit there). applicable=false lists the blockers - fix ' +
    'them or do the rename by hand with the evidence given. Each change ' +
    'carries BOTH line numbers: "line" is 1-based (what delphi_read shows ' +
    'and what delphi_changeset''s atline expects) and "line0" is the ' +
    'language server''s 0-based one. Use "line".';

  // ---- delphi_help ----

  SD_HELP =
    'EL MAPA de este servidor, para no gastar contexto averiguandolo. ' +
    'command=tasks (por defecto) da la tabla tarea -> tool en una linea cada ' +
    'una: que uso para leer, para editar, para compilar, para varios ficheros ' +
    'a la vez, para renombrar, para tests, para desplegar. command=tool ' +
    'name=<tool> da UNA tool entera (descripcion + parametros) sin volver a ' +
    'pedir tools/list, que las trae TODAS de golpe. command=conventions da las ' +
    'reglas que valen para todas: rutas y unidades virtuales, la jaula, como ' +
    'se edita por ancla, las copias de seguridad y los encodings. Empieza ' +
    'por aqui si acabas de conectarte.';

  SP_HELP_COMMAND =
    'tasks (tabla tarea -> tool; por defecto) | tool (una tool entera, con ' +
    '"name") | conventions (las reglas comunes a todas)';

  SP_HELP_NAME =
    'command=tool: nombre de la tool (delphi_edit, o solo "edit")';

  SR_HELP_CMD =
    'error: command debe ser tasks | tool | conventions.';

  SR_HELP_NEED_NAME =
    'RECHAZADO: command=tool necesita "name". Las que hay:';

  SN_HELP_ASSUMED_FMT =
    '(No existe ninguna tool "%s"; he entendido que querias %s, que es la ' +
    'unica que se le parece. Si no era esa, delphi_help command=tasks las ' +
    'lista todas.)';

  SR_HELP_NO_TOOL_ALL_FMT =
    'RECHAZADO: no existe ninguna tool "%s", ni nada que se le parezca. ' +
    'Estas son TODAS las que hay: %s';

  SR_HELP_NO_TOOL_FMT =
    'RECHAZADO: no existe ninguna tool "%s". Se parecen a lo que pides: %s';

  SN_HELP_TOOL_NOTE =
    'Lo que manda es la descripcion de la tool: esta es la misma que sirve ' +
    'tools/list, solo que suelta. Si algo no casa con lo que hace de verdad, ' +
    'dilo con delphi_report: los contratos se corrigen con casos reales.';

  SN_HELP_TASKS =
    'QUE USO PARA CADA COSA (el detalle, en la descripcion de cada tool)'#10 +
    #10 +
    'ORIENTARSE'#10 +
    '  donde estoy, que puedo tocar ....... delphi_workspace'#10 +
    '  que proyectos hay (y su repo/rama) . delphi_projects'#10 +
    '  buscar texto en el codigo .......... delphi_search'#10 +
    '  listar ficheros de una carpeta ..... delphi_list'#10 +
    #10 +
    'LEER Y ENTENDER'#10 +
    '  leer un fichero (o un rango) ....... delphi_read'#10 +
    '  simbolos de una unit ............... delphi_symbols'#10 +
    '  donde se define / donde se usa ..... delphi_definition, delphi_references'#10 +
    '  errores sin compilar ............... delphi_diagnostics'#10 +
    '  que componentes hay instalados ..... delphi_components'#10 +
    #10 +
    'ESCRIBIR'#10 +
    '  cambiar Pascal por ANCLA ........... delphi_edit'#10 +
    '  cambiar texto que no es Pascal ..... delphi_textedit'#10 +
    '  varios ficheros TODO-O-NADA ........ delphi_changeset'#10 +
    '  crear proyecto/unit/form/frame ..... delphi_create'#10 +
    '  borrar / mover un fichero .......... delphi_delete, delphi_move'#10 +
    '  subir un binario o un trozo ........ delphi_upload'#10 +
    '  ver el impacto de un rename ........ delphi_rename_symbol (solo preview)'#10 +
    #10 +
    'PROYECTO'#10 +
    '  framework, plataformas, search path  delphi_config'#10 +
    '  meter/quitar una unit del proyecto . delphi_config add-unit / remove-unit'#10 +
    '  compilar ........................... delphi_build'#10 +
    '  saber si FUNCIONA .................. delphi_test'#10 +
    '  ejecutar aqui ...................... delphi_run (apagado por defecto)'#10 +
    #10 +
    'FORMS Y ESTILOS'#10 +
    '  que publica una clase .............. delphi_designer info / prop'#10 +
    '  revisar un .dfm/.fmx ............... delphi_designer lint / tree / get'#10 +
    '  estilos FMX ........................ delphi_styles'#10 +
    #10 +
    'LLEVARSELO Y DESPLEGAR'#10 +
    '  bajarse un fichero ................. delphi_fetch'#10 +
    '  empaquetar una carpeta ............. delphi_package'#10 +
    '  desplegar y ejecutar en un target .. delphi_paserver, delphi_adb'#10 +
    '  Android ............................ delphi_adb'#10 +
    #10 +
    'GIT Y MEMORIA'#10 +
    '  ramas, commit, diff, stash ......... delphi_git'#10 +
    '  memoria del proyecto ............... vault_read, vault_search'#10 +
    '  escribir en la memoria ............. vault_append, vault_patch, vault_create'#10 +
    #10 +
    'HABLAR CON QUIEN LLEVA EL SERVIDOR'#10 +
    '  contar un fallo o una friccion ..... delphi_report'#10 +
    '  leer lo que te han dejado .......... delphi_messages'#10 +
    #10 +
    'COMO SE LLAMA CADA UNA se responde aqui; COMO SE LLAMA A UNA, con ' +
    'delphi_help command=tool name=<la que sea>, que te da su descripcion ' +
    'entera y TODOS sus parametros. Eso es lo que evita descubrir a golpes ' +
    'que delphi_create acepta "content" con el fuente entero, o que ' +
    'delphi_edit acepta "edits" con varias ediciones de una vez.'#10 +
    #10 +
    'Y las reglas comunes: delphi_help command=conventions.';

  SN_HELP_CONVENTIONS =
    'REGLAS DE LA CASA (valen para todas las tools)'#10 +
    #10 +
    '1. RUTAS. Las unidades del servidor viajan VIRTUALES: srvd:, srvc:... ' +
    'Usalas tal cual en cualquier parametro de ruta; solo existen dentro de ' +
    'este MCP y nunca resuelven en tu disco. Nunca te llegara una letra real.'#10 +
    #10 +
    '2. LA JAULA. Escribir, solo dentro de los "roots" que dice ' +
    'delphi_workspace. Leer, ademas, en la zona de biblioteca (fuentes de la ' +
    'RTL/VCL/FMX, componentes, SDK): mirar si, tocar no. Lo de fuera se ' +
    'rechaza siempre con el motivo.'#10 +
    #10 +
    '3. EDITAR ES POR ANCLA, no por numero de linea. "old" es UNA linea ' +
    'entera, copiada literal de lo que acabas de leer, y tiene que ser unica; ' +
    'si aparece dos veces, acota con "atline". Nunca reescribas un fichero ' +
    'entero para cambiar tres lineas: si el ancla falla, el fichero se queda ' +
    'como estaba y el error te dice por que.'#10 +
    #10 +
    '4. COPIAS. Toda tool que escribe deja copia del original en la papelera ' +
    '__delphi-patch junto al fichero, ANTES de tocarlo, una por dia y fichero ' +
    '(la primera del dia es la original, que es la que vale). Un fichero vivo ' +
    'SIEMPRE pasa por ahi primero: eso es la red. Cuando ya no necesites una ' +
    'copia, delphi_delete con purge=true la borra de verdad, pero SOLO dentro ' +
    'de la papelera y solo la TUYA (ver regla 12).'#10 +
    #10 +
    '5. ENCODING Y FINALES DE LINEA se respetan como estan. No conviertas un ' +
    'fichero de paso; si necesitas un caracter que no cabe en su codepage, ' +
    'usa el literal Pascal (#$2714) FUERA de las comillas, concatenado.'#10 +
    #10 +
    '6. VARIOS FICHEROS A LA VEZ: delphi_changeset. Apila (stage), mira ' +
    '(preview), aplica (commit). O entra todo o no entra nada, y si algo ' +
    'falla a mitad se deshace lo ya hecho. unstage quita una operacion suelta.'#10 +
    #10 +
    '7. QUE COMPILE NO ES QUE FUNCIONE: delphi_build dice "0 errores", ' +
    'delphi_test dice "17 pasan, 1 falla". Termina por el segundo.'#10 +
    #10 +
    '8. UN ERROR PARE A LOS DEMAS. En un build fallido empieza por ' +
    '"firstError": lo de detras suele ser su sombra.'#10 +
    #10 +
    '9. EJECUTAR ES OPCIONAL Y ESTA APAGADO salvo que el operador lo ' +
    'encienda (AllowRun, AllowTests, AllowRemoteRun). Si te lo rechaza, no ' +
    'insistas: dilo con delphi_report y sigue con otra cosa.'#10 +
    #10 +
    '10. EL BUZON ES UN TABLON, NO CORREO PRIVADO. Se indexa por el id que ' +
    'declaras tu, y todos los que trabajais aqui compartis el mismo token: ' +
    'cualquiera puede leer, y CONSUMIR, el correo de un id que adivine. Lee ' +
    'el tuyo y no hurgues en el de otros; el operador no manda nada secreto ' +
    'por aqui, y tu tampoco.'#10 +
    #10 +
    '11. COMO LEER UNA NEGATIVA. "RECHAZADO:" = te lo he denegado a ' +
    'proposito y el motivo va detras: no insistas, cambia de camino. ' +
    '"error:" = no he podido (no existe, no cuadra, falta un parametro): ' +
    'corrige y repite. "Error executing tool:" = me he roto yo por dentro; ' +
    'eso SIEMPRE es un fallo mio, cuentalo con delphi_report.'#10 +
    #10 +
    '12. QUIEN ERES. Te identificas UNA VEZ, en el handshake, con ' +
    'clientInfo.name; el servidor lo ata a tu sesion y a partir de ahi sabe ' +
    'quien eres en cada peticion sin que lo repitas. Con eso: delphi_messages ' +
    'lee TU correo sin teclear el id, y lo que TU mandas a la papelera solo ' +
    'lo purgas tu (otro agente que lo intente se lleva un RECHAZADO). No es ' +
    'una contrasena -el token es comun a todos-, pero para hacerse pasar por ' +
    'ti hay que robarte la sesion, no basta con escribir tu nombre. Trabaja ' +
    'en TU carpeta de proyecto y no pisaras a nadie.'#10 +
    #10 +
    '13. SI ALGO NO SE PUEDE HACER POR AQUI, ESO ES UN HALLAZGO. Cuentalo con ' +
    'delphi_report (kind=limitation) con la llamada exacta y lo que ' +
    'esperabas: este servidor se ha hecho entero con esos informes.';

  // ---- delphi_test ----

  SD_TEST =
    'TESTS: la diferencia entre "compila" y "funciona". command=discover ' +
    'path=<carpeta o proyecto> lista los proyectos de test que hay debajo ' +
    '(un .dpr que use DUnitX, o uno de consola cuyo nombre diga test/spec). ' +
    'command=run project=<.dproj del test> compila y ejecuta ese runner y ' +
    'devuelve el resultado ESTRUCTURADO: total, passed, failed, la lista de ' +
    'fallos, exitCode, duracion y la cola de lo que imprimio. Entiende dos ' +
    'dialectos: el resumen de DUnitX y la convencion PASS/FAIL + ExitCode de ' +
    'un runner de consola escrito a mano. El veredicto dice de donde sale ' +
    '(verdictFrom: counts o exitCode) y nunca se lo inventa. Ejecutar tests ' +
    'es EJECUTAR: tiene su propio interruptor [Security] AllowTests (o ' +
    'AllowRun, que lo implica); el binario se compila aqui, sale de un ' +
    'proyecto de la jaula y corre en el mismo sandbox de baja integridad que ' +
    'delphi_run, con timeout. Sin ese interruptor, discover funciona y run ' +
    'se rechaza.';

  SP_TEST_COMMAND =
    'discover (listar proyectos de test bajo "path") | run (compilar y ' +
    'ejecutar el de "project"). Por defecto: discover';

  SP_TEST_PATH =
    'discover: carpeta (o proyecto) bajo la que buscar proyectos de test';

  SP_TEST_PROJECT =
    'run: el .dproj (o .dpr) del proyecto de test a ejecutar';

  SP_TEST_CONFIG =
    'run: configuracion a compilar y ejecutar (Debug por defecto)';

  SP_TEST_FILTER =
    'run opcional: filtro de tests para frameworks que lo admiten (DUnitX ' +
    '--run:); un runner de consola a mano lo ignora';

  SP_TEST_TIMEOUT =
    'run opcional: milisegundos maximos de ejecucion (120000 por defecto, ' +
    'maximo 600000). Un test que se cuelga se corta y se dice';

  SP_TEST_NOBUILD =
    'run opcional: true = NO compilar antes, ejecutar el binario que ya ' +
    'existe. Por defecto se compila (ejecutar un binario viejo es mentir)';

  SP_TEST_PLATFORM =
    'run opcional: plataforma a compilar y ejecutar (Win64 por defecto). ' +
    'Solo plataformas de ESTA maquina: el binario corre aqui';

  SR_TEST_PLATFORM_UNKNOWN_FMT =
    'RECHAZADO: "%s" no es una plataforma de Delphi. Antes te la aceptaba y ' +
    'ejecutaba Win64 sin decir nada. Validas para ejecutar aqui: Win32 y ' +
    'Win64.';

  SR_TEST_NOBINARY_NOBUILD =
    'error: me pediste nobuild=true (no compilar) y ahi no hay ningun ' +
    'binario que ejecutar. O compilas antes (quita nobuild, o delphi_build ' +
    'con esa MISMA plataforma y config), o apuntas a la config que si tiene ' +
    'binario.';

  SN_TEST_STALE_FMT =
    'OJO: %s es MAS NUEVO que el binario que acabo de ejecutar. Has tocado ' +
    'el codigo despues de compilarlo, asi que estos numeros son de la ' +
    'version anterior. Quita nobuild=true y vuelve a lanzarlo.';

  SN_TEST_NEAR_MISS_FMT =
    'OJO: hay %d linea(s) que PARECEN un resultado y NO he contado, la ' +
    'primera es "%s". Mira el formato en command=discover ("countsFormat"): ' +
    'la primera palabra tiene que ser PASS/PASSED/OK o FAIL/FAILED/ERROR. Si ' +
    'esas lineas eran fallos tuyos, el veredicto de arriba se queda corto.';

  SR_TEST_NAME_NOT_PATH_FMT =
    'RECHAZADO: "%s" parece el NOMBRE del proyecto, y aqui hace falta su ' +
    'RUTA completa (la que te da delphi_projects en el campo "project"). ' +
    'Antes esto te contestaba que estaba fuera de los workspaces permitidos, ' +
    'que es verdad de cualquier nombre suelto y no aclaraba nada.';

  SR_TEST_CONFIG_FMT =
    'RECHAZADO: la configuracion "%s" no existe en este proyecto. Tiene ' +
    'estas: %s. (Antes te la aceptaba y compilaba en una carpeta con ese ' +
    'nombre, que no es lo que querias.)';

  SR_TEST_PLATFORM_FMT =
    'RECHAZADO: %s no se puede EJECUTAR en esta maquina, y ejecutar es de lo ' +
    'que va esta tool. Compila para esa plataforma con delphi_build y ' +
    'llevatelo con delphi_paserver / delphi_adb.';

  SN_TEST_TIMEOUT_NOTE =
    'SE ACABO EL TIEMPO y he MATADO el proceso: no es que los tests fallen, ' +
    'es que no terminaron. Por eso exitCode viene a 1. Los numeros que veas ' +
    'son los de lo que alcanzo a imprimir ANTES de morir, asi que estan ' +
    'incompletos aunque parezcan buenos: no los tomes por el resultado. Y si ' +
    '"outputTail" viene vacio es porque la salida de un programa de consola ' +
    'se guarda en un buffer y solo se vuelca al terminar, asi que al matarlo ' +
    'se pierde; con Flush(Output) despues de cada linea la veras. Si esperas ' +
    'que tarde, sube "timeoutms".';

  SN_TEST_NO_COUNTS_FAILED_FMT =
    'FALLO. No he sabido contar los tests (el runner no imprime un formato ' +
    'que yo entienda), pero ha devuelto codigo de salida %d, y eso es el ' +
    'propio runner diciendo que algo ha ido mal: NO lo des por bueno. Mira ' +
    'outputTail para ver que fallo, y si quieres el recuento pasa ' +
    'countsFormat (primera palabra PASS/OK/FAIL/ERROR por linea).';

  SN_TEST_NO_COUNTS =
    'Ha terminado bien pero NO he sabido contar ni un solo test, asi que no ' +
    'te digo "pass": que un binario acabe con exitCode 0 no demuestra que ' +
    'haya probado nada. O el proyecto no ejecuta tests, o su salida no sigue ' +
    'ninguno de los dos formatos que se leer (mira "countsFormat" en ' +
    'command=discover).';

  SN_TEST_CONSOLE_FORMAT =
    'Para que pueda contarte los tests, imprime UNA LINEA POR COMPROBACION ' +
    'cuya PRIMERA PALABRA sea PASS, PASSED u OK cuando va bien, y FAIL, ' +
    'FAILED o ERROR cuando va mal, seguida de la descripcion: "PASS suma de ' +
    'dos enteros" / "FAIL email invalido: esperaba False". Mayusculas o ' +
    'minusculas da igual, y los espacios de delante tampoco importan; lo que ' +
    'tiene que ser exacto es la PALABRA: "PASSABLE" no cuenta (no es PASS), y ' +
    '"[ OK ] 12 algo" tampoco (empieza por corchete). Si imprimes lineas que ' +
    'se le parecen y no cuentan, te lo digo en "linesNotCounted". Y termina ' +
    'con ExitCode distinto de 0 si algo fallo. Con DUnitX no hace falta nada ' +
    'de esto: se lee su resumen.';

  SN_TEST_RUNS_ON =
    'command=run compila Y ejecuta la MISMA plataforma: Win64 salvo que ' +
    'pases platform=. Ojo si compilaste a mano con delphi_build, que por ' +
    'defecto usa Win32: son binarios distintos. El programa corre en su ' +
    'propia carpeta de salida y con ella como directorio actual; ESA carpeta ' +
    'es el unico sitio donde puede ESCRIBIR (el sandbox de baja integridad ' +
    'le niega %TEMP% y el resto del disco). Si tus tests tocan ficheros, ' +
    'usalos con rutas RELATIVAS.';

  SN_TEST_NOBUILD_NOTE =
    'nobuild=true: NO he compilado nada, he ejecutado el binario que ya ' +
    'estaba ahi ("builtAt" dice de cuando es). Si has tocado el codigo ' +
    'despues de esa fecha, estos numeros son de otro programa.';

  SR_TEST_CMD =
    'error: command debe ser discover | run';

  SR_TEST_NEED_PATH =
    'RECHAZADO: discover necesita "path" (la carpeta o el proyecto bajo el ' +
    'que buscar).';

  SR_TEST_NEED_PROJECT =
    'RECHAZADO: run necesita "project" (el .dproj del proyecto de test). ' +
    'command=discover te los lista.';

  SR_TEST_NOPATH_FMT =
    'RECHAZADO: no existe %s.';

  SR_TEST_NOTATEST_FMT =
    'RECHAZADO: %s no parece un proyecto de test. Cuenta como tal un .dpr ' +
    'que use DUnitX, o uno con {$APPTYPE CONSOLE} cuyo nombre diga ' +
    'test/tests/spec. Si el tuyo lo es y no lo detecto, dilo con ' +
    'delphi_report: el criterio se afina con casos reales.';

  SR_TEST_NOBINARY =
    'error: no encuentro el binario del proyecto de test despues de ' +
    'compilar. Compila a mano con delphi_build y mira que declara en ' +
    '"output".';

  SR_TEST_DISABLED =
    'RECHAZADO: ejecutar tests esta APAGADO en este servidor. El operador lo ' +
    'enciende con [Security] AllowTests=1 en el settings.ini junto al ' +
    'ejecutable (o DELPHI_MCP_ALLOW_TESTS=1) y reinicia. Es un interruptor ' +
    'propio, separado de AllowRun a proposito: permitir una bateria de tests ' +
    'no es lo mismo que permitir ejecutar binarios cualesquiera (AllowRun, ' +
    'si esta encendido, ya lo implica). command=discover si funciona sin el.';

  SN_TEST_NONE =
    'No hay proyectos de test ahi debajo. Cuenta como tal un .dpr con DUnitX ' +
    'o uno de consola cuyo nombre diga test/spec.';

  SN_TEST_DISCOVER_NOTE =
    'Ejecutalos con command=run project=<el .dproj de la lista>. Si alguno ' +
    'trae hasDproj=false, compilalo antes con delphi_build sobre su .dpr.';

  SN_TEST_BUILD_FAILED =
    'El proyecto de test NO compila, asi que no hay nada que ejecutar: mira ' +
    '"build.errors" (y "missingUnits" si falta alguna unidad). Arregla eso ' +
    'primero.';

  SN_TEST_RUN_NOTE =
    'result=pass|fail sale de "verdictFrom": counts (los numeros del ' +
    'framework) o exitCode (0 = verde) cuando el runner no da numeros; ' +
    'result=timeout es que lo mate por tiempo y result=no-tests es que ' +
    'termino bien sin que yo pudiera contar nada. failures lista las lineas ' +
    'de fallo tal cual las imprimio. Corrio en sandbox de baja integridad, ' +
    'con timeout, en su carpeta de salida, que es lo unico donde puede ' +
    'escribir.';

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
    'lint (designer lint on demand) | check-binding (does the .dfm agree ' +
    'with the class in the .pas: components with no published field, events ' +
    'naming a method that is not published, published fields with no ' +
    'component, duplicate names - all of which COMPILE and then throw when ' +
    'the form is created) | layout (WHERE things end up on a VCL .dfm: ' +
    'resolves Align and returns the resolved rectangle of every control plus ' +
    'controls of size zero, outside their container, overlapping, or clipped ' +
    'by the bands around them - a form can bind perfectly and still be ' +
    'unusable). Default: info';

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
    'error: command debe ser info | prop | tree | get | lint | check-binding | layout';

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

  // ---- delphi_git: ramas ----

  SR_BUILD_INCLUDE_OUTSIDE_FMT =
    'RECHAZADO: no compilo esto. La directiva %s de %s mete en la ' +
    'compilacion un fichero que esta FUERA de lo que este servidor deja ' +
    'leer. El compilador lo abre con los permisos del servidor, y lo que ' +
    'entra vuelve a salir por dos sitios: dentro del binario (que luego se ' +
    'descarga) y citado palabra por palabra en los errores cuando el fichero ' +
    'no es Pascal. Las rutas de {$I} y {$R} tienen que quedarse dentro del ' +
    'workspace.';

  SN_BUILD_LOCKED_OUTPUT =
    'F2039 "Could not create output file" casi nunca es un fallo de tu ' +
    'codigo: el binario que este build quiere escribir esta ABIERTO. Suele ' +
    'ser la ejecucion anterior todavia viva, el IDE con el proyecto abierto o ' +
    'un depurador enganchado. Espera a que termine lo que este corriendo y ' +
    'repite; si es delphi_test quien lo dejo colgado, tiene timeout y se mata ' +
    'solo. Yo NO mato procesos de esta maquina: puede haber alguien ' +
    'trabajando con el IDE al otro lado.';

  SN_BUILD_DEFAULT_PLATFORM =
    'No me diste "platform", asi que he compilado Win32, que es el defecto de ' +
    'esta tool. OJO: delphi_test ejecuta Win64 por defecto, asi que si vas a ' +
    'pasar los tests despues, compila Win64 (platform=Win64) o dejale a ' +
    'delphi_test que compile el solo.';

  SN_BUILD_QUEUED =
    'Este build ha esperado su turno: el servidor compila DE UNO EN UNO ' +
    'porque dos msbuild simultaneos se pisan los .dcu, los outputs y el ' +
    '.deployproj. "queuedMs" es lo que esperaste en cola, no lo que ' +
    'tardo el compilador.';

  SN_BUILD_FIRST_ERROR =
    'Empieza por "firstError": un solo error puede parir a los demas. Un ' +
    'E2009 (asignar un procedimiento suelto a un evento) provoca detras ' +
    'siete E2250 de Synchronize/Queue que parecen un problema de hilos y no ' +
    'lo son. Arregla el primero y vuelve a compilar antes de tocar nada mas.';

  SN_LINT_UNKNOWN_CLASS_FMT =
    '"%s" no esta en la tabla %s de este servidor (sera de un paquete de ' +
    'terceros, o no existe). No es un error por si mismo, pero NO he revisado ' +
    'ninguna propiedad de ese objeto ni de lo que lleva dentro.';

  SP_DESIGNER_UNIT =
    'check-binding opcional: el .pas con la clase del form. Por defecto, el ' +
    'que se llama igual que el .dfm.';

  SR_DESIGNER_NO_FORM_FMT =
    'RECHAZADO: no existe el fichero de form %s.';

  SR_DESIGNER_NO_UNIT_FMT =
    'RECHAZADO: no encuentro la unit del form (%s). Si se llama de otra ' +
    'forma, pasala en "unit".';

  SN_DESIGNER_LAYOUT_OK =
    'La geometria CUADRA: nada mide cero, nada se sale de su contenedor, ' +
    'nada se solapa y a todos los alineados les queda hueco. Eso es lo que ' +
    'no se ve desde aqui: un form puede enlazar perfecto y ser una pila de ' +
    'controles unos encima de otros.';

  SN_DESIGNER_LAYOUT_BAD =
    'OJO: esto CARGA pero no se ve como crees. Nada de lo de abajo lo dice ' +
    'el compilador ni el enlazador: un control de tamano cero esta ahi y no ' +
    'se ve, uno que se sale del contenedor aparece recortado, y dos que se ' +
    'solapan hacen que el de arriba tape al de abajo. Arreglalo antes de ' +
    'dar el formulario por bueno.';

  SN_DESIGNER_LAYOUT_HOW =
    'Como lo mido: resuelvo Align como TWinControl.AlignControls (cada ' +
    'alineado se come su banda del hueco que queda, en orden del .dfm), con un ' +
    'detalle clave: alClient NO recorta el rectangulo, asi que dos alClient ' +
    'reciben el hueco ENTERO y se tapan al 100%. Aplico el Align por defecto de ' +
    'la clase cuando el .dfm no lo escribe (TStatusBar=alBottom, TToolBar=alTop, ' +
    'TSplitter=alLeft, TTabSheet=alClient...). Salto lo invisible (Visible= ' +
    'False), no juzgo los hijos de un TGridPanel (van por celdas) ni trato un ' +
    'TBevel/TShape/TImage como que tapa a nadie (es decoracion), y un TScrollBox ' +
    'puede tener el contenido mas grande a proposito. En "boxes" te doy el ' +
    'rectangulo resuelto de cada control en coordenadas del form: eso es donde ' +
    'acaba cada cosa, para colocar la siguiente sin ver la pantalla. Es ' +
    'aproximado: el area util de un contenedor la tomo como su Width/Height, y ' +
    'Anchors (que gobiernan el REDIMENSIONADO) no es lo que mido.';

  SN_COMPLETION_SNAPPED_FMT =
    'He ajustado la posicion de la columna %d a la %d: pediste completion de ' +
    'miembro (trigger ".") pero la columna caia sobre el identificador, no ' +
    'DESPUES del punto. "despues de Foo." es la columna del punto + 1; sobre el ' +
    'nombre, el LSP te devuelve el ambito global entero. Estos son los miembros ' +
    'del tipo.';

  SR_DESIGNER_LAYOUT_FMX =
    'RECHAZADO: command=layout es solo para .dfm (VCL). Un .fmx coloca con otro ' +
    'modelo (Size.Width, Position.X, Align distinto) que este servidor todavia ' +
    'no resuelve; contestar "ok" sobre un .fmx seria mentir. Para .fmx usa de ' +
    'momento tree/get/lint.';

  SR_DESIGNER_LAYOUT_TRUNC =
    'OJO: el .dfm parece TRUNCADO (hay mas objetos abiertos que "end" que los ' +
    'cierran). Lo que te diga de la geometria puede estar incompleto: revisa ' +
    'que el fichero termina en el "end" del form.';

  SN_DESIGNER_LAYOUT_ESTIMATED =
    'OJO: el form no trae ClientWidth/ClientHeight, solo Width/Height (el tamano ' +
    'de la VENTANA). He restado un marco nominal a 96 dpi para estimar el area ' +
    'util; cerca del borde derecho o inferior el recorte real puede variar unos ' +
    'pixeles segun el BorderStyle.';

  SR_DESIGNER_BINDING_NOT_FORM =
    'RECHAZADO: check-binding compara un FORM con su clase, asi que "path" ' +
    'tiene que ser el .dfm/.fmx. La unit va en "unit" (y si se llama igual ' +
    'que el form no hace falta pasarla).';

  SR_DESIGNER_BINDING_UNIT_EXT =
    'RECHAZADO: "unit" tiene que ser un .pas. Esta tool lee la clase del ' +
    'form, no cualquier fichero de texto.';

  SR_DESIGNER_BINDING_NO_ROOT =
    'RECHAZADO: este fichero no empieza por un objeto de designer ("object ' +
    '<Nombre>: <TClase>"), asi que no es un form que yo pueda comparar.';

  SN_DESIGNER_BINDING_NOCLASS_FMT =
    'OJO: el .dfm dice que este form es de clase %s, pero esa clase NO esta ' +
    'declarada en %s. O el .dfm apunta a otra unit, o la clase se renombro ' +
    'solo en un sitio. No comparo nada mas hasta que eso cuadre: seria ' +
    'inventarme el resultado.';

  SN_DESIGNER_BINDING_PARTIAL_FMT =
    'PARCIAL: la herencia sale de esta unit (%s), asi que los componentes y ' +
    'metodos heredados no los veo desde aqui. Lo que te digo que SOBRA o que ' +
    'FALTA seria mentira, asi que no lo listo; si te sale ok:true, leelo ' +
    'como "no he encontrado nada malo en lo que SI puedo ver". Para revisar ' +
    'lo heredado, pasa check-binding tambien al form padre.';

  SN_DESIGNER_BINDING_OK =
    'El form y su clase CUADRAN: cada objeto del .dfm tiene su campo ' +
    'publicado, cada evento apunta a un metodo que existe, y no sobra ningun ' +
    'campo. Eso es lo que el compilador NO comprueba: un desajuste aqui ' +
    'compila igual y revienta al crear la ventana.';

  SN_DESIGNER_BINDING_BAD =
    'OJO: el .dfm y la clase NO cuadran. Esto compila igual y falla al CREAR ' +
    'el form, en ejecucion, con un mensaje que no senala aqui. Un objeto sin ' +
    'campo publicado llega a nil; un evento cuyo metodo no existe hace que ' +
    'el form no cargue. Arregla los tres listados antes de dar nada por ' +
    'bueno.';

  SN_DESIGNER_SET_NOTE =
    'Es un SET: en el .dfm/.fmx se escribe entre corchetes y separado por ' +
    'comas, [goEditing, goTabs], y vacio es [].';

  SR_PACKAGE_NEED_DIR =
    'error: delphi_package necesita "dir" (la carpeta a comprimir).';

  SP_FETCH_MAXBYTES =
    'OJO: pedir maxbytes<=1048576 (1 MB) FUERZA trozos base64 inline - justo ' +
    'lo contrario de lo que quieres con un fichero grande. Para un download ' +
    'grande OMITE este parametro: por encima de 4 MB la respuesta trae el ' +
    'ENLACE de descarga y ningun trozo inline ("inline":false, "bytes":0), ' +
    'que es lo barato. maxbytes solo ajusta el tamano de trozo (tope 8388608) ' +
    'cuando el contenido va inline.';

  SR_STYLES_VALUE_GRAMMAR_FMT =
    'RECHAZADO: "%s" no es un valor que un .style pueda guardar. Un fichero ' +
    'de estilos es un DFM de texto: numero (12, -3.5), color en hexadecimal ' +
    '($FF2A2A2A), identificador (claRed, True, TAlignLayout.Top), texto entre ' +
    'comillas simples (''Aceptar'') o conjunto ([a, b]). Si lo escribo tal ' +
    'cual, el fichero deja de poder leerse y solo te enterarias en ' +
    'command=build.';

  SR_STYLES_RENAME_EMPTY =
    'RECHAZADO: StyleName vacio. Un estilo sin nombre no lo encuentra nadie.';

  SR_STYLES_RENAME_DUP_FMT =
    'RECHAZADO: en ese fichero ya hay un estilo llamado "%s". Dos estilos con ' +
    'el mismo StyleName es justo lo que caza el lint, y a partir de ahi ' +
    'delete/get trabajan con el primero que encuentran. Elige otro nombre.';

  SN_STYLES_RENAMED_FMT =
    'RENOMBRADO el estilo "%s" a "%s" en %s. OJO: los StyleLookup de tus ' +
    '.fmx que apuntaban al nombre viejo ya no encuentran nada; pasa ' +
    'command=lint para ver cuales.';

  SN_CONFIG_PLAT_ALREADY_FMT =
    'La plataforma %s YA estaba deshabilitada: no he tocado nada (ni copia de ' +
    'seguridad, que seria de un fichero identico). add-platform la reactiva.';

  SR_CONFIG_PLAT_LAST_FMT =
    'RECHAZADO: %s es la ULTIMA plataforma habilitada del proyecto y un ' +
    'proyecto sin ninguna no se puede compilar desde el IDE. Habilita antes ' +
    'otra con add-platform y luego quita esta.';

  SR_CONFIG_OUTPUT_INVALID =
    'RECHAZADO: eso no vale como carpeta de salida. Tiene que ser un nombre ' +
    'RELATIVO y simple, como Compiled o bin\out: sin unidad ni ruta ' +
    'absoluta, sin ".." y sin caracteres especiales (los espacios si valen). ' +
    'Con ' +
    'output=default se restaura el reparto estandar de RAD Studio.';

  SN_CONFIG_DPR_ONLY =
    'Esto es el .dpr y a su lado no hay .dproj, asi que solo puedo decirte ' +
    'sus UNITS. El framework (VCL/FMX), las plataformas, las configuraciones, ' +
    'los search path y el despliegue viven en el .dproj: no los se, y no me ' +
    'los invento. add-unit y remove-unit si funcionan aqui; el resto de ' +
    'comandos necesitan un .dproj.';

  SR_CONFIG_NO_DPROJ_FMT =
    'RECHAZADO: %s es el .dpr (el fuente), y la configuracion del proyecto ' +
    '(framework, plataformas, rutas de busqueda, salida) vive en el .dproj. ' +
    'Ahi al lado no hay ningun %s. Si el proyecto no tiene .dproj, este ' +
    'servidor no puede configurarlo: creale uno con delphi_create o abrelo ' +
    'una vez en el IDE. (add-unit y remove-unit si funcionan sobre el .dpr.)';

  SR_CREATE_BADNAME_FMT =
    'RECHAZADO: "%s" no es un identificador Pascal valido. Un nombre de unit ' +
    'es Letra/_ seguido de letras, digitos o _, con puntos entre segmentos si ' +
    'quieres espacio de nombres (MiApp.Datos.Clientes).';

  SR_CREATE_RESERVED_FMT =
    'RECHAZADO: "%s" es una palabra reservada de Delphi, asi que "%s" no ' +
    'puede llamarse asi: en cuanto entre en el uses del .dpr el compilador ' +
    'da E2029 y detras van 15 errores en cascada que no apuntan aqui. ' +
    'Ponle un prefijo (UBegin, MiApp.Begin no vale tampoco: el segmento debe ' +
    'ser limpio).';

  SR_CREATE_RTLNAME_FMT =
    'RECHAZADO: "%s" es el nombre de una unit de la RTL/VCL. Un fichero con ' +
    'ese nombre junto al proyecto SECUESTRA a la de verdad y los errores que ' +
    'salen luego apuntan a cualquier sitio menos a esto. Ponle un prefijo ' +
    'tuyo (U%s) o un espacio de nombres TUYO (MiApp.%s): lo que no vale es ' +
    'colgarlo de uno de Embarcadero (System., Vcl., FMX., Data...).';

  SR_CREATE_RTLNS_FMT =
    'RECHAZADO: "%s" cuelga de "%s", que es un espacio de nombres de ' +
    'Embarcadero. Crear ahi una unit tuya secuestra a la del compilador ' +
    'exactamente igual que usar el nombre a secas: en cuanto exista, la suya ' +
    'deja de encontrarse y el error que ves es que ha desaparecido algo tan ' +
    'basico como Exception. Usa un espacio de nombres tuyo (MiApp.%s no, ' +
    'pero MiEmpresa.MiApp.LoQueSea si).';

  SR_CREATE_PROJECT_KIND =
    'RECHAZADO: de proyectos solo se yo hacer tres: kind=project-console, ' +
    'kind=project-vcl y kind=project-fmx. (Y luego form-vcl, form-fmx, ' +
    'frame-vcl, frame-fmx, datamodule y unit, que van DENTRO de un proyecto ' +
    'que ya existe.)';

  SR_CREATE_NEED_DIR =
    'RECHAZADO: falta "dir", la carpeta donde crear el proyecto. Debe estar ' +
    'dentro del workspace; delphi_workspace te dice cual es.';

  SR_CREATE_CLASH_FMT =
    'RECHAZADO: ahi ya hay un %s (en %s) y el scaffolder jamas sobreescribe. ' +
    'No he creado NADA: %s sigue sin existir. Un proyecto nuevo quiere su ' +
    'propia carpeta; pon "dir" en una subcarpeta.';

  SN_CREATE_CONSOLE_FORM =
    'OJO: ese proyecto es de CONSOLA (no usa Vcl.Forms ni FMX.Forms), asi que ' +
    'el form entra y compila pero no lo va a ver nadie: no hay Application ' +
    'que lo cree ni bucle de mensajes que lo muestre. Si de verdad quieres ' +
    'convertirlo en una aplicacion con ventana, hace falta cambiar el .dpr ' +
    '(uses del framework, Application.Initialize/CreateForm/Run) y quitar el ' +
    '{$APPTYPE CONSOLE}.';

  SR_CREATE_FRAMEWORK_FMT =
    'RECHAZADO: pides un %s pero %s es un proyecto %s. Mezclarlos compila mal ' +
    'y tarde: el form iria con su Application.CreateForm a un .dpr que usa el ' +
    'otro framework. Usa el kind que toca, o crea el form en un proyecto de ' +
    'su tipo.';

  SR_CREATE_CONTENT_NOUNIT =
    'RECHAZADO: el "content" que mandas no empieza por "unit <nombre>;", asi ' +
    'que no es una unit de Pascal. Manda el fuente COMPLETO (unit / ' +
    'interface / implementation / end.) o no mandes content y te dejo el ' +
    'esqueleto vacio.';

  SR_CREATE_CONTENT_NAME_FMT =
    'RECHAZADO: el fuente dice "unit %s" pero el fichero se llamaria %s.pas. ' +
    'Delphi exige que coincidan. Corrige uno de los dos.';

  SR_CREATE_CONTENT_NOEND =
    'RECHAZADO: el "content" no termina en "end." - parece cortado. Manda la ' +
    'unit entera; si es larga, usa delphi_upload por trozos y luego ' +
    'delphi_config command=add-unit para registrarla.';

  SR_CHANGESET_VIRT_MISSING_FMT =
    'RECHAZADO: no existe %s, ni lo crea ninguna operacion anterior de esta ' +
    'misma tanda. Si lo va a crear una posterior, ordena las operaciones: se ' +
    'aplican en el orden en que las apilas.';

  SR_CHANGESET_VIRT_EXISTS_FMT =
    'RECHAZADO: %s ya existe (create jamas sobreescribe). Si lo que quieres ' +
    'es rehacerlo entero, apila primero kind=delete de ese mismo fichero y ' +
    'luego el create: la tanda cuenta con lo que apilas, no solo con el disco.';

  SR_CHANGESET_VIRT_DEST_FMT =
    'RECHAZADO: el destino %s ya existe (o lo crea una operacion anterior de ' +
    'esta tanda). Elige otro nombre o borra ese primero.';

  SR_CHANGESET_UNSTAGE_N_FMT =
    'RECHAZADO: n=%d no vale; hay %d operaciones apiladas. Usa el numero que ' +
    'te da command=preview, o n=0 para quitar la ultima.';

  SN_CHANGESET_UNSTAGED_FMT =
    'Quitada la operacion %d (%s %s). Quedan %d apiladas. Nada se ha tocado ' +
    'en disco: la tanda sigue viva.';

  SN_CHANGESET_PREVIEW_VIRTUAL =
    'Ese fichero todavia no existe: lo crea una operacion anterior de esta ' +
    'misma tanda, asi que el ancla no se puede comprobar hasta el commit. Si ' +
    'falla, el commit deshace la tanda entera como siempre.';

  SR_UPLOAD_OFFSET_INSIDE_FMT =
    'RECHAZADO: offset %d cae DENTRO del fichero (tiene %d bytes) y escribir ' +
    'ahi se llevaria por delante todo lo que viene detras, sin copia ' +
    'recuperable. Para continuar una subida a trozos, el offset es el FINAL ' +
    'actual: usa offset=%d. Para reemplazar el fichero entero, offset=0 (esa ' +
    'si deja copia).';

  SR_UPLOAD_BINARY_DESIGNER =
    'RECHAZADO: eso es un .dfm/.fmx BINARIO (firma TPF0 o envoltorio de ' +
    'recurso $FF) y este servidor no interpreta designers binarios: si lo ' +
    'subes, ninguna tool de aqui podra volver a leerlo ni arreglarlo, y si ' +
    'encima pisa un designer de texto vivo te quedas sin el original legible. ' +
    'Sube el designer como TEXTO (empieza por "object <Nombre>: <TClase>").';

  SR_UPLOAD_BAD_SHA_FMT =
    'RECHAZADO: "%s" no tiene forma de sha256 (son 64 digitos hexadecimales). ' +
    'No he subido nada. Antes daba la subida por mala y apartaba el fichero ' +
    'como .corrupto, castigando al fichero por un error del parametro.';

  SR_UPLOAD_NO_CHUNK_FMT =
    'RECHAZADO: no mandas "chunkbase64", asi que no hay nada que subir, y ahi ' +
    'ya hay un fichero de %d bytes. Una llamada a medias NO lo vacia. Si ' +
    'quieres reemplazarlo, manda su contenido en base64; si quieres borrarlo, ' +
    'delphi_delete.';

  SR_UPLOAD_NO_CHUNK_NEW =
    'RECHAZADO: falta "chunkbase64", el contenido en base64. Para un fichero ' +
    'de texto vacio o con contenido, delphi_create / delphi_edit son mejor ' +
    'herramienta; delphi_upload es para binarios y para trozos.';

  SR_UPLOAD_SHA_MISMATCH_FMT =
    'el sha256 NO coincide: lo ensamblado difiere del origen, asi que NO lo ' +
    'dejo publicado con su nombre. Lo he apartado en %s. Reenvia desde ' +
    'offset=0.';

  SN_UPLOAD_REPLACED_FMT =
    'OJO: ahi ya habia un fichero (%d bytes) y esta subida lo ha SUSTITUIDO ' +
    'entero. La copia del contenido anterior esta en "backup" (papelera ' +
    '__delphi-patch junto al fichero, una por dia: si ya habias sustituido ' +
    'ese fichero hoy, la copia que hay es la ORIGINAL de esta manana, que es ' +
    'la que vale). Si querias anadir al final y no reemplazar, usa offset=<el ' +
    'tamano actual>, no offset=0.';

  SP_DELETE_PURGE =
    'true = BORRAR DE VERDAD, sin vuelta atras. Solo vale DENTRO de la ' +
    'papelera (__delphi-patch): sirve para limpiar tus propias copias cuando ' +
    'ya no las necesitas, no para saltarte la papelera. Un fichero vivo ' +
    'siempre pasa por ella primero, y eso no se puede desactivar.';

  SR_FILE_PURGE_ONLY_TRASH =
    'RECHAZADO: purge=true solo se puede usar DENTRO de la papelera ' +
    '(__delphi-patch). Para un fichero vivo, borralo normal: va a la ' +
    'papelera, y si de verdad quieres que desaparezca, purgalo desde alli. ' +
    'Ese doble paso es la red de la que dependen todas las demas tools.';

  SR_GUARD_OWNER_MARKER =
    'RECHAZADO: los ficheros ".by" son el marcador de quien mando algo a la ' +
    'papelera. Los escribe el servidor y no se editan: reescribir uno es ' +
    'adjudicarse el trabajo de otro agente.';
  SR_GUARD_DEAD_TRASH =
    'RECHAZADO: __delphi-patch\\ es la papelera de copias recuperables. Se lee ' +
    'y se restaura, pero no se escribe dentro: esa copia es la ULTIMA version ' +
    'buena de un fichero y pisarla destruye justo lo que la papelera existe ' +
    'para conservar. El fichero vivo esta un nivel mas arriba.';
  SR_GUARD_DEAD_IDE =
    'RECHAZADO: __history\\ y __recovery\\ son las copias muertas del IDE. No ' +
    'se escribe en ellas; el fichero vivo esta en la carpeta del proyecto.';

  SR_FILE_PURGE_FOLDER_NOT_YOURS_FMT =
    'RECHAZADO: dentro de esa carpeta hay %d copia(s) que mandaron a la ' +
    'papelera otros agentes (%s). Una carpeta se purga entera o no se purga: ' +
    'purga tus copias una a una, o pidele al operador que limpie la carpeta.';

  SR_FILE_PURGE_NOT_YOURS_FMT =
    'RECHAZADO: esa copia la mando a la papelera OTRO agente (%s), asi que no ' +
    'es tuya para purgarla. Limpia lo tuyo; lo de los demas lo quita su ' +
    'dueno o el operador. (Si de verdad esto lo llevas tu, conectate con el ' +
    'mismo clientInfo.name con el que lo borraste.)';

  SR_FILE_PURGE_NOT_ROOT =
    'RECHAZADO: eso es la carpeta __delphi-patch ENTERA, y ahi dentro hay ' +
    'copias de otros. Purga lo tuyo: la subcarpeta del dia, o la copia ' +
    'concreta que quieras quitar de en medio.';

  SR_FILE_PURGE_FAILED_FMT =
    'RECHAZADO: no he podido purgar %s (%s). Si algo lo tiene abierto, ' +
    'reintenta en un momento.';

  SN_FILE_PURGED_FMT =
    'PURGADO %s. Esto no tiene vuelta atras: era una copia de la papelera y ' +
    'ya no esta.';

  SR_FILE_DELETE_EMPTY_SHELL_FMT =
    'CASI: TODO el contenido de %s esta ya fuera (copia recuperable en %s), ' +
    'y lo unico que queda es la carpeta VACIA, que no me deja quitarla ' +
    '(algun proceso la tiene como directorio actual). No te digo BORRADO ' +
    'porque el cascaron sigue ahi, pero no vuelvas a lanzar el borrado: no ' +
    'queda nada que copiar y cada intento solo ensucia la papelera. Que la ' +
    'quite el operador, o dejala: esta vacia.';

  SN_FILE_DELETE_EMPTY_OK_FMT =
    'BORRADA la carpeta vacia %s. No he hecho copia: no habia nada dentro ' +
    'que copiar.';

  SR_FILE_DELETE_STUCK_FMT =
    'RECHAZADO: %s esta vacia pero no puedo quitarla: algo la tiene abierta ' +
    '(suele ser que es el directorio actual de algun proceso). No hay nada ' +
    'dentro, asi que no se pierde nada dejandola; si molesta, la quita el ' +
    'operador.';

  SR_FILE_DELETE_PARTIAL_FMT =
    'A MEDIAS: la copia recuperable de %s SI esta hecha (%s), pero el ' +
    'original NO se ha podido quitar del sitio: algo lo tiene abierto (una ' +
    'compilacion en marcha, el IDE, o una carpeta que es el directorio ' +
    'actual de algun proceso). No te digo BORRADO porque no lo esta. ' +
    'Reintentalo dentro de un momento; si sigue igual, tiene que quitarlo el ' +
    'operador a mano.';

  SR_STYLES_RC_OUTSIDE_FMT =
    'RECHAZADO: el manifiesto %s de %s apunta a un fichero que esta FUERA de ' +
    'lo que este servidor deja leer. No lo compilo: el compilador de recursos ' +
    'abre lo que le pongas con los permisos del servidor y mete el contenido ' +
    'dentro del .res, que luego se puede descargar; por ahi se ha sacado ' +
    'desde el win.ini hasta el fichero de configuracion con el token. Las ' +
    'rutas del .rc tienen que quedarse dentro del workspace, y mejor ' +
    'relativas a la carpeta de estilos.';

  SR_STYLES_RC_DEEP =
    'RECHAZADO: los #include del manifiesto se anidan demasiado (mas de 8). ' +
    'Aplana el .rc: si hace falta esa profundidad, algo raro pasa.';

  SR_STYLES_RC_BADPATH_FMT =
    'RECHAZADO: no puedo resolver la ruta %s del .rc. Usa rutas relativas a ' +
    'la carpeta del propio .rc.';

  SR_STYLES_RC_UNREADABLE_FMT =
    'RECHAZADO: no puedo leer el .rc (%s) para comprobar a que ficheros ' +
    'apunta, asi que no lo compilo.';

  SR_PASERVER_PROFILE_NAME =
    'RECHAZADO: el nombre del perfil solo admite letras, digitos, punto, ' +
    'guion y guion bajo.';

  SN_PASERVER_PROFILE_REMOVED_FMT =
    'BORRADO el perfil de conexion "%s". Ojo: los perfiles viven fuera del ' +
    'workspace (donde los guarda el IDE), asi que esto NO tiene papelera: no ' +
    'hay vuelta atras salvo volver a crearlo con add-profile.';

  SR_PASERVER_HOST_DENIED_FMT =
    'RECHAZADO: no marco a "%s". Un test-connection es una conexion que abre ' +
    'ESTE servidor, asi que decidir a donde no te toca a ti: valen los hosts ' +
    'de los perfiles de conexion que ya tiene el IDE (command=profiles te ' +
    'los lista) y los que el operador haya escrito en [Security] RemoteHosts ' +
    '(ahora mismo: %s). Si lo que quieres es comprobar un target de verdad, ' +
    'usa su PERFIL por nombre: test-connection name=<perfil>.';

  SR_GIT_REMOTE_OFF_FMT =
    'RECHAZADO: este servidor no habla con "%s". Una URL explicita en un ' +
    'comando de git hace que sea EL SERVIDOR quien abre la conexion, asi que ' +
    'decidir con quien la abre no te toca a ti: el operador escribe los hosts ' +
    'permitidos en [Security] GitRemotes del settings.ini. Los remotos que el ' +
    'ya haya configurado en el repositorio SI funcionan: usa el nombre del ' +
    'remoto (push origin main), no la URL.';

  SR_GIT_REMOTE_HOST_FMT =
    'RECHAZADO: "%s" no esta entre los hosts que este servidor tiene ' +
    'permitidos (%s). Si hace falta uno mas, pidelo con delphi_report: lo ' +
    'anade el operador.';

  SN_GIT_HINT_OVERRIDE =
    'OJO con los "hint:" de ahi arriba: los escribe git, no yo, y algunos ' +
    'recomiendan justo lo que esta tool no deja hacer (--no-ff, rebase, dar ' +
    'la URL en la linea de comandos). Aqui la salida de un merge divergente ' +
    'es dejarlo estar y avisar a un humano, o merge args=--abort si te ' +
    'quedaste a medias; y para un remoto, su NOMBRE, no su URL.';

  SR_GIT_MERGE_ARGS =
    'RECHAZADO: merge solo acepta el NOMBRE de una rama, o "--abort" para ' +
    'salir de un merge a medias. Nada de opciones: --no-ff (y cualquier otra ' +
    'que anule el --ff-only con el que se lanza) deja el repositorio en ' +
    'MERGING con conflictos a medio resolver, que es justo lo que este ' +
    'comando promete que no puede pasar.';

  SN_GIT_MERGE_ABORTED =
    'MERGE ABORTADO: el repositorio vuelve a como estaba antes de intentarlo.';

  SR_GIT_MESSAGE_LINES =
    'error: "message" no admite saltos de linea en este comando (va en la ' +
    'linea de ordenes). commit y tag SI los admiten: ahi el mensaje se pasa ' +
    'por fichero (-F) y puedes escribir asunto, linea en blanco y cuerpo.';

  SR_GIT_SWITCH_NEEDS =
    'RECHAZADO: switch necesita "args" con el nombre de la rama. Para crear ' +
    'una nueva y saltar a ella: args=<rama> create=true. Los cambios sin ' +
    'commitear viajan contigo; si git se queja, guardalos antes con ' +
    'command=stash args=push.';

  SR_GIT_MERGE_NEEDS =
    'RECHAZADO: merge necesita "args" con la rama a integrar. Siempre se ' +
    'hace --ff-only: si hiciera falta un commit de merge (o hubiera ' +
    'conflictos), se rechaza en vez de dejarlo a medias. Eso es cosa de una ' +
    'persona, no de un agente adivinando.';

  SR_GIT_STASH_ARGS =
    'RECHAZADO: stash admite push (guardar, por defecto), pop (recuperar) o ' +
    'list. "drop" no esta: destruye trabajo sin vuelta atras.';

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
    'begin (new changeset -> id) | stage (add ONE operation) | unstage (take ' +
    'operation "n" back out; n=0 = the last one) | preview (resolve anchors + ' +
    'fingerprint files; required before commit) | commit (apply all or ' +
    'nothing) | rollback (discard) | status (list open ones)';

  SP_CHANGESET_N =
    'unstage: numero de la operacion a quitar, el que da preview (0 o vacio ' +
    '= la ultima apilada)';

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
    'RECHAZADO: kind debe ser edit | create | delete | delete-line | move.';

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
    'posterior a la ultima operacion que apilaste o quitaste (stage o unstage). Llama a command=preview y revisa el resultado.';

  SR_CHANGESET_FILE_CHANGED_FMT =
    'RECHAZADO: FILE_CHANGED - estos ficheros cambiaron despues del preview: ' +
    '%s. Nada se ha tocado. Repite preview (los fingerprints se recalculan) ' +
    'y vuelve a commit.';

  SR_CHANGESET_ROLLED_BACK_FMT =
    'ROLLBACK COMPLETO: fallo la operacion %d de %d y TODOS los ficheros han ' +
    'vuelto byte a byte a como estaban antes del commit. Causa: %s -- El ' +
    'changeset queda cerrado; corrige y monta otro.';

  SR_CHANGESET_PROJECT_FILE_FMT =
    'RECHAZADO: %s es un fichero de proyecto y lo mantiene el IDE; el commit ' +
    'lo iba a rechazar de todas formas, y te habria tirado la tanda entera. ' +
    'Para tocar el proyecto usa delphi_config (add-unit, remove-unit, ' +
    'add-platform, add-searchpath, set-output).';

  SN_CHANGESET_STATUS_NOTE =
    'Los ids salen recortados a proposito: los changesets se ven pero no se ' +
    'tocan sin el id completo, que solo tiene quien lo abrio. Si has perdido ' +
    'el tuyo, abre otro; el viejo caduca solo a la media hora.';

  SN_CHANGESET_BEGUN_FMT =
    'CHANGESET %s abierto. stage anade operaciones (una por llamada), ' +
    'preview las resuelve, commit aplica todo o nada.';

  SN_CHANGESET_STAGED_FMT =
    'STAGED %s de %s (operacion %d del changeset). Nada tocado aun. ' +
    'command=preview es OBLIGATORIO antes del commit, y tiene que ser ' +
    'POSTERIOR a la ultima operacion que apiles: si apilas algo mas despues ' +
    'del preview, hay que volver a previsualizar. Si te equivocas en una, ' +
    'command=unstage n=<numero> la quita sin tirar la tanda.';

  SN_CHANGESET_DISCARDED =
    'Changeset descartado. No se habia tocado ningun fichero.';

  SN_CHANGESET_PREVIEW_OK =
    'Preview limpio: todas las anclas resuelven. commit aplica todo o nada; ' +
    'si un fichero cambia antes del commit, se rechaza entero.';

  SN_CHANGESET_PREVIEW_BAD =
    'Hay operaciones sin resolver (anchor NO ENCONTRADA o AMBIGUA). Quita la ' +
    'que falla con command=unstage n=<el numero que ves arriba> y vuelve a ' +
    'apilarla bien (con atline si el ancla sale mas de una vez): NO hace ' +
    'falta tirar la tanda entera. commit sigue bloqueado hasta un preview ' +
    'limpio.';

  SN_CHANGESET_COMMITTED_FMT =
    'COMMIT COMPLETO: %d operaciones aplicadas sobre %d ficheros. Esto es lo ' +
    'que ha cambiado:'#10'%s'#10'Los backups por fichero de __delphi-patch ' +
    'siguen existiendo como siempre.';

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
