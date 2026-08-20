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
  SERVER_VERSION = '0.29.0-beta';

  // ---------------------------------------------------------------------
  // Virtual drive units (the path contract with the client)
  // ---------------------------------------------------------------------
  SN_VIRTUAL_DRIVES =
    'Server paths use VIRTUAL drive units - srvd:, srvc:, ... - which only ' +
    'exist inside this MCP: use them verbatim in every path argument and ' +
    'you will receive them back in results. They are NEVER your own local ' +
    'disks.';

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

  SR_JAIL_FMT =
    'RECHAZADO: "%s" esta FUERA de los workspaces permitidos. Este servidor ' +
    'solo opera dentro de: %s (configurado en DELPHI_MCP_ROOTS o ' +
    'settings.ini [Workspace] Roots).';

  SR_ROOTS_INVALID =
    'RECHAZADO: [Workspace] Roots esta configurado pero ninguna de sus ' +
    'rutas es valida (comillas de mas, unidad inexistente...). Por seguridad ' +
    'se rechaza todo hasta corregir settings.ini / DELPHI_MCP_ROOTS.';

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
  // delphi_report (feedback channel - works at EVERY access level)
  // ---------------------------------------------------------------------
  SD_REPORT =
    'Report a problem, limitation or suggestion about THIS MCP server ' +
    'directly to its maintainers. Use it whenever a tool refuses something ' +
    'you believe is legitimate, an answer looks wrong, a message is ' +
    'confusing, or you had to work around a missing capability - that ' +
    'feedback is what fixes the server. Each report is stored as its own ' +
    'timestamped markdown file in a reports folder next to the server ' +
    'executable, with the server version and the date. Available at EVERY ' +
    'access level, read-only included. Be concrete: what you tried, what ' +
    'happened, what you expected.';

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

  SR_REPORT_EMPTY =
    'RECHAZADO: delphi_report necesita "message" con la descripcion del ' +
    'problema. Cuenta que intentaste, que paso y que esperabas.';

  SN_REPORT_OK_FMT =
    'GRACIAS - reporte guardado como %s (v%s).'#10 +
    'Lo leeremos con calma junto a los demas. Si descubres mas detalles, ' +
    'manda otro reporte: se acumulan, no se sobreescriben.';

implementation

end.
