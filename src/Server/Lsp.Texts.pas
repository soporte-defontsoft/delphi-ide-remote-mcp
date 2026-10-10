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
    SR_* = refusal or failure, SK_* = success, SN_* = note/warning,
    SF_* = fragment (a piece glued into another text, or one line of a
    listing), SL_* = log line, SE_* = exception text.
  - Every SR_/SK_/SN_ STARTS with its tag: [AREA-NNN] or, for a refusal
    or a failure, [AREA-NNN OUTCOME] (DENIED, NOT_FOUND, INVALID_PARAM,
    INTERNAL - the code structuredContent publishes). The writer of the
    message declares the outcome; nobody reads it from the wording. The
    rest carry no tag. test_catalogo checks all of it.
  - The OUTCOME is what the agent must DO next (rule 11 of delphi_help
    conventions): INVALID_PARAM = the call is malformed (a missing
    parameter, a value of the wrong shape, two that do not combine);
    NOT_FOUND = well formed, but what it names is not there; DENIED = it
    exists, but a rule refuses it or something stands in the way (the same
    call will fail again); INTERNAL = the server broke or a piece of its
    installation is missing. A wrapper that tells a cause takes the
    cause's outcome (MsgConCausa); a caught exception with no outcome is
    INTERNAL (MsgExcepcion); a caller error that travels as an exception is
    raised as a tagged SR_. A failure goes in the answer or in the "error"
    field of a JSON answer - never in another field, where nobody reads it.
  - Every text leaves through MsgText / MsgFmt (MsgEnvuelve for a cause
    inside a wrapper), never written inline in a unit. English only.
  - A rejection says WHAT was refused, WHY, and THE LEGITIMATE WAY to do it.
    An agent that only hears "no" invents a workaround (measured twice in the
    field: build+run and trailing-dot bypasses). }

interface

uses
  System.JSON; // CampoDeTexto

const
  // ---------------------------------------------------------------------
  // Identity
  // ---------------------------------------------------------------------
  SERVER_NAME = 'delphi-lsp-mcp-service';
  { La marca de las notas de arranque que son un AVISO: la llevan las SL_ que
    las anuncian (las de Lsp.Settings, Lsp.NetDrives, Lsp.DesignerMetaGen y
    Lsp.Host) y la leen Lsp.Host y Lsp.NetDrives (NotaAlLog) para ponerles el
    prefijo de aviso. Una
    constante para los dos lados: al traducir cambia en un sitio. }
  SL_MARCA_AVISO =
    'WARNING';
  SERVER_VERSION = '1.17.0';

  // ---------------------------------------------------------------------
  // Virtual drive units (the path contract with the client)
  // ---------------------------------------------------------------------
  SF_VIRTUAL_DRIVES =
    'Server paths use VIRTUAL drive units - srvd:, srvc:, ... - which only ' +
    'exist inside this MCP: use them verbatim in every path argument and ' +
    'you will receive them back in results. They are NEVER your own local ' +
    'disks.';

  { Un servidor es UN Delphi y sin el suyo NO arranca (David, 5-oct-2026:
    "siempre debe haber uno, por eso es un servidor MCP para Delphi"). La
    fijada que no esta, o que no trae DelphiLSP, no se sustituye por otra.
    Lo lanza Lsp.Discovery.ExigeElDelphiDelServidor desde TMcpHost.Wire, y
    cada host lo cuenta a su manera: el log y un codigo de salida, el visor
    de eventos, la bandeja. La version sale del settings.ini y de nada mas
    (David: "o hay version en el ini o cogemos la mas nueva instalada,
    punto"). %s = la version, %s = las que sirven aqui, cada una con su
    clave. }
  SE_DISC_FIJADA_NO_ESTA_FMT =
    'This server does not start: its settings.ini pins [Server] ' +
    'DelphiVersion=%s, which is not installed on this machine or ships no ' +
    'DelphiLSP - a Delphi MCP server needs its Delphi and never uses ' +
    'another version instead. Usable here: %s.';
  SE_DISC_NINGUNA =
    'This server does not start: no RAD Studio with DelphiLSP is ' +
    'installed on this machine, and a Delphi MCP server needs its Delphi.';
  { Un settings.ini con el BOM de UTF-8 delante de una cabecera de seccion: la
    API de los ini de Windows no ve esa seccion (Lsp.Settings,
    LineaConBomAntesDeSeccion, medido el 6-oct-2026). %s = el fichero, %d =
    la linea. }
  SE_GUARD_INI_BOM_FMT =
    'This server does not start: its settings.ini (%s) has, on line %d, a ' +
    'UTF-8 BOM right before a section header, and the Windows ini reader ' +
    'does not see a header with a BOM in front - that whole section would be ' +
    'lost (for a [Server]: its Port, BindIP and DelphiVersion, so the ' +
    'server would listen on another port and on every network interface). ' +
    'Save the file as UTF-8 without BOM (one BOM at the very start followed ' +
    'by a comment line is harmless).';
  { Un settings.ini en UTF-16 big endian (FE FF) o en UTF-32 (LE o BE): la
    API de los ini de Windows lee UTF-16 little endian con su BOM, pero no
    estos; no veia ninguna seccion y se arrancaba sin ellas, callado (9.2 de
    la 1.18.0; UTF-32 medido el 9-oct-2026). %s = el fichero, %s = su
    codificacion (EncName). }
  SE_GUARD_INI_CODIFICACION_FMT =
    'This server does not start: its settings.ini (%s) is saved as %s ' +
    '(by its BOM), which the Windows ini reader does not read - every ' +
    'section would be lost (the [Server] port and bind IP, and each ' +
    'workspace with its roots and token). Save it as UTF-8 without BOM, or ' +
    'as UTF-16 little endian (what Notepad calls "UTF-16 LE").';
  { Un settings.ini que esta y no se puede leer (abierto en exclusiva por
    otro proceso, sin permiso para la cuenta del servidor): no se lee nada de
    el y se dice al arrancar y en delphi_workspace (David, 9-oct-2026:
    cerrado y nunca callado). %s = el fichero, %s = el motivo del sistema. }
  SL_GUARD_INI_SIN_LEER_FMT =
    'The settings.ini of this server (%s) could not be read (%s): nothing in ' +
    'it is in force - no workspace, so every token is refused and a client ' +
    'started with one admits nothing, and [Server] keeps its defaults (with ' +
    'no workspace token, HTTP binds only to 127.0.0.1 unless ' +
    'DELPHI_MCP_BIND_IP says otherwise). Close whatever holds the file, or ' +
    'give this server''s account read access to it, and restart the server.';
  { Una instalacion que sirve, con su clave, para la negativa. }
  SF_DISC_USABLE_FMT =
    '%s -> [Server] DelphiVersion=%s';
  SF_DISC_NINGUNA_USABLE =
    'none';
  { Al arrancar, TODAS las instalaciones de la maquina, cada una con la
    clave que el operador copiaria a su settings.ini, y cual usa este
    servidor (David, 5-oct-2026: "que se vea la clave que el operador
    deberia usar"). Las compone Lsp.Discovery.NotasDeArranqueDelphi. La
    que no trae DelphiLSP no ofrece clave: no la puede usar nadie. }
  SL_DISC_INSTALACION_FMT =
    'RAD Studio on this machine: %s  ->  [Server] DelphiVersion=%s%s';
  SL_DISC_LA_DEL_SERVIDOR =
    '   <- this server';
  SL_DISC_SIN_DELPHILSP_FMT =
    'RAD Studio on this machine: %s (version %s) ships no DelphiLSP: a ' +
    'server cannot use it.';
  { %s = la version con lo que la instalacion dice de si misma ('37.0 (RAD
    Studio 13, Delphi 13 and C++Builder 13 Update 1)'), %s = por que esa. }
  SL_DISC_USA_FMT =
    'This server uses DelphiVersion=%s, %s. One server, one Delphi: for ' +
    'another version, run another server from its own folder with its ' +
    'own port.';
  SL_DISC_POR_CLAVE =
    'pinned by [Server] DelphiVersion in settings.ini';
  SL_DISC_POR_DEFECTO =
    'the newest with DelphiLSP';
  { El update que declara el operador ([Server] DelphiUpdate): hoy no
    decide nada, es la prevision para lo que traiga uno concreto. }
  SL_DISC_UPDATE_DECLARADO_FMT =
    'Update declared in settings.ini: [Server] DelphiUpdate=%s.';
  SL_DISC_UPDATE_SIN_DECLARAR =
    'No update declared in settings.ini ([Server] DelphiUpdate=13.1, ' +
    '13.2...): none is assumed. The line of each RAD Studio above shows ' +
    'the update its installer recorded.';
  { Primer arranque sin version fijada: la elegida se escribe en su
    settings.ini, y a partir de ahi manda la clave - no cambia sola el dia
    que se instale otro Delphi (David, 5-oct-2026: "si no hay nada en el
    ini, podemos escribirlo con el Delphi escogido y a partir de ahi usar
    la clave"). La escribe Lsp.Settings.FijaDelphiVersionEnElIni. }
  SL_DISC_ESCRITA_FMT =
    'settings.ini had no [Server] DelphiVersion: this server chose the ' +
    'newest with DelphiLSP and wrote it there (DelphiVersion=%s), so it ' +
    'does not change by itself when another RAD Studio is installed. Edit ' +
    'it to use another one.';
  SL_DISC_NO_ESCRITA_FMT =
    SL_MARCA_AVISO + ': settings.ini has no [Server] DelphiVersion and ' +
    'this server could not write the one it chose (DelphiVersion=%s): %s. ' +
    'Add the key by hand, or it may change by itself when another RAD ' +
    'Studio is installed.';
  SF_DISC_NO_SE_LEE =
    'the key did not read back after writing it';
  { [Server] dos veces, o su DelphiVersion dos veces: Windows lee el primero
    y la clave del operador puede estar en el otro; escribirla la taparia
    (Lsp.Settings.FijaDelphiVersionEnElIni, revision del 6-oct-2026). }
  SF_GUARD_SERVER_DOBLE_NO_ESCRIBE =
    'settings.ini has [Server] twice, or DelphiVersion twice in it, and ' +
    'Windows reads only the first one - the version you meant may be in ' +
    'the other, and writing here would hide it for good. Merge them and ' +
    'set [Server] DelphiVersion yourself';
  { Un [Workspace.<nombre>] DelphiVersion= de la 1.13: quien lo tenia
    queria una version, y la mas nueva no se fija por el (David, 6-oct-2026).
    %s = el workspace. }
  SF_GUARD_WS_DELPHIVERSION_NO_ESCRIBE_FMT =
    '[Workspace.%s] still declares DelphiVersion (read until 1.13, ignored ' +
    'now), so that workspace wanted a version - pinning the newest here ' +
    'could be the wrong one. Move the version you mean to [Server] ' +
    'DelphiVersion';
  SN_WORKSPACE_LIBZONE_OFF =
    '[WS-001] The library zone is OFF on this server ([Workspace.<name>] ' +
    'LibraryZone=0): reading is limited to the roots, the same as ' +
    'writing. The sources of the RTL and of the components are NOT ' +
    'readable from here.';

  SN_WORKSPACE_NOTE =
    '[WS-002] These are paths on the REMOTE server that runs Delphi, not ' +
    'your local machine. Server drive letters travel as VIRTUAL units ' +
    '(srvd:, srvc:, ...): use them verbatim in every path argument - ' +
    'they only resolve inside this MCP, never on your disk. Work only ' +
    'inside "roots"; anything outside is refused.';

  // ---------------------------------------------------------------------
  // Listing and build results (a stateless protocol means the agent only
  // knows what each result tells it - so results must leave it ready for
  // the next step, the same way a rejection offers the legitimate path)
  // ---------------------------------------------------------------------
  // No '..' anywhere in this text: results are asserted to carry no
  // traversal residue (R4-C), so even a cosmetic ellipsis is banned here.
  SN_PROJECTS_NO_MATCH_FMT =
    '[PROJ-001] No project has that name ("%s"). There are %d in the ' +
    'workspace; call without "name" to see them (they come in pages).';

  // Una maquina de trabajo tiene MILES de .dproj: sin paginar, la respuesta
  // eran 82 KB y reventaba el limite del cliente, o sea que la tool era
  // inservible sin "root" (medido el 2026-09-20 usando el servidor como
  // agente: 7025 proyectos). Ahora se pagina como delphi_search.
  SN_PROJECTS_PAGE_FMT =
    '[PROJ-002] Here are %d of %d projects. The next page is offset=%d, ' +
    'but to really narrow it down use "name" or a more specific "root".';

  // La version del proyecto. Cuatro sitios del .dproj tienen que decir lo
  // mismo (los numeros del VERSIONINFO y las claves FileVersion y
  // ProductVersion) y el gate de release los compara: por eso es una
  // operacion curada y no una edicion por ancla.
  // El contrato de BuildWithParams.bat, el de la casa: quiet no le pide los
  // warnings a msbuild, asi que no hay recuento que dar. BUILD-001 lo decia
  // en CADA build quiet; desde el 4-oct-2026 lo dice esta descripcion y la
  // respuesta no lleva la clave (nunca un 0 que seria mentira).
  SP_BUILD_VERBOSITY =
    'quiet (DEFAULT: errors + the summary - cheapest for "does it still ' +
    'compile"; warnings are not even asked for) | normal (warnings and ' +
    'msbuild milestones) | verbose (everything, the whole linker command ' +
    'line included - when a quiet error is not clear enough). It sets ' +
    'msbuild''s own verbosity: quiet asks for less, it does not just hide ' +
    'it.';

  SR_CONFIG_VERSION_VACIA =
    '[CFG-001 INVALID_PARAM] "version" is missing. Examples: 1.2.3, 1.2.3.0 or ' +
    '1.2.3-beta (the suffix is accepted and ignored for the VERSIONINFO, ' +
    'which is numeric).';

  SR_CONFIG_VERSION_FORMATO_FMT =
    '[CFG-002 INVALID_PARAM] "%s" is not a version. Expected 2 to 4 numbers ' +
    'separated by dots (1.2, 1.2.3, 1.2.3.4), each between 0 and 65535. ' +
    'A suffix like -beta is accepted and ignored for the VERSIONINFO.';

  SR_CONFIG_VERSION_SIN_VERINFO =
    '[CFG-003 DENIED] This project has no VERSIONINFO (there is no ' +
    'VerInfo_MajorVer in the .dproj). The IDE creates that block when ' +
    '"Include version information" is checked in Project Options; once ' +
    'it exists, this tool maintains its values.';

  SN_CONFIG_VERSION_OK_FMT =
    '[CFG-004] Project version: %s (was %s). The Windows VERSIONINFO and ' +
    'the FileVersion/ProductVersion keys now say the same thing, which ' +
    'is exactly where they drift apart when edited by hand. I did NOT ' +
    'touch Android (versionCode/versionName) or iOS (CFBundleVersion): ' +
    'numbering there is different and versionCode can only go up. ' +
    'Previous copy of the .dproj in __delphi-patch.%s';

  SR_PROJECTS_NO_ROOT_FMT =
    '[PROJ-003 NOT_FOUND] The working folder "%s" does not exist on this ' +
    'server. It is not that there are no projects: there is nothing ' +
    'there. See delphi_workspace for the real folders.';
  { Sin "root", una raiz del workspace que no esta se salta y se dice: la
    primera que faltaba cortaba la lista ENTERA con PROJ-003, y el agente
    creyo que esa era la carpeta por defecto (Hermes, 5-oct-2026). }
  SN_PROJECTS_RAICES_SALTADAS_FMT =
    '[PROJ-005] Skipped, because the server cannot reach them right now: ' +
    '%s. The projects listed come from the other roots; delphi_workspace ' +
    'says why (unavailableRoots).';

  { Los ficheros que no se dejaron leer en una busqueda de carpeta: se
    caia la busqueda entera (SYS-027) por uno solo (sexta revision). }
  SN_SEARCH_ILEGIBLES_FMT =
    '[SEARCH-003] %d file(s) could not be read (another process holds ' +
    'them, or no permission) and were skipped: %s';

  { regex=true y el tope de tamano de delphi_search (muros de la lista del
    4-oct-2026: solo literal, y un fichero se leia entero fuera cual fuera) }
  SR_SEARCH_REGEX_INVALID_FMT =
    '[SEARCH-004 INVALID_PARAM] The query is not a valid regular expression: ' +
    '%s. Nothing was searched.';

  SR_SEARCH_REGEX_CARA_FMT =
    '[SEARCH-005 INVALID_PARAM] The regular expression gave up on line %d of ' +
    '%s: too much backtracking, or a repeated group too deep for that line ' +
    '(the engine has a step limit and a depth limit). Make it more ' +
    'specific - anchor it, avoid nested repetitions like (a+)+, and write ' +
    'a class instead of a repeated alternative on long lines ([ab]* does ' +
    'what (a|b)* does, with no depth). Nothing more was searched.';

  { Una consulta de varias lineas no casa con nada: la busqueda va linea a
    linea, y daba total 0 sin decir por que - el agente concluia que no habia
    nada parecido y escribia el gemelo, justo lo que el punto 14 de las
    convenciones manda evitar (revision de la 1.13.0). }
  SR_SEARCH_VARIAS_LINEAS =
    '[SEARCH-008 INVALID_PARAM] The query spans several lines, and the ' +
    'search goes line by line: it could match nothing, and "total 0" would ' +
    'not mean the text is not there. Search for ONE characteristic line ' +
    '(the most specific one), then read around the hits. Nothing was ' +
    'searched.';

  SN_SEARCH_GRANDES_FMT =
    '[SEARCH-006] %d file(s) larger than %d MB were not searched: %s';

  SR_SEARCH_FICHERO_GRANDE_FMT =
    '[SEARCH-007 INVALID_PARAM] %s is %d MB, more than the %d MB a search ' +
    'reads. Read the part you need with delphi_read (fromline/toline).';

  SN_SEARCH_MASK_NO_MATCH_FMT =
    '[SEARCH-002] The mask "%s" matched no file here, so nothing was ' +
    'searched: "total 0" does NOT mean the text is not there. pattern ' +
    'takes ONE mask (*.pas, *.dfm); without pattern, the Delphi sources ' +
    'are searched.';

  SR_CREATE_SUBDIR_REL_FMT =
    '[CREATE-001 INVALID_PARAM] "dir"="%s" is not valid for creating INSIDE a ' +
    'project. Here "dir" is a SUBFOLDER of the project, relative to it ' +
    'and with as many levels as you want (Domain\Models): no drive, no ' +
    'absolute path, no ".." and only letters, digits, space, dot, hyphen ' +
    'and underscore. The absolute path is only for creating a new ' +
    'PROJECT.';
  SR_CREATE_UNIT_NEED_PROJECT =
    '[CREATE-002 INVALID_PARAM] kind=unit needs "project" (the path of the .dpr ' +
    'or .dproj to add the unit to); the folder comes from there, and ' +
    '"dir" is its subfolder. For a STANDALONE unit that no project lists ' +
    'yet: no project, and "dir" = the ABSOLUTE folder to create it in.';
  SR_CREATE_SUELTO_DIR =
    '[CREATE-003 INVALID_PARAM] Without "project", "dir" must be the ABSOLUTE ' +
    'folder in which to create the file (inside your roots).';
  SN_CREATE_UNIT_SUELTA_FMT =
    '[CREATE-004] CREATED unit %s (%s), %d lines, STANDALONE: no project ' +
    'lists it yet. To put it in one: delphi_config command=add-unit; if ' +
    'its uses is split into {$IFDEF} branches, delphi_edit in the right ' +
    'branch.';
  // Aviso de delphi_edit (no bloquea): un comentario de llave con otra llave
  // dentro. Empieza por *** para que una tanda lo conserve.
  SN_AVISO_LLAVE_ANIDADA_FMT =
    '[EDIT-091] *** WARNING (not blocking): line %d opens a brace ' +
    'comment that has another brace inside. Pascal does not nest braces: ' +
    'the first } closes it and what follows is code, or a real directive ' +
    'if it quotes a brace-dollar one. If you meant to quote it, write ' +
    'the comment with // or with (* *). ***';
  SR_CREATE_INCLUDE_CONTENT =
    '[CREATE-005 INVALID_PARAM] kind=include needs "content": an empty .inc is ' +
    'of no use.';
  SN_CREATE_INCLUDE_FMT =
    '[CREATE-006] CREATED include %s (%s), %d lines. Use it with {$I ' +
    '%s.inc} from the unit that needs it; it is not registered in any ' +
    'project.';
  // Un uses partido en ramas IFDEF (cada rama acaba en su ;): error: y no
  // RECHAZADO, no es politica; es una forma que un escritor no sabe tocar.
  SR_USES_EN_RAMAS_FMT =
    '[USES-001 DENIED] The %s clause of %s is split into {$IFDEF} ' +
    'branches (each branch ends with its own ";") and I do not know ' +
    'which one the unit goes in: a unit in one branch only exists on ' +
    'that platform. Add, remove or rename it with delphi_edit in the ' +
    'right branch. Nothing was changed.';

  SN_COMPONENTS_FILTER_IGNORED_FMT =
    '[COMP-001] (I IGNORED filter="%s": with platform= this gives you ' +
    'the library paths of that platform, which is a different question. ' +
    'To search the installed packages, call without platform.)';

  SN_REPORT_KIND_FMT =
    #10 +
    '[REPORT-001] (NOTE: "%s" is not one of the kinds I handle, so I ' +
    'filed it as "bug". The valid ones: bug, limitation, suggestion, ' +
    'question.)';

  { Calentamiento del motor: definition vacia con hover lleno (medido por
    Hermes, 2026-09-22). Es "todavia no", asi que va como error: (corrige y
    repite) y no como RECHAZADO (cambia de rumbo). }
  SR_LSP_WARMING =
    '[LSP-025 DENIED] The engine recognizes the symbol at that ' +
    'position (hover answers) but has not indexed its definition yet: it ' +
    'is warming up that unit. Repeat the same call in a few seconds; the ' +
    'position is correct and there is nothing to change.';
  SR_REFS_WARMING_FMT =
    '[LSP-002 DENIED] The engine recognizes "%s" (hover answers) ' +
    'but does not have its definition indexed yet: it is warming up that ' +
    'unit. Repeat the same call in a few seconds, with the same ' +
    'arguments.';
  { Medido por Hermes (2026-09-22): con definition vacia, declaration directa
    en un punto de llamada devuelve el metodo ENVOLVENTE, y la tool lo daba
    por bueno sin decirlo. }
  SN_DEF_DECL_FALLBACK =
    ' [LSP-026] [note: definition did not resolve at that position, so ' +
    'this is DelphiLSP''s DIRECT declaration answer - on a call site that ' +
    'is the ENCLOSING routine, not the callee. Check the line before ' +
    'trusting it.]';

  SR_REFS_NO_DEFINITION_FMT =
    '[LSP-003 NOT_FOUND] The compiler does not resolve "%s" at that ' +
    'position, so there is nothing to anchor the references to. It is ' +
    'almost always because you are pointing at text that is not a ' +
    'symbol: inside a string, in a comment, on a reserved word, or at an ' +
    'identifier of another unit that this project does not compile. ' +
    'Point INSIDE the identifier on a real line of code (delphi_read ' +
    'gives you line and column). It can also happen if the project has ' +
    'no usable configuration: delphi_config command=view tells you ' +
    'whether it has one.';

  SR_LSP_LINE_RANGE_FMT =
    '[LSP-004 INVALID_PARAM] Line %d does not exist in %s, which has %d ' +
    'lines. Remember that lines here count from 0 (the last one is %d), ' +
    'while delphi_read numbers them from 1.';

  SR_LSP_CHAR_RANGE_FMT =
    '[LSP-005 INVALID_PARAM] Column %d does not exist on line %d, which has ' +
    '%d characters: "%s". Columns also count from 0, and you must point ' +
    'INSIDE the identifier.';

  SR_LSP_NEGATIVE_FMT =
    '[LSP-006 INVALID_PARAM] Line %d and column %d: there are no ' +
    'negative positions.';

  { El "path" de las tools de POSICION (definition, hover, completion,
    signature, references, rename_symbol). Estaba heredado de una clase base
    comun con delphi_symbols, asi que las SEIS anunciaban que aceptan una
    CARPETA - cosa que solo hace symbols. Compartir la clase base hizo
    compartir una descripcion que era verdad en una sola de ellas: el olor de
    siempre, pero al reves (medido 2026-09-20 leyendo el esquema de
    delphi_definition). }
  { "exit=0" y NADA mas es indistinguible de una respuesta que se ha roto por
    el camino, y lo primero que hace quien la recibe es repetir la llamada.
    En "diff" el silencio SIGNIFICA algo -no hay cambios-, que es justo lo que
    se estaba preguntando; en otras ordenes significa "fue bien y esta no
    imprime nada". Decirlo cuesta una linea. Medido 2026-09-20 preguntando por
    el diff de un arbol limpio. }
  { Cuatro caracteres, "null", como respuesta entera. Es correcto -el motor no
    ha resuelto nada- y es ilegible: no dice si apuntaste mal, si falta la
    configuracion del proyecto o si ahi de verdad no hay nada que resolver, y
    las tres se arreglan de forma distinta. Una respuesta que no se puede
    leer cuesta una llamada, y a veces tres. }
  SN_LSP_NULL_NOTE =
    '[LSP-029] null - the engine resolved nothing there. It is not an ' +
    'error: it simply has no answer. The four causes, most frequent ' +
    'first: (1) the position does not fall INSIDE an identifier - lines ' +
    'are 0-BASED here and 1-based in delphi_read, so line N of a read is ' +
    'N-1 here; (2) the file has no project configuration and the engine ' +
    'cannot cross units (the warning next to this says so, if it ' +
    'appears); (3) there is a reserved word, a literal or a comment ' +
    'there, and no symbol to resolve; (4) rarely, the engine has no answer ' +
    'at THIS position and has one at another occurrence of the same ' +
    'symbol (measured 2026-09-30: 9 of 10 on one line, 0 of 10 on three ' +
    'others) - ask at another one. To see what is on that line, ' +
    'delphi_read; to locate a symbol by name, delphi_symbols ' +
    'filter=<name>, which gives you the line already split into 1-based ' +
    'and 0-based.';

  SN_GIT_DIFF_CLEAN =
    '[GIT-001] (no differences: NOTHING has changed compared to what was ' +
    'compared. The command went fine; git prints nothing when there are ' +
    'no changes.)';

  SN_GIT_DIFF_HAY_CAMBIOS =
    '[GIT-037] exit=1 from diff means there ARE differences (--quiet and ' +
    '--exit-code answer that way): it is not a failure.';

  SN_GIT_SILENT_OK_FMT =
    '[GIT-002] (git %s finished fine, and it prints nothing when it ' +
    'succeeds. It is not a lost answer: it is this command''s success.)';
  { Una CONSULTA vacia (log, tag, branch, stash list...) no es un exito sin
    mas: no hay nada que mostrar (revision de la 1.17.0). }
  SN_GIT_CONSULTA_VACIA_FMT =
    '[GIT-060] (git %s found nothing to show: nothing matches, or there is ' +
    'nothing to list. It finished fine; it is not a lost answer.)';
  { Un log -S/-G vacio: que miran y como comprobar el texto. -S y -G
    distinguen mayusculas y -i las iguala (medido el 7-oct-2026: -Srelease
    126 commits, con -i 185). }
  SN_GIT_PICKAXE_VACIO =
    '[GIT-058] -S and -G look for exactly that text, capitals included, in ' +
    'what each commit adds or removes: no commit does. -i ignores capitals; ' +
    'delphi_search shows where a text is today.';

  SP_LSP_FILE_PATH =
    'A Delphi file (.pas/.dpr/.dpk/.inc). ONE file goes here, not a ' +
    'folder: these tools resolve a position inside a source. To see at ' +
    'once what each unit of a folder offers, that is delphi_symbols.';

  SP_SYMBOLS_PATH =
    'A Delphi file (.pas/.dpr) for its symbols - or a FOLDER: at once, ' +
    'what each unit in it OFFERS (its interface: types, classes, routines, ' +
    'properties, uses), without bodies - ONE call to find your way around ' +
    'code you did not write.';

  { El resumen de una carpeta tenia un tope de 60 UNIDADES y no de tamano:
    src\Server daba 40K de una vez, y lo que no cabia solo decia
    "truncated" (revisor de tokens, 4-oct-2026). %d: el tope en caracteres;
    %d: cuantas no entraron; %d: cuantas nombra notShown (tiene tope: decia
    que las nombraba todas, revision de la 1.13.0). }
  SN_SYMBOLS_DIGEST_FUERA_FMT =
    '[LSP-034] The digest stops at about %d characters: %d units are not ' +
    'in it, and "notShown" names %d of them (relative to the folder). Ask ' +
    'for one of them by its path, or for a subfolder.';

  SN_SYMBOLS_DIGEST_NOTE =
    '[LSP-007] This is the DIGEST: only what each unit declares in its ' +
    'interface, read as text and without the semantic engine. For the ' +
    'detail of one unit (with ranges and nesting) call with the file; to ' +
    'read it whole, delphi_read. If a unit is missing or something looks ' +
    'odd, do not rely on the digest to edit: read the file.';

  { Lo que un contenedor del arbol lleva dentro, detras de su linea: la
    descripcion de delphi_symbols lo promete asi, en ingles ('+N inside'),
    y el arbol lo escribia en castellano y en linea (revisor de tokens del
    4-oct-2026). }
  SF_SYMBOLS_DENTRO_FMT =
    ' (+%d inside)';

  SP_SYMBOLS_MODE =
    'For a FILE only: summary = the skeleton (each section with its ' +
    'members and line; containers say how many they hold) | full = the LSP ' +
    'tree with its ranges, minus what repeats. Empty = full if the tree is ' +
    'small, summary if large (the answer says which, and how big the full ' +
    'one was).';

  SP_SYMBOLS_FILTER =
    'For a file: only the symbols whose name contains this ' +
    '(case-insensitive), with kind, declaration as written (decl), line ' +
    'and container. Ignores mode. The cheap way to find a method without ' +
    'the whole tree.';

  { Decia "lineas 0-based" y desde v1.0.4-beta los @N son 1-BASED, como los
    de delphi_read: la nota se quedo describiendo el comportamiento viejo.
    Importa porque las tools de LSP (definition, hover, references,
    completion, signature, rename) SI toman 0-based, asi que un agente que se
    creyera la nota apuntaba una linea mas abajo. Ahora se dicen las dos
    cosas, que es lo unico que no se malinterpreta. }
  SN_SYMBOLS_SUMMARY_NOTE =
    '[LSP-008] SUMMARY: each line is the declaration as written in the ' +
    'source; @N is 1-based (delphi_read), the LSP tools take @N-1; (+N ' +
    'inside) = members of a container: filter="name" finds one (line and ' +
    'line0 split), mode="full" gives ranges. Top-level "symbols" live in ' +
    'no section (a .dpr).';

  { El filtro busca por NOMBRE y antes buscaba dentro de la firma renderizada,
    asi que filter="string" sacaba nueve cosas por su TIPO. Al arreglarlo, esa
    llamada pasa a dar cero - y cero sin explicacion se lee como "aqui no hay
    nada". }
  SN_SYMBOLS_FILTER_NONE =
    '[LSP-009] No matches. This searches by symbol NAME, not by type nor ' +
    'by the text of the signature: to search text inside the source use ' +
    'delphi_search, and to see the whole skeleton, mode="summary".';

  SN_SYMBOLS_AUTO_FMT =
    '[LSP-010] The full tree was %d characters, so here is the summary. ' +
    'With mode="full" you get it whole; with filter="name" only what you ' +
    'are looking for.';

  SP_CONFIG_SECTION =
    'view only: summary (default) | platforms (state and reasons) | ' +
    'searchpaths (by group) | deploy (files by platform) | units (all the ' +
    'project units) | all (everything, large).';

  SN_CONFIG_SECTIONS =
    '[CFG-005] This is the summary. The detail, by section: ' +
    'section=platforms | searchpaths | deploy | units. section=all ' +
    'brings everything together (large).';

  { Regla 11 de las convenciones: "error:" es "no he podido (no existe, no
    cuadra, falta un parametro): corrige y repite"; "RECHAZADO:" es "te lo he
    denegado a proposito, no insistas". Un fichero que no esta es el ejemplo
    literal de la primera, y este texto llevaba la segunda: al agente que se
    equivocaba de nombre se le decia que se rindiera (medido 2026-09-20).
    delphi_list y delphi_search ya lo hacen bien sobre la misma entrada. }
  { El motor de ese proyecto lo paro el propio servidor: su carpeta se movia
    o se borraba, o git reescribia el arbol (switch, merge, stash, pull de
    otro agente). Quien tenia una peticion en vuelo lo recibe AL INSTANTE, no
    al acabar su plazo de 30 o 60 s (29-sep-2026). Con etiqueta: lo lee un
    agente, que tiene que saber que basta con repetir. Y el motor que se
    acabo SOLO: el servidor lo retira igual, y a quien tenia una peticion en
    vuelo no se le dice que su carpeta se movia (sexta revision). }
  SR_LSP_ENGINE_STOPPED =
    '[LSP-033 DENIED] The LSP engine of that project is not running any ' +
    'more: this server stopped it - its folder was being moved or ' +
    'deleted, git was rewriting the tree (switch, merge, stash, pull), ' +
    'or the engine had stopped answering - or its process had ended by ' +
    'itself. Repeat the request - at the new place if the folder was ' +
    'moved: a new engine starts with it.';

  { Como acabo un motor que este servidor paro, cuando no acabo limpio o no
    contesto a `shutdown` en su plazo (30-sep-2026). Al log del servidor: con
    el modo sin cuadro puesto al motor, Windows ya no apunta su caida en el
    Visor de eventos (medido ese dia), que es donde se encontraron. Sin
    etiqueta: no lo lee un agente. }
  SL_LSP_ENGINE_ENDED_FMT =
    'lsp: ENGINE %s exit=$%x shutdown asked=%s answered=%s';

  { Los motores que para el barrendero de la sesion (30-sep-2026): el COLGADO
    -algo en vuelo y ninguna senal de vida en su plazo- y el que nadie usa. }
  SL_LSP_ENGINE_HUNG_FMT =
    'lsp: ENGINE %s stopped by the server: something in flight and no sign ' +
    'of life (no message, no CPU, no I/O) for %d s, and no answer when asked';

  SL_LSP_ENGINE_IDLE_FMT =
    'lsp: ENGINE %s stopped by the server: not used for %s min';

  { El tope de motores ([Server] MaxEngines, 4-oct-2026): el menos usado de
    los que no trabajan deja sitio al que llega. %s: el motor que se para;
    %d: el tope; %s: el que llega. }
  SL_LSP_ENGINE_LRU_FMT =
    'lsp: ENGINE %s stopped by the server: MaxEngines=%d reached, and it ' +
    'was the least recently used one; it makes room for %s';

  { El servicio sin la ventana que RunService le da a la aplicacion de la
    VCL (30-sep-2026): sin ella el bucle principal no recibe el WM_QUIT del
    marco de servicios y el proceso no se va al parar. }
  SL_SYS_SERVICE_NO_WINDOW =
    'service: the application window could not be created - after a stop ' +
    'this process will not leave by itself, and the system ends it about ' +
    'thirty seconds later';

  { Una carpeta que se esta yendo no arranca motores: el que arrancase
    volveria a retenerla (29-sep-2026). }
  SR_LSP_FOLDER_LEAVING_FMT =
    '[LSP-032 DENIED] "%s" is inside a folder that is being moved, ' +
    'deleted or rewritten by git right now, and no LSP engine is started ' +
    'there. Repeat the request in a moment - at the new place if the ' +
    'folder was moved.';

  SR_LSP_NO_FILE_FMT =
    '[LSP-011 NOT_FOUND] %s does not exist. Check the name and the ' +
    'folder: delphi_list root=<folder> shows what is really there, and ' +
    'delphi_search finds it by content.';

  { Un motor sin ajustes de proyecto NO publica diagnosticos: ni de una unidad
    valida ni de un error de sintaxis (medido 2026-10-06: 4,5 min y 80 s en
    "in-progress"; Hermes, la VM 13.2, se fue a los 300 s de su cliente). Se
    dice antes de arrancar un motor para nada. Una unidad que ningun proyecto
    lista pero que vive junto a uno SI se analiza con los de ese proyecto
    (medido el mismo dia: E2029 al momento). }
  SR_LSP_LINT_SIN_AJUSTES_FMT =
    '[LSP-035 NOT_FOUND] %s has no project settings to be linted with: no ' +
    '.delphilsp.json or .dproj was found for it in its folder or the ones ' +
    'above. The engine compiles a unit with the settings of a project and, ' +
    'with none, never answers - nothing was linted. Put it in a project ' +
    '(delphi_config command=add-unit) or create one (delphi_create), and ' +
    'lint it again.';

  { La ruta existe, pero es de otro tipo - que no es lo mismo que no existir.
    Medido 2026-09-20: delphi_read sobre la raiz del repo contestaba "no
    existe" de una carpeta con 20 entradas, y el agente se iba a buscar una
    ruta que tenia delante. }
  { El espejo del anterior: delphi_list y delphi_package sobre un README.md
    que existe contestaban "directory not found", conflando "no esta" con "no
    es de ese tipo" igual que delphi_read al reves (medido 2026-09-20). }
  { Una mascara que no casa con NADA y una carpeta vacia contestaban lo
    mismo: total 0 y files vacio (sin llaves aqui: cierran el comentario).
    delphi_symbols presume en su propia
    negativa de haber arreglado justo esto ("antes te devolvia una lista
    vacia, que parecia decir que la unit no tiene nada") y el arreglo no
    habia viajado hasta aqui - medido 2026-09-20 sobre src\, que tiene 55
    fuentes. }
  { delphi_projects escondia las copias de seguridad y los artefactos del IDE
    sin decirlo: apuntarlo a __delphi-patch contestaba total 0 teniendo dos
    .dproj dentro. delphi_list ya contaba lo oculto y te lo ensenaba si
    NOMBRABAS esa carpeta como raiz; el arreglo no habia viajado hasta aqui.
    Lo vio David el 2026-09-20 preguntando si esto deberia leer __delphi-patch
    para declarar proyectos - no debe declararlos, pero si decir que estan. }
  { Dentro de la jaula pero en una carpeta declarada de SOLO LECTURA. No es
    la jaula: la jaula dice "ahi no entras" y esta dice "ahi miras y no
    tocas", asi que el texto tiene que distinguirlo o el agente se pone a
    buscar un problema de roots que no tiene. Nace el 20-sep-2026 para los
    clones de referencia que viven dentro del repo con su propio git. }
  { Un identificador corto (una variable local de una letra) saca cientos de
    homonimos, y volcarlos enteros hizo una respuesta de 78 KB que el cliente
    MCP rechazo ENTERA - el agente no vio ni las referencias buenas. Se listan
    los primeros y se dice cuantos hay. Medido 2026-09-20. }
  { La ruta cae dentro de la jaula por el TEXTO, pero un enlace del camino
    lleva fuera. Merece mensaje propio y no el de la jaula: quien lo lea tiene
    que entender que su ruta no esta mal escrita, que lo que pasa es que esa
    carpeta no es lo que parece. Encontrado el 2026-09-20 por un agente
    auditor: un junction dentro del root apuntando a
    C:\Windows\System32\drivers\etc hacia que delphi_list listara ese sitio y
    delphi_read devolviera el hosts de la maquina - y se podia plantar un
    fichero fuera. }
  SR_JAIL_LINK_FMT =
    '[GUARD-001 DENIED] "%s" looks like it is inside the allowed ' +
    'workspaces, but some part of the path is a LINK (junction or ' +
    'symlink) that leads outside them, and the jail is measured on the ' +
    'real target, not on the name. You did not mistype the path: that ' +
    'folder is not what it looks like. If the link should be allowed, it ' +
    'is the operator who adds its TARGET to Roots= of your ' +
    '[Workspace.<name>].';

  // P4-a de la 1.18.0: la carpeta en la que de verdad se escribiria (por un
  // enlace del camino) no es de escritura; vale para los cuatro motivos
  // (fuera de las raices, referencia, solo lectura, un vault: revisor, B-5)
  SR_SUSTITUCION_CARPETA_REAL_FMT =
    '[GUARD-037 DENIED] "%s": some part of the path is a LINK, and the ' +
    'folder this file really sits in is not one this session writes in ' +
    '(outside the roots, a reference, a read-only folder or a vault). The ' +
    'temporary file and the replace would be born there. Nothing was ' +
    'written.';

  // la gemela de GUARD-001 para la zona de biblioteca (M1 de la 1.18.0)
  SR_JAIL_LINK_BIBLIOTECA_FMT =
    '[GUARD-036 DENIED] "%s" looks like it is inside the IDE''s library ' +
    '(the Library Search Path, read-only), but some part of the path is a ' +
    'LINK (junction or symlink) that leads outside it, and the jail is ' +
    'measured on the real target, not on the name. What is behind that ' +
    'link is not read.';

  { Un virtual y su override no son dos simbolos: son el mismo metodo a dos
    alturas de la jerarquia. Preguntando por el de la base, las llamadas
    reales -que resuelven SIEMPRE a la hija- se iban a la lista de homonimos
    y la respuesta era "no lo llama nadie" sobre un metodo con dos llamadas.
    Un agente actua sobre eso borrando la base de la jerarquia. }
  SN_REFS_FAMILY_NOTE =
    '[LSP-012] Among the confirmed ones, some are marked with ' +
    'via:"override": they do not resolve to THIS method but to one of ' +
    'its inheritance family (the virtual one and whoever overrides it, ' +
    'or the other way round). They are counted as its uses on purpose: a ' +
    'call through a variable of the child class always resolves to the ' +
    'child, so asking about the virtual of the base class the answer ' +
    'would have been "nobody calls it" for a method that has calls. If ' +
    'you are going to RENAME, careful: the whole family has to be ' +
    'renamed at once or the override stops overriding.';

  SN_REFS_REJECTED_CAP_FMT =
    '[LSP-013] %d of the %d discarded are listed: a short identifier ' +
    'yields hundreds and the whole answer does not fit in the client. ' +
    'The full count is in rejectedHomonyms; if you need to see them all, ' +
    'ask about a smaller scope (a specific file as path) or use ' +
    'delphi_search wholeword=true, which pages.';

  { "No lo se" y "se que no" no son lo mismo, y acababan en el mismo saco.
    Un nombre escrito en un comentario o dentro de una cadena no lo resuelve
    el motor -ahi no hay simbolo- igual que no resuelve lo que se quedo sin
    presupuesto de validacion, y las dos cosas caian en "unverified". Como
    delphi_rename_symbol bloquea el rename con UNO solo, documentar un
    identificador dejaba esa tool inservible sobre el. Medido 2026-09-21
    sobre MaskDriveText de este repo: 18 confirmadas, 6 unverified, las SEIS
    comentarios. }
  { El motor puede contestar con un fichero de OTRO sitio. Sin .delphilsp.json
    ni .dproj cerca la unit va SIN CONFIGURAR, y el indice del motor -que
    sobrevive al reinicio del servidor- conserva units del mismo nombre vistas
    en otras sesiones. Medido 2026-09-21: preguntando por un simbolo de la
    jaula A, la definicion resolvia a un fichero de la jaula B de una bateria
    anterior; al borrar ese fichero, caia en el de una tercera. La llamada
    entera moria con un RECHAZADO de jaula que ADEMAS escupia la ruta ajena:
    una respuesta imposible y una fuga en el mismo sitio. El %s es el
    IDENTIFICADOR, nunca la ruta de fuera. Y desde P2 de la 1.18.0 la otra
    causa, la de un proyecto CONFIGURADO: una unit que su .dpr nombra con
    ruta fuera de las raices (la misma que niega LSP-038); el texto decia que
    casi siempre era una unit sin configurar. }
  SR_REFS_TARGET_OUTSIDE_FMT =
    '[LSP-014 DENIED] "%s" resolves to a definition OUTSIDE this ' +
    'workspace, so I do not search for its uses: what I found here would ' +
    'not be uses of that symbol, and telling you nobody uses it would be ' +
    'worse than not answering. Two things cause it: a unit the project''s ' +
    '.dpr names with a path outside the roots (bring that unit into the ' +
    'workspace or take it out of the project), or an UNCONFIGURED unit (no ' +
    '.delphilsp.json or .dproj nearby), which the engine resolves against ' +
    'another unit with the same name that it indexed before - then work on ' +
    'the project, with its .dproj next to it, so that it gets configured. ' +
    'delphi_definition and delphi_hover deny it the same way (LSP-038).';

  SN_REFS_ILEGIBLES_FMT =
    '[LSP-040] %d file(s) of the scope could not be read (another process ' +
    'holds them, or the gate refused): they are listed in "unreadable" and ' +
    'were NOT scanned, so a reference in them is not here. ' +
    'delphi_rename_symbol refuses while any is listed.';
  SN_REFS_MENTIONS_FMT =
    '[LSP-015] The name also appears %d time(s) in COMMENTS or inside ' +
    'strings (%d are listed in "mentions"). They are not references - ' +
    'there is nothing there for the compiler to resolve - so they do not ' +
    'count as "unverified". A COMMENT never blocks delphi_rename_symbol, ' +
    'which renames code, not prose; a STRING LITERAL in a file the rename ' +
    'touches DOES (RENAME-020): it may be a FindComponent, RTTI or ' +
    'StyleLookup by name, which a rename would leave pointing at a name ' +
    'that no longer exists. If you want the comments to say the new name ' +
    'too, change them by hand with delphi_edit.';

  SR_READONLY_PATH_FMT =
    '[GUARD-012 DENIED] "%s" is inside a folder declared READ-ONLY in ' +
    'this workspace (%s). It is not the jail: you CAN read there ' +
    '(delphi_read, delphi_search, delphi_symbols...), what you cannot do ' +
    'is write. It is usually third-party code - a vendor, a submodule, a ' +
    'reference clone - that is consulted but not touched. If it really ' +
    'has to change, it is the operator who removes it from ' +
    'ReadOnlyPaths= in their [Workspace.<name>]: ask for it with ' +
    'delphi_report and say what for.';

  SN_PROJECTS_HIDDEN_FMT =
    '[PROJ-004] %d .dproj/.groupproj hidden because they are COPIES: ' +
    'backups of this server (__delphi-patch), of the IDE (__history) or ' +
    'build artifacts. They are not projects you can open. If you want to ' +
    'see them, pass that folder as "root" and I will show them.';

  SN_LIST_MASK_NO_MATCH_FMT =
    '[LIST-001] The mask "%s" matched nothing, but the folder is NOT ' +
    'empty: its first level alone has %d entries. ONE mask (*.pas) or ' +
    'several separated by ";" (*.pas;*.dfm) are accepted. Without ' +
    'pattern, the Delphi sources and projects are listed.';

  SR_LIST_IS_FILE_FMT =
    '[LIST-002 INVALID_PARAM] %s is a FILE, not a folder. delphi_list ' +
    'walks folders; to read it use delphi_read, and to search INSIDE it, ' +
    'delphi_search root=<that file> (it accepts a single file as root).';

  SR_LSP_IS_FOLDER_FMT =
    '[LSP-016 INVALID_PARAM] %s is a FOLDER, not a file. To see what it ' +
    'contains use delphi_list root=<that path>; to read one of its ' +
    'files, pass its full path.';

  SR_LSP_NOT_SOURCE_FMT =
    '[LSP-017 INVALID_PARAM] %s is not a Delphi source: the language ' +
    'tools work on .pas, .dpr, .dpk and .inc files.';

  { La descripcion del parametro, compartida por delphi_edit y
    delphi_textedit: lo que hace no depende de si el fichero es Pascal. }
  { El rechazo del ancla de VARIAS lineas en la forma suelta. Mandaba a "una
    llamada por linea", que era verdad en agosto y dejo de serlo dos veces:
    primero cuando "edits" acepto anclas de BLOQUE y despues cuando llego
    "toline". Un agente que se cree la negativa hace cuarenta llamadas para
    algo que es una. Lo mide quien lo sufre: yo tropece con esta misma
    negativa dos dias seguidos usando el servidor como cliente, y las dos
    veces el camino bueno estaba a un parametro de distancia. Una negativa
    que no dice por donde SI se puede es media negativa. }
  SR_PATCH_ANCHOR_MULTILINE =
    '[EDIT-001 INVALID_PARAM] The anchor of a SINGLE edit is ONE line, and this ' +
    'one has several. Nothing was written. What DOES work:'#10 +
    '- Several CONSECUTIVE lines at once: send them in "edits" as ONE ' +
    'entry; there the anchor can be a BLOCK and it is replaced whole.'#10 +
    '- Removing or replacing a RANGE of which you only want to write the ' +
    'first line: "old" = that line and "toline" = the last line of the ' +
    'range.'#10 +
    '- INSERTING: anchor on ONE existing line and in "new" send back ' +
    'that same line together with the new text.';

  { Un texto por concepto en las hermanas que lo tienen (delphi_edit y
    delphi_textedit: delphi_changeset no lleva toline): medido con Qwen3.8 y
    Glimmer el 5-oct-2026 contra el largo de antes, sin perder acierto
    (scratchpad banco_edit). }
  SP_PATCH_TOLINE =
    'RANGE (1-based, inclusive): with this, "old" becomes the FIRST line ' +
    'of a range that ends here - delete:true removes it all (a whole ' +
    'method, without pasting it), "new" replaces it all. Refused if ' +
    'backwards, past the end or the whole file.';

  { EL MODO FRAGMENTO (2026-09-21). El ancla de linea completa es la regla
    de la casa y sigue siendolo: existe para que nadie edite de memoria. Pero
    un parrafo de README es UNA linea de 600 caracteres, y cambiar "68" por
    "69" obligaba a pegarla entera byte a byte - el muro que acabo con un
    reemplazo hecho por fuera de la tool. El fragmento no relaja la regla:
    "atline" es OBLIGATORIO y el fragmento tiene que aparecer UNA sola vez
    en esa linea. Un solo texto para las tres tools que lo aceptan. }
  { La puerta HTTP: una sesion que este proceso no emitio, o que caduco por
    inactividad. 404 con motivo, para que el cliente vuelva a hacer
    initialize en vez de trabajar contra un fantasma. }
  SR_SESSION_UNKNOWN =
    '[SYS-007 NOT_FOUND] Session not found: this server does not know ' +
    'that Mcp-Session-Id (it was restarted since, or the session was ' +
    'closed or expired long ago). Send initialize again and use the new ' +
    'session id.';
  SR_SESSION_EXPIRED_FMT =
    '[SYS-008 NOT_FOUND] Session expired: no request on it for more than ' +
    '%s minutes ([Server] SessionTimeoutMinutes). Send initialize again ' +
    'and use the new session id.';
  { La que se cerro para hacer sitio: salia SYS-007 "el servidor se
    reinicio" (octava revision). }
  SR_SESSION_EXPULSADA_FMT =
    '[SYS-033 NOT_FOUND] Session closed to make room: the server keeps ' +
    'at most %d sessions, and this one had gone longest without a ' +
    'request. Send initialize again and use the new session id.';
  { The HTTP gate without a valid token: what the client has to send and
    where the token lives. Said by the 401 body and by the tray when it
    copies the URL (issue #4, 2026-09-27: the URL alone got a bare 401).
    At most 255 characters: it is also the tray's balloon, which Windows
    cuts there. No double quote or backslash: it goes inside JSON as is. }
  SF_TOKEN_NEEDED =
    'Send the header Authorization: Bearer <token>, where <token> is the ' +
    'Token= (or ReadOnlyToken=) of a [Workspace.<name>] section in the ' +
    'settings.ini next to DelphiLspMcp.exe. A browser cannot send it: ' +
    'register the URL in your MCP client with that header.';
  SN_SERVER_INI_CHANGED_FMT =
    '[SYS-001] settings.ini on disk was modified at %s, AFTER this ' +
    'process started at %s: what was edited is NOT loaded. The file is ' +
    'read once at start-up and never reloaded live (a running agent''s ' +
    'jail must not change under it): ask the operator to restart the ' +
    'service (sc.exe stop DelphiLspMcp; sc.exe start DelphiLspMcp).';
  SN_SERVER_LOCALSYSTEM =
    '[SYS-002] This server runs as LocalSystem. RAD Studio keeps its ' +
    'Library Path, registered packages, SDKs and PAServer profiles in ' +
    'the HKCU of the user who owns the IDE, and LocalSystem sees none of ' +
    'them: builds that use an installed component fail with F2613, ' +
    '"profiles" comes back empty and get-sdk lands in the SYSTEM ' +
    'profile. Ask the operator to make the service log on as that user ' +
    '(services.msc, or sc config ... obj=) - see "The service must log ' +
    'on as the user who owns the IDE" in the README.';

  SP_PATCH_FRAGMENT =
    'FRAGMENT mode for a LONG line: "fragment" = the exact piece to change ' +
    '(case-sensitive, EXACTLY ONCE in that line), "atline" = its 1-based ' +
    'line (MANDATORY) and "new" = what replaces just that piece; the rest ' +
    'of the line stays byte for byte. One line only; it goes INSTEAD of ' +
    '"old" and combines with no other mode (nor toline).';

  SR_FRAG_NEEDS_ATLINE =
    '[EDIT-002 INVALID_PARAM] "fragment" needs "atline": the number (1-based, ' +
    'the one delphi_read shows) of the line where it is. A fragment is ' +
    'searched for INSIDE one specific line, never across the whole file. ' +
    'Nothing was written.';
  SR_FRAG_MIXED_FMT =
    '[EDIT-003 INVALID_PARAM] "fragment" does not combine with "%s". They are ' +
    'two different ways of saying where: either the whole line in "old" ' +
    '(with delete/toline if needed), or a piece of ONE line with ' +
    'fragment + atline + new.';
  SR_FRAG_MULTILINE =
    '[EDIT-004 INVALID_PARAM] In fragment mode neither "fragment" nor "new" ' +
    'contain line breaks: it changes a piece INSIDE one line. To add or ' +
    'remove lines use the whole-line anchor ("old").';
  SR_FRAG_EMPTY =
    '[EDIT-005 INVALID_PARAM] "fragment" is empty or contains U+FFFD (you read ' +
    'the file with a generic tool). Copy the piece from delphi_read.';
  SR_FRAG_BEYOND_FMT =
    '[EDIT-006 INVALID_PARAM] atline=%d does not exist in %s, which has %d ' +
    'lines.';
  SR_FRAG_NOTFOUND_FMT =
    '[EDIT-007 NOT_FOUND] The fragment |%s| does not appear on line %d (the ' +
    'comparison is case-sensitive). Nothing was written. The real line ' +
    'is:'#10 +
    '  %s'; // la cita, de su compositor (Lsp.Mascara.CitaDeLinea)
  SR_FRAG_SEVERAL_FMT =
    '[EDIT-008 INVALID_PARAM] The fragment |%s| appears %d times on line %d, ' +
    'and I will not guess which one. Nothing was written. Lengthen it ' +
    'with what is next to it until it is unique. The real line is:'#10 +
    '  %s'; // la cita, de su compositor (Lsp.Mascara.CitaDeLinea)
  // EDIT-009 ("new" igual a "fragment") se retiro el 28-sep: era un ERROR
  // donde la edicion suelta dice una NOTA (EDIT-113, sin cambios); ahora un
  // fragment que no cambia nada va por ese mismo camino.

  SP_PATCH_EDITS =
    'SEVERAL edits on THIS SAME file, in a single call and ALL OR ' +
    'NOTHING: a JSON array [{"old":"...","new":"...","atline":12}, ...] ' +
    'applied IN ORDER. Each entry accepts two forms of anchor: ONE LINE ' +
    '(the same as a single edit) or a BLOCK of several consecutive lines ' +
    'in "old", searched for whole and in order - useful for replacing in ' +
    'one piece the body of a method or a long documentation paragraph. ' +
    'If the anchor appears more than once, break the tie with ' +
    '"occurrence": 1, 2... (better than "atline" inside a batch: line ' +
    'numbers MOVE as earlier entries add or remove lines, and ' +
    '"occurrence" does not: it counts on the file as it was BEFORE the ' +
    'batch, so if one entry changes occurrence 1, the next entry asks ' +
    'for 2, not for 1 again; two entries on the same line are refused). ' +
    '"delete": true removes the line (a BLANK one: "atline" and no ' +
    '"old"); and with "toline": <number> the ' +
    'anchor stops being ONE line and becomes a RANGE - from the anchor''s ' +
    'line to that one, both included - that is removed whole (delete) or ' +
    'replaced by "new". It is the way to drop a method without pasting ' +
    'it whole as an anchor. Inside a batch the range shifts too: if an ' +
    'earlier entry added or removed lines, "toline" is corrected on its ' +
    'own; with "toline", "old" is ONE line (a block already says what it ' +
    'replaces: EDIT-020). If an entry fails, the file goes back byte for ' +
    'byte to how it was and you are told which one failed. At most 50 ' +
    'entries per call (EDIT-026). For a LONG line, an entry ' +
    'can carry "fragment" instead of "old": ' +
    '{"fragment":"68","new":"69","atline":12} changes only that piece of ' +
    'line 12 (atline mandatory, and the piece exactly once in it). If ' +
    'the change touches SEVERAL files, that is delphi_changeset. "edits" ' +
    'is the whole call: old/new/fragment/delete are another mode ' +
    '(EDIT-111) and atline/toline go INSIDE each entry (EDIT-115).';

  { "edits" en delphi_textedit: un resumen que se sostiene solo - un
    ToolsOnly= puede dar la hermana sin delphi_edit. En delphi_edit sigue el
    largo: con Glimmer, el corto desempataba peor las anclas repetidas de un
    lote (medido el 5-oct-2026; a Qwen3.8 le iba al reves). fragment y toline
    ya son un solo texto para las tres (SP_PATCH_FRAGMENT, SP_PATCH_TOLINE). }
  SP_PATCH_EDITS_CORTO =
    'SEVERAL edits on THIS SAME file in ONE all-or-nothing call: a JSON ' +
    'array [{"old":"...","new":"...","atline":12}, ...] applied in order. ' +
    'An entry anchors on ONE line or on a BLOCK of consecutive lines; ' +
    '"occurrence": N breaks a tie (counted on the file BEFORE the batch, ' +
    'so it does not move like atline); "delete": true removes (a blank ' +
    'line: atline, no old); "toline" ' +
    'makes the anchor the first line of a range; "fragment" + "atline" ' +
    'changes a piece of a long line. If one entry fails, the file goes ' +
    'back byte for byte and you are told which one. At most 50 entries ' +
    'per call. Several files: delphi_changeset.';

  { Los campos de una entrada de tanda se leen a mano, uno a uno, asi que un
    nombre que no existe no daba "Unknown parameter" como en los parametros
    de la tool: se IGNORABA. Una errata ("occurence" con una r, "atlines")
    dejaba la entrada haciendo otra cosa -la de por defecto- y contestando
    OK. Descubierto el 2026-09-20 al medir la bateria del rango contra el
    binario anterior: "toline" entraba sin protestar y no hacia nada. }
  { Pedir la ocurrencia 5 de algo que aparece 3 veces no fallaba: la
    resolucion devolvia 0, el motor lo leia como "sin desempate" y la edicion
    caia en la PRIMERA aparicion. O sea que el parametro que existe para no
    equivocarse de sitio te mandaba justo al sitio equivocado, con un OK. }
  SR_PATCH_OCCURRENCE_DUP_FMT =
    '[EDIT-010 INVALID_PARAM] Entries %d and %d point at the SAME line (%d). ' +
    '"occurrence" counts on the file as it was BEFORE the batch, not on ' +
    'what is left as it goes: if the earlier entry changes occurrence 1, ' +
    'this one has to ask for 2 (or anchor by atline). Nothing was ' +
    'written.';
  SR_PATCH_OCCURRENCE_FMT =
    '[EDIT-011 INVALID_PARAM] Entry %d asks for occurrence %d of "%s", ' +
    'and there are only %d. Nothing was written. Re-read with ' +
    'delphi_read and count, or lengthen the anchor until it is unique.';
  { La guarda de occurrence (David, 9-oct-2026): un ancla que TRAE sangria y
    la linea que elige occurrence lleva otra. Nunca se escribe en la
    "probable": se dicen las candidatas, citadas (CitaDeLinea) con su numero
    de occurrence (SF_PATCH_SANGRIA_CANDIDATA_FMT), para contestar a la
    primera. El consejo es occurrence y no atline: los numeros son del
    fichero de ANTES de la tanda, occurrence se arrastra con las entradas
    anteriores y atline no (revisor propio). %d = la entrada, %d = la
    ocurrencia pedida, %d = su linea, %s = esa linea, %s = las que casan con
    la sangria del ancla o SF_PATCH_SANGRIA_NINGUNA. }
  SR_PATCH_OCCURRENCE_SANGRIA_FMT =
    '[EDIT-121 INVALID_PARAM] Entry %d: occurrence %d of that anchor is ' +
    'line %d, and its indentation is not the one your anchor carries. ' +
    'Indentation does not count when occurrences are counted, so I do not ' +
    'guess which line you meant. Nothing was written.'#10 +
    'The one occurrence chose:'#10'%s'#10 +
    'The ones indented as your anchor:'#10'%s'#10 +
    'The line numbers are those of the file BEFORE the batch. Send the ' +
    'entry again with "occurrence" set to the K of the one you mean: it ' +
    'counts that same file and follows the lines earlier entries add or ' +
    'remove (atline does not), in a block too.';
  SF_PATCH_SANGRIA_NINGUNA =
    '  (none: no line that matches your anchor carries its indentation - ' +
    'send the anchor with the indentation of the line you mean, or the ' +
    'occurrence of the one above if it is that one)';
  { Las candidatas de EDIT-121 que no caben en la lista, con sus K para poder
    elegirlas: %d = cuantas, %s = sus occurrence separadas por comas. }
  SF_PATCH_SANGRIA_MAS_FMT =
    '  ...and %d more: occurrence %s';
  { Una candidata de EDIT-121 (David, 9-oct-2026: "line N = occurrence K",
    que orienta): %d = su linea, %d = su occurrence, %s = la linea citada. }
  SF_PATCH_SANGRIA_CANDIDATA_FMT =
    'line %d = occurrence %d -> %s';

  SR_PATCH_EDIT_KEY_FMT =
    '[EDIT-012 INVALID_PARAM] Entry %d of "edits" has the field "%s", ' +
    'which does not exist. The fields of an edit are: %s (all ' +
    'lowercase). Nothing was written.';

  SR_PATCH_EDIT_NO_TEXTO_FMT =
    '[EDIT-107 INVALID_PARAM] Entry %d: "%s" must be a text (a JSON ' +
    'string), not an object, an array, a number or a boolean. Nothing ' +
    'was written.';

  SR_EDIT_MODOS_NO_COMBINAN_FMT =
    '[EDIT-111 INVALID_PARAM] These modes do not combine in one call: %s. ' +
    'Nothing was done: send them in separate calls, one mode per call.';

  { Un parametro que no es del modo de la llamada: se ignoraba en silencio
    ("content" sin create / createunit, sexta revision; code sin insert,
    eol sin create, atline con edits..., septima: la regla general,
    Lsp.Guard.ParametroQueNoVa). }
  SR_EDIT_NO_VA_CON_MODO_FMT =
    '[EDIT-115 INVALID_PARAM] "%s" does not go with %s (it would be ' +
    'ignored). Nothing was done: %s takes %s.';

  SR_EDIT_NO_SE_ESCRIBIO_FMT =
    '[EDIT-112 DENIED] Could not write %s: %s';

  SN_EDIT_SIN_CAMBIOS_FMT =
    '[EDIT-113] UNCHANGED: line %d of %s already says exactly that, so ' +
    'nothing was written and no backup was taken.';

  SR_PATCH_EDIT_VALOR_FMT =
    '[EDIT-110 INVALID_PARAM] Entry %d, "%s": %s Nothing was written (the ' +
    'same rule as the whole-number and true/false parameters of the call).';

  SR_PATCH_BLOCK_SHORT =
    '[EDIT-013 INVALID_PARAM] That multi-line "old" is left with a single line ' +
    'once its final line break is removed. A single line needs nothing ' +
    'special: send it as it is.';

  { Por que no casa un ancla de UNA linea (Lsp.Patch.AnclaPerdida, el
    texto de delphi_edit y de delphi_textedit). Decian cosas distintas de
    la misma regla, y delphi_edit contestaba "no aparece" a un texto que
    estaba DENTRO de una linea (26-sep-2026). }
  SR_ANCLA_DENTRO_FMT =
    '[EDIT-092 INVALID_PARAM] That is not a whole line of %s: it is INSIDE one ' +
    '(below). The anchor ("old") is the COMPLETE line, copied from ' +
    'delphi_read (the indentation may be missing); to change only that ' +
    'piece: fragment=<that text> atline=<its number> and new. Nothing ' +
    'was written.';
  SR_ANCLA_NO_ESTA_FMT =
    '[EDIT-093 NOT_FOUND] The anchor does not appear in %s. Nothing was ' +
    'written.'#10 +
    'Anchor searched for: |%s|';
  SN_ANCLA_COPIALA =
    '[EDIT-014] Copy the literal line from delphi_read (do not rebuild ' +
    'it from memory).';
  SN_ANCLA_BLANCOS_FMT =
    '[EDIT-094] NOTE: line %d has that SAME text with other spaces or tabs ' +
    'around it: the indentation does not count, but the END of the line ' +
    'does (trailing blanks included). Copy it as is:';
  SN_ANCLA_CONTIENEN =
    '[EDIT-095] Lines that CONTAIN it:';
  SN_ANCLA_PARECIDA_FMT =
    '[EDIT-096] The most similar REAL line is %d - compare it character ' +
    'by character:';
  SN_BLOQUE_LINEA_FALTA_FMT =
    '[EDIT-097] Line %d of your block is not WHOLE in the file: "%s".';

  SR_PATCH_BLOCK_MISSING_FMT =
    '[EDIT-098 NOT_FOUND] I cannot find that block of %d lines. The first ' +
    'line I look for is "%s". The block is compared WHOLE and in order ' +
    '(spaces at the ends of each line do not matter, the content does): ' +
    're-read with delphi_read and copy it from there.';

  SR_PATCH_BLOCK_AMBIGUOUS_FMT =
    '[EDIT-015 INVALID_PARAM] That block appears %d times (it starts with ' +
    '"%s"), so I do not know which one you mean. Add "occurrence": 1, ' +
    '2... to that entry, or lengthen the block until it is unique.';

  SN_PATCH_BLOCK_OK_FMT =
    '[EDIT-016] block of %d lines replaced (it started at line %d)';

  { EL RANGO: "old" ancla la PRIMERA linea y "toline" dice hasta donde. Un
    rango mal puesto se lleva codigo por delante sin que se vea en la
    respuesta, asi que las tres formas de ponerlo mal se rechazan antes de
    tocar el disco. }
  SR_RANGE_BACKWARDS_FMT =
    '[EDIT-017 INVALID_PARAM] toline=%d is BEFORE the line of the anchor ' +
    '(%d), so the range is backwards and there is nothing to remove. ' +
    '"old" marks the FIRST line of the range and "toline" the LAST, both ' +
    'included.';

  SR_RANGE_BEYOND_FMT =
    '[EDIT-018 INVALID_PARAM] toline=%d, but %s has %d lines. Re-read ' +
    'the range with delphi_read and copy the number of the last line ' +
    'that goes.';

  SR_RANGE_WHOLE_FMT =
    '[EDIT-019 DENIED] That range (1-%d) takes the WHOLE file. This tool ' +
    'does not empty files, just as it does not rewrite them whole. If ' +
    'what you want is to remove it, delphi_delete sends it to the trash ' +
    'and it can be recovered.';

  SR_RANGE_WITH_BLOCK =
    '[EDIT-020 INVALID_PARAM] "toline" does not combine with a ' +
    'MULTI-line anchor: either the block says what is replaced, or the ' +
    'range does. With "toline", "old" is ONE single line, the first of ' +
    'the range.';

  SR_RANGE_WRONG_MODE_FMT =
    '[EDIT-021 INVALID_PARAM] "toline" belongs to the EDIT/DELETE mode ' +
    '(an "old" anchor and how far the range goes) and here you asked for ' +
    '%s, which does not work by lines. I stopped it instead of ignoring ' +
    'it: a parameter swallowed silently is how you end up believing you ' +
    'deleted something that is still there.';

  SN_RANGE_DELETED_FMT =
    '[EDIT-022] DELETED %d lines (from %d to %d) of %s';

  SN_RANGE_REPLACED_FMT =
    '[EDIT-023] REPLACED %d lines (from %d to %d) of %s';

  SR_PATCH_EDITS_JSON_FMT =
    '[EDIT-024 INVALID_PARAM] "edits" must be a JSON array of objects, for ' +
    'example [{"old":"  FList: TList;","new":"  FList: ' +
    'TObjectList<TItem>;"}]. If you send it from a command line, put it ' +
    'in a file and use the @file form, so the console does not mangle ' +
    'it. %d characters arrived, starting with: %s';

  SR_PATCH_EDITS_EMPTY =
    '[EDIT-025 INVALID_PARAM] "edits" is empty. Without operations there is ' +
    'nothing to apply.';

  SR_PATCH_EDITS_TOOMANY_FMT =
    '[EDIT-026 DENIED] Too many edits at once (the limit is %d). If you ' +
    'really have to touch that many lines of the same file, almost ' +
    'certainly what you want is to rewrite it whole: delphi_changeset ' +
    'with delete + create.';

  SR_PATCH_EDITS_NOFILE_FMT =
    '[EDIT-027 NOT_FOUND] %s does not exist.';

  SR_PATCH_EDITS_ROLLED_FMT =
    '[EDIT-099 INVALID_PARAM] ROLLBACK: edit %d of %d failed and the file went ' +
    'back byte for byte to how it was. NOTHING was applied, not even the ' +
    'earlier ones. This is what happened:'#10 +
    '%s'#10 +
    'Fix that entry (re-read the file with delphi_read and copy the ' +
    'literal anchor) and send them all again.';

  { Una tanda en la que NINGUNA entrada cambia nada: decia APPLIED y
    prometia una copia que no existia (sexta revision). }
  SN_PATCH_EDITS_SIN_CAMBIOS_FMT =
    '[EDIT-114] UNCHANGED: none of the %d edits changes %s (each one ' +
    'already says what the file says), so nothing was written and no ' +
    'backup was taken.';

  SN_PATCH_EDITS_OK_FMT =
    '[EDIT-028] APPLIED %d edits on %s, all or none:'#10 +
    '%s'#10 +
    'Previous copy of the file in __delphi-patch (one per day and file: ' +
    'the first one of the day is the original from before all this).';

  SN_EDIT_DUP_ABOVE_FMT =
    '[EDIT-029] NOTE: line %d (just ABOVE) is identical to the first ' +
    'line you just inserted: "%s". It almost always means you sent the ' +
    'anchor repeated inside "new". It compiles the same and it does not ' +
    'show; look at the file.';

  SN_EDIT_DUP_BELOW_FMT =
    '[EDIT-030] NOTE: line %d (just BELOW) is identical to the last line ' +
    'you just inserted: "%s". It is usually the anchor sent twice inside ' +
    '"new".';

  SR_READ_RANGE_FMT =
    '[READ-001 INVALID_PARAM] The range is backwards (from=%d, to=%d) ' +
    'and the file has %d lines, so there is nothing to return. Swap the ' +
    'two numbers.';

  { Lo que delphi_list y delphi_search NO ensenan: la cabecera y una parte
    por motivo, solo las que no son cero (THiddenCount.Report, en
    Lsp.References). Cada parte dice que es y como verlo. }
  SN_HIDDEN_HEAD_FMT =
    '[LIST-012] %d entries are not shown here:';
  SN_HIDDEN_ARTIFACTS_FMT =
    '[LIST-003] %d are in build folders (Win32, Win64, Debug, Release, ' +
    'dcu, __history, __recovery, __pycache__): they exist on disk, pass that folder as root to ' +
    'see them or download the output with delphi_package + delphi_fetch';
  SN_HIDDEN_TEMP_FMT =
    '[LIST-004] %d are server temporaries (__delphi-temp): they never ' +
    'show, not even with includetrash, because nothing is restored from ' +
    'there; if a tool gave you a path inside it, delphi_fetch downloads ' +
    'it';
  SN_HIDDEN_GIT_FMT =
    '[LIST-005] %d are git plumbing (.git): look at the repository with ' +
    'delphi_git';
  SN_HIDDEN_TRASH_FMT =
    '[LIST-006] %d are trash copies (__delphi-patch): delphi_list with ' +
    'includetrash=true shows them';
  SN_HIDDEN_FOLDERS_FMT =
    '[LIST-007] %d are folders of other tools (.vs, .github, ' +
    '.idea...), which dirs mode does not show: pass one as root to ' +
    'see inside';

  { Las marcas de dueno (.by) se cuentan aparte: la nota las llamaba
    "live files" (octava revision). }
  SN_LIST_SHOWN_TRASH_FMT =
    '[LIST-008] Of the %d entries, %d are trash copies (__delphi-patch) ' +
    'and %d their owner markers (.by), listed because includetrash=true; ' +
    'the rest are live files.';

  { En cada list sin pattern: corta (revisor de tokens, 4-oct-2026). Saber si
    el filtro escondio algo de verdad costaria otro paseo por el arbol; y un
    filtro que nadie menciona se lee como "no hay nada mas". }
  SN_LIST_DEFAULT_MASK =
    '[LIST-009] Delphi files only (no "pattern"): pattern=* lists ' +
    'everything.';

  { Una lista que no cabe en una pagina: la siguiente, y DONDE esta lo que
    no cabe (byFolder). Cortaba en 500 y lo de detras no se alcanzaba (Hermes,
    5-oct-2026: las 500 primeras eran copias de backups\). }
  SN_LIST_CAPPED_FMT =
    '[LIST-010] Here are %d of %d entries. The next page is offset=%d; ' +
    'byFolder says where they are, and one of those folders as root (or a ' +
    'pattern, *.pas) narrows it down.';

  SR_LIST_ROOT_IS_FILE_FMT =
    '[LIST-011 INVALID_PARAM] "%s" is a FILE, not a folder, so there is nothing ' +
    'to list. To see inside it use delphi_read; for its folder, pass the ' +
    'folder.';

  // BUILD-002 (recoger el binario con delphi_package + delphi_fetch) iba en
  // cada build correcto; se retiro el 4-oct-2026: lo dice delphi_package.

  // ---------------------------------------------------------------------
  // Access control
  // ---------------------------------------------------------------------
  SR_READ_ONLY_FMT =
    '[READ-002 DENIED] READ-ONLY access. The operation "%s" modifies the ' +
    'server machine and this credential does not allow it. What each tool ' +
    'allows in this mode is announced by tools/list: annotations.readOnlyHint, ' +
    'and _meta.access with readOnlyCommands (and readOnlyWhen) for the mixed ' +
    'ones. delphi_report is available to tell us about any problem.';

  SR_GIT_OPTION_FMT =
    '[GIT-003 DENIED] The git option "%s" is not allowed (it can write ' +
    'files, read outside the repository or run a command).';

  // The gate used to read an argument with an exact, case-SENSITIVE name while
  // the RTTI binder resolves it ignoring case and "_". Two keys that differ
  // only in those made the gate inspect one value and the tool receive the
  // other. Duplicates are never legitimate - no client emits them - so they
  // are refused instead of guessing which one wins.
  SR_ARG_DUPLICATE_FMT =
    '[GUARD-013 INVALID_PARAM] You sent the parameter "%s" twice (uppercase and ' +
    '"_" do not make it different). Send each parameter ONCE, with the ' +
    'exact name tools/list gives in "inputSchema".';

  // delphi_build composes a cmd.exe line (rsvars.bat && msbuild ...) and
  // platform/config/target travel through it UNQUOTED: a metacharacter there
  // IS a shell, and it would sail past the jail, the test container
  // and the .dproj hazard scanner in a single call. delphi_config
  // already armoured the same token for the XML sink; this is its twin mouth.
  SR_BUILD_PLATFORM_FMT =
    '[BUILD-003 INVALID_PARAM] "%s" is not a valid Delphi platform. See the ' +
    'platforms the project has with delphi_config command=view, and use ' +
    'one of them exactly as written.';

  SR_BUILD_TARGET_FMT =
    '[BUILD-004 INVALID_PARAM] "%s" is not a valid target. Use Build (full), ' +
    'Make (incremental), Clean or Deploy (builds and deploys: to the ' +
    'PAServer of the profile parameter on Linux/macOS, or packages the ' +
    'app on Android). After changing platform use Build.';

  { ...y si lo que vino en target es una PLATAFORMA (el conjunto cerrado de
    CanonicalPlatform), la pista: "target" se lee como "target platform"
    (Hermes, 5-oct-2026). }
  SF_BUILD_TARGET_ES_PLATAFORMA_FMT =
    ' "%s" is a platform: it goes in platform=%s, and target says what to ' +
    'do with it.';

  SN_BUILD_MANIFEST_NEW =
    '[BUILD-005] No .deployproj existed, so a MINIMAL deployment ' +
    'manifest was generated next to the project (the project output ' +
    'only, exec bit on). GUI apps need the richer manifest the IDE ' +
    'Deployment Manager writes (shared libraries, assets); this one ' +
    'covers console/simple binaries.';

  SN_BUILD_DEPLOYED_FMT =
    '[BUILD-006] Deployed through profile "%s". On the target machine ' +
    'the files are under the PAServer scratch directory (default ' +
    '~/PAServer/scratch-dir) in %s-%s/%s/ (PAServer names the folder ' +
    '<windows user>-<profile>) - executables arrive with their exec bit ' +
    'set, ready to run there. That folder is REWRITTEN on every deploy: ' +
    'whatever the app stored next to its binary (a data\ folder, a local ' +
    'database, a key file) is gone with it - copy it elsewhere before ' +
    'redeploying if a test needs it. deployedFiles counts what this run ' +
    'shipped (only with verbosity=verbose: quiet and normal do not print ' +
    'the copies); if it is missing there, nothing was sent: check the ' +
    'manifest with delphi_config command=view (deployFiles) and add the ' +
    'missing entries with add-deployfile.';

  { W1033 en un paquete: units de OTROS paquetes compiladas dentro del
    nuestro. El IDE ensena la lista y pregunta si anadirlos al requires
    (David, 2026-09-23); aqui la lista va en la respuesta y el agente decide. }
  SN_BUILD_REQUIRES_FMT =
    '[BUILD-007] This package compiled %d units of OTHER packages into ' +
    'itself (W1033 implicitly imported): a duplicate of their code, ' +
    'which the IDE would have offered to fix by adding those packages to ' +
    'the requires clause; implicitImports lists the units.%s%s';
  SN_BUILD_REQUIRES_KNOWN_FMT =
    ' [BUILD-008] Their packages, read from the BPLs this install ships: ' +
    '%s. Add them with delphi_config command=add-requires requires="%s" ' +
    'and build again.';
  SN_BUILD_REQUIRES_UNKNOWN_FMT =
    ' [BUILD-009] No BPL of this install declares these units, so their ' +
    'package is not known here (a third-party package outside bin\, or ' +
    'units of your own that belong in contains): %s.';
  { Punto 8 (Hermes 2026-09-23, David 24-sep): units de un .dpk del PROPIO
    workspace. Solo pista: compilar e instalar paquetes no es cosa del server. }
  SN_BUILD_REQUIRES_WORKSPACE_FMT =
    '[BUILD-010] These units belong to packages of YOUR workspace, not ' +
    'to this install: %s. Build that package FIRST (until it compiles ' +
    'there is no .dcp to require), then add-requires it here and build ' +
    'again. Installing a package in the IDE is the operator''s job, never ' +
    'yours.';

  SN_BUILD_QUIET_DEPLOYED =
    '[BUILD-011] msbuild only prints the deploy copies at ' +
    'verbosity=verbose, so deployedFiles cannot be counted here. Repeat ' +
    'with verbosity=verbose if you need the count.';

  { E0017 sobre <job>.wait.exe = el vigia de un remote-run anterior sigue
    vivo porque su programa sigue corriendo en el target. El deploy borra
    la carpeta antes de copiar, asi que ademas puede haberse llevado el .pid
    de ese trabajo. Medido 2026-09-23 (192.168.1.10, GUI viva). }
  SN_BUILD_DEPLOY_LOCKED_FMT =
    '[BUILD-012] The deploy could not rewrite the project folder on the ' +
    'target: msbuild hit E0017 on the watcher of remote-run job %s, ' +
    'which is alive because THAT PROGRAM IS STILL RUNNING there. Stop it ' +
    'first (delphi_paserver command=kill profile=%s project=%s job=%s) and ' +
    'deploy again. Careful: this failed deploy may already have deleted ' +
    'the job''s .pid on the target; if kill then answers JOB-006 (no job ' +
    'alive), close the program on the target by hand (delphi_desktop) ' +
    'before deploying.';

  SN_BUILD_DEPLOY_EMPTY_ENTRY =
    '[BUILD-013] The deployment manifest has an entry with an EMPTY ' +
    'local file for this platform (msbuild: Local file "" not found, ' +
    'skipped). Open it with delphi_config command=view (deployFiles) and ' +
    'fix or remove that entry.';

  SN_BUILD_MANIFEST_FILLED_FMT =
    '[BUILD-014] The project''s .deployproj had NO files for %s (the IDE ' +
    'writes an empty group for a platform it never deployed): the ' +
    'project output was added for Debug and Release, like the IDE''s ' +
    'Deployment Manager would. Extra files (a component''s .so) go in ' +
    'with delphi_config add-deployfile.';

  SR_BUILD_CONFIG_FMT =
    '[BUILD-015 INVALID_PARAM] The configuration "%s" has characters the build ' +
    'shell would interpret. A configuration is a simple name (letters, ' +
    'digits, space, ".", "_" and "-"): Debug, Release, or whatever your ' +
    'project declares. See the declared ones with delphi_config ' +
    'command=view.';

  // delphi_delete/delphi_move park their target in a trash folder created
  // NEXT TO it. For a ROOT that folder lands in the root's PARENT - a write
  // OUTSIDE the jail - and the whole workspace disappears in one call. The
  // root is the jail, not content.
  SR_ROOT_ITSELF_FMT =
    '[GUARD-014 DENIED] "%s" is a WORKSPACE ROOT (the jail itself), not ' +
    'a working file: deleting or moving it would take the whole project ' +
    'with it and leave the backup OUTSIDE the jail. Delete or move what ' +
    'is INSIDE it (delphi_list shows it to you). Changing the roots is ' +
    'the operator''s job, in settings.ini [Workspace.<name>] Roots.';

  SR_AGENT_CONFINED_FMT =
    '[GUARD-015 DENIED] The server is in confined mode and you (agent ' +
    '"%s") can only WRITE inside your folder <root>\%s\... (or in a ' +
    'shared folder the operator has declared). You can read everything; ' +
    'you can write only what is yours. Create/edit under your folder, or ' +
    'ask the operator to mark that folder as shared.';

  SR_REFERENCE_ROOT_FMT =
    '[GUARD-016 DENIED] "%s" is in a REFERENCE project of this workspace ' +
    '(ReadOnlyRoots: %s). It is read, searched, navigated and its git ' +
    'consulted, but it is not written, not compiled (compiling writes ' +
    'dcu and exe) and not moved: it is there to learn how things are ' +
    'done in-house, not to change it. Your work goes in the roots of ' +
    'delphi_workspace.';

  SN_WORKSPACE_REFERENCE_NOTE =
    '[WS-003] readOnlyRoots are REFERENCE projects: read, search, ' +
    'navigate, git query and fetch work there exactly like in your ' +
    'roots; every write, build, test, move and delete is refused. They ' +
    'are there to learn how things are done in this house, and they win ' +
    'over roots: a folder in both is read-only. delphi_projects lists ' +
    'them with readOnly:true.';

  SR_JAIL_FMT =
    '[GUARD-002 DENIED] "%s" is OUTSIDE the allowed workspaces. This ' +
    'server only operates inside: %s (configured in DELPHI_MCP_ROOTS or ' +
    'settings.ini [Workspace.<name>] Roots).';

  { La ruta de RED de un sitio que el operador declaro con su letra (una
    unidad de red conectada), mandada por un agente. Sigue negada: cada
    sitio vale en la forma en que se declaro. Con el mensaje de la jaula,
    el enmascarador de salida la ensenaba ya traducida a esa letra, y la
    negativa se contradecia: "srvx:\a esta FUERA; solo se trabaja en
    srvx:\" (segundo revisor de la 1.8.2). El %s es la forma declarada:
    sale con su unidad virtual, que es la que el agente puede usar. }
  SR_JAIL_FORMA_DE_RED_FMT =
    '[GUARD-029 DENIED] That is the network path of "%s", a place this ' +
    'server declares by its drive. A place is taken only in the form it ' +
    'was declared in: use that one.';

  { El modo local (un proceso sin workspace activo) cerrado al cargar: por
    que (SF_CIERRE_*). A quien llama se le dice que no es cosa suya. }
  SR_LOCAL_CERRADO_FMT =
    '[GUARD-030 DENIED] This server process admits nothing in its local ' +
    'mode: %s. It does not depend on your call: it is the operator''s to ' +
    'fix, and the startup log of the server names what.';

  SF_CIERRE_PROTECCION =
    'an entry of DELPHI_MCP_READONLY_ROOTS, DELPHI_MCP_READONLY_PATHS or ' +
    'DELPHI_MCP_VAULT_PATH was not loaded, and what it names could be ' +
    'written';

  { Un proceso lanzado con un token (stdio) cuando su settings.ini no se pudo
    leer: el workspace de ese token puede estar en el (revisor propio,
    9-oct-2026). }
  SF_CIERRE_INI_SIN_LEER =
    'it was started with a token, and the settings.ini that says whose ' +
    'workspace it opens could not be read';

  SF_CIERRE_WORKSPACE_FMT =
    'the token it was started with is the one of [Workspace.%s], and that ' +
    'workspace is closed';

  SR_ROOTS_INVALID =
    '[WS-004 DENIED] [Workspace.<name>] Roots is configured but none of ' +
    'its paths is valid (extra quotes, a drive that does not exist...). ' +
    'For safety everything is refused until settings.ini / ' +
    'DELPHI_MCP_ROOTS is fixed.';

  // An unserved "srvz:" used to be expanded to the REAL "Z:\", so the
  // rejection echoed a drive letter of the host - and the outbound mask only
  // covers served letters, so it came back raw. Probing srva: .. srvz: told
  // the client which drives the machine has (field round 10). Unserved units
  // never touch the filesystem now; this says so without naming anything the
  // client cannot already get from delphi_workspace.
  SR_UNIT_UNKNOWN_FMT =
    '[CFG-006 DENIED] "%s" is not a drive of this server. The valid ' +
    'drives are: %s. Ask for the paths with delphi_workspace and use ' +
    'them exactly as the server returns them.';

  // This is a pure DEVELOPMENT/COMPILE server: nothing runs on it except a
  // test project (AllowTests). Running a compiled artifact belongs on a real
  // target through remote-run (delphi_run, execution here, retired 2026-09-23).
  // A build must never EXECUTE code on a compile-only server. If the project
  // carries shell-running / file-planting MSBuild tasks, refuse the build
  // (unless build scripts were opted into) - field round 7: upload could plant
  // a .dproj whose <Target><Exec> ran arbitrary commands at build time. An inert
  // custom <Target> (Message/PropertyGroup only) is NOT refused (field round 9).
  { Wrong KIND of file, which is not the same as a missing one. Until
    2026-09-20 there was no type check at all and the hazard scan below stood
    in for it: CHANGELOG.md was "refused" for an <Exec> task it does not have
    (the word appears in prose describing that very guard) while LICENSE,
    which contains no "exec" anywhere, sailed past and MSBuild was spawned on
    the text of an MIT licence. "error:" and not "RECHAZADO:" on purpose
    (rule 11): nothing was denied, the argument does not fit - correct it and
    repeat. }
  SR_BUILD_NOT_A_PROJECT_FMT =
    '[BUILD-016 INVALID_PARAM] "%s" is not a Delphi project. ' +
    'delphi_build compiles a .dproj, or the .dpr/.dpk next to one. Find the project with ' +
    'delphi_projects, or look at the ones in a folder with delphi_list.';

  { El .dproj no se pudo LEER para comprobar que no ejecuta nada: se
    compilaba igual, con el escaner mirando un texto vacio (sexta revision:
    fallaba ABIERTO). Ahora no se compila. }
  SR_BUILD_DPROJ_ILEGIBLE_FMT =
    '[BUILD-045 DENIED] I could not read %s to check that the build runs ' +
    'nothing (%s), so it is not built. If another process holds it, ' +
    'close it and repeat.';

  { Una plataforma que el proyecto no declara (o tiene desactivada) no se
    compila: lo que compila un agente lo tiene que compilar igual el operador
    en el IDE sin reconfigurar (Lsp.Dproj.PlataformaNoDeclarada). }
  SR_BUILD_PLATAFORMA_NO_DECLARADA_FMT =
    '[BUILD-046 DENIED] %s is not an enabled platform of this project ' +
    '(enabled: %s), so it is not built: the IDE would not build it without ' +
    'adding it, and what is built here has to build the same there. ' +
    'delphi_config command=add-platform platform=%s declares it as the IDE ' +
    'does (for a remote one, sdk= and profile= go in the same call).';

  SR_BUILD_HAZARD_FMT =
    '[BUILD-017 DENIED] The project contains %s. This server only ' +
    'COMPILES, never executes, and that task would run a program or ' +
    'write files during the build. Compile a .dproj without execution ' +
    'tasks (a <Target> that only prints a message or sets a property IS ' +
    'accepted; a pre/post build event for signing or copying is not ' +
    'refused either: it is compiled without running it and the answer ' +
    'says so). For a trusted project to really run its tasks, the ' +
    'operator enables it with [Workspace.<name>] AllowBuildScripts=1.';
  SN_BUILD_EVENTS_SKIPPED =
    '[BUILD-018] Compiled WITHOUT running the project''s pre/post build ' +
    'events (signing, copies, EurekaLog...): this server only compiles. ' +
    'The binary is good for testing and running while you work; the ' +
    'final, signed version is compiled by the operator outside this ' +
    'server, where those events run. With AllowBuildScripts=1 in the ' +
    'workspace they would run.';

  SR_BUILD_RESERVED_PROP_FMT =
    '[BUILD-019 DENIED] The project (or something it imports) defines ' +
    '%s, a reserved IDE property. The <Import>s of ' +
    'CodeGear.Common.Targets and CodeGear.Profiles.Targets (and the ' +
    'UserTools.proj of every .dproj) resolve the file they load through ' +
    'it, and this server trusts those IDE <Import>s without reading ' +
    'them: redefining it diverts one of them to a file the project ' +
    'chooses, and that way code is loaded and executed during the build ' +
    'WITHOUT a visible <Import> in the .dproj. This server only ' +
    'compiles, never executes: remove that property from the project and ' +
    'from what it imports (delphi_config does not write it). For a ' +
    'trusted project to really run its tasks, the operator enables it ' +
    'with [Workspace.<name>] AllowBuildScripts=1.';

  // ---------------------------------------------------------------------
  // vault_* (knowledge vault: Markdown notes linked with [[wikilinks]])
  // These descriptions ARE the doctrine the agent sees: lazy loading, write
  // in the vault's language, log vs progress discipline, read the write-rules before
  // creating. What can be enforced by code lives in Mcp.Tools.Vault.
  // ---------------------------------------------------------------------
  SD_VAULT_SEARCH =
    'Searches the knowledge vault (Markdown notes linked with ' +
    '[[wikilinks]]). PROTOCOL: when starting a task, first call ' +
    'vault_read WITHOUT path to get the rules and the index; decide from ' +
    'the index descriptions which notes to load with vault_read - lazy ' +
    'loading, never read the vault in bulk.';

  SD_VAULT_READ =
    'Reads a note of the knowledge vault by relative path. WITHOUT path ' +
    'it returns the rules (AGENTS-VAULT.md) + the index (MEMORY.md): do ' +
    'that when starting. The [[wikilinks]] in the content refer to other ' +
    'notes - locate them with vault_search target=files. NOTE: the vault ' +
    'this server serves is the one its operator has exposed (the ' +
    'VaultPath= of YOUR [Workspace.<name>] in settings.ini), which may ' +
    'be a COPY and not the user''s live folder: if something sounds ' +
    'outdated, ask before taking it as good.';

  SD_VAULT_APPEND =
    'Appends content to an existing vault note (log entries, progress ' +
    'updates). Write in the vault''s language (AGENTS-VAULT-WRITE.md says ' +
    'which). Log format: dated entry under the section of the day. In ' +
    'progress.md respect its snapshot structure: live status lines, the ' +
    'history goes in log - do not accumulate; if you close a matter, ' +
    'delete its line with vault_patch instead of adding "done". The ' +
    'server keeps a copy of the original before writing.';

  // "el indice que corresponda" sent agents straight into the governance
  // wall: they read it as MEMORY.md, vault_patch refused it every time, and
  // the note was left created but unlinked (defontsito's field report,
  // 2026-09-11). The instruction now names the ONLY index they can edit
  // (the project's own notes) and spells out the human path for MEMORY.md.
  SD_VAULT_CREATE =
    'Creates a new note in the vault. BEFORE creating: read ' +
    'AGENTS-VAULT-WRITE.md (decision tree of where each thing goes, and ' +
    'templates) and link the note with [[wikilinks]] from the project ' +
    'notes (context.md, log.md, progress.md) - NOT from MEMORY.md: that ' +
    'root index is governance and is always refused; if the note ' +
    'deserves an entry there, ask for it in your answer or in a ' +
    'delphi_report and a person will do it. Write in the vault''s ' +
    'language (AGENTS-VAULT-WRITE.md says which). Do not reorganize ' +
    'folders or move existing notes - that requires a human OK. It never ' +
    'overwrites: if the note exists, it is refused.';

  SD_VAULT_PATCH =
    'Targeted edit of a note: replaces old_text (UNIQUE in the file) ' +
    'with new_text. For striking closed lines of a progress or ' +
    'correcting a fact. To add content use vault_append; for large ' +
    'rewrites, stop and ask the user. The server keeps a copy of the ' +
    'original before writing.';

  // Handed to the model in the initialize response when a vault is configured
  // - unless the vault ships its own VAULT-INSTRUCTIONS.md, which wins. Short
  // on purpose: instructions travel in EVERY prompt of every client, so the
  // heavy doctrine stays behind vault_read (no path).
  SD_VAULT_INSTRUCTIONS =
    'This server gives access to a KNOWLEDGE VAULT: Markdown notes ' +
    'linked with [[wikilinks]] holding the conventions, patterns, ' +
    'decisions and status of each project. PROTOCOL when starting any ' +
    'task: (1) call vault_read WITHOUT path - it returns the vault rules ' +
    'and the note index; (2) identify the project you are working on and ' +
    'load its context.md and its progress.md; (3) the other notes, only ' +
    'on demand when the index says they apply (lazy loading - never read ' +
    'the vault in bulk). If the vault allows writing, read ' +
    'AGENTS-VAULT-WRITE.md first and respect the vault''s language.';

  SD_VAULT_PROMPT =
    'Loads the knowledge vault bootstrap: its rules and the note index. ' +
    'Use it when starting, or to reload the index in the middle of a ' +
    'long session.';

  SF_VAULT_PROMPT_HEADER =
    'These are the rules and the index of this server''s knowledge vault. ' +
    'Work with lazy loading: load only the notes the index says apply to ' +
    'your task, with vault_read.';

  // Decia "este servidor no tiene vault configurado ([Vault] Path)" y las dos
  // mitades eran falsas desde v0.98: el servidor PUEDE tener vault (el de otro
  // workspace) y la clave [Vault] Path ya no existe. Un agente que leyera eso
  // le contaba a su operador algo que no es y lo mandaba a una seccion que no
  // esta (medido el 2026-09-20 con un servidor de dos workspaces, uno con
  // vault y otro sin el).
  SR_VAULT_UNSET =
    '[VAULT-035 DENIED] YOUR workspace declares no knowledge ' +
    'vault. The vault belongs to the ACTIVE workspace: it is declared ' +
    'with VaultPath= in its [Workspace.<name>] section of the server''s ' +
    'settings.ini (and VaultReadOnly=0 if it must also be writable). ' +
    'These tools appearing here only means that SOME workspace of this ' +
    'server has a vault, not that it is yours. If you need it for your ' +
    'work, ask for it with delphi_report.';

  SR_VAULT_PROMPT_NO_EXISTE_FMT =
    '[VAULT-041 NOT_FOUND] Prompt "%s" does not exist (prompts/list ' +
    'names the ones there are).';

  // No echo of the offending path on purpose: the outbound filter rewrites
  // server drive letters, so echoing "C:/Windows/win.ini" came back as
  // "srvc:/Windows/win.ini" - something the agent never sent, confusing to
  // debug (field round 8). The rule itself is what the agent needs.
  // The vault is reachable ONLY through the vault_* tools, wherever it lives -
  // including inside a workspace root. Otherwise delphi_edit could rewrite a
  // note behind the vault's back: no automatic backup, and the governance
  // files (rules and index) would stop being protected.
  SR_VAULT_NOT_CODE =
    '[VAULT-002 DENIED] That path belongs to the KNOWLEDGE VAULT, which ' +
    'is not touched with the code tools. Use vault_read / vault_search ' +
    'to consult it (and vault_append / vault_create / vault_patch if ' +
    'this server allows writing to it): that way a backup copy is kept ' +
    'and its rules are respected.';

  SR_VAULT_WOULD_EMPTY =
    '[VAULT-003 DENIED] That replacement would leave the note EMPTY, and ' +
    'deleting knowledge is not an operation of this server (there is no ' +
    'delete and no full rewrite, by design). If the note really has to ' +
    'be removed, tell the user and let a person do it.';

  SR_VAULT_JAIL =
    '[VAULT-004 DENIED] That path leaves the vault. Use a RELATIVE path ' +
    'inside the vault (projects/x/context.md): no drives, no absolute ' +
    'paths and no "..". Locate notes with vault_search target=files.';

  SN_VAULT_MORE_FMT =
    #10 +
    '[VAULT-036] --- Showing lines %d..%d of %d. Ask for the rest with ' +
    'vault_read {offset: %d} (and limit if you want smaller chunks).';

  SR_VAULT_TARGET_FMT =
    '[VAULT-005 INVALID_PARAM] target="%s" does not exist. There are ' +
    'only two: files (searches the NAMES of the notes, with glob: *.md, ' +
    '*delphi*) and content (searches INSIDE the text, with a regular ' +
    'expression). Default: files.';

  SN_VAULT_SHOWN_FMT =
    #10 +
    '[VAULT-037] --- Showing lines %d..%d of %d (to the end).';

  SR_VAULT_PAST_END_FMT =
    '[VAULT-006 INVALID_PARAM] offset %d is past the end: "%s" has %d ' +
    'lines. Ask from offset=1 or from a line that exists.';

  SN_VAULT_BOOTSTRAP =
    '[VAULT-038] # Vault bootstrap: the rules (AGENTS-VAULT.md) and the ' +
    'index (MEMORY.md).'#10 +
    'Lazy loading: use the index to decide which notes to open with ' +
    'vault_read; do not read the whole vault.'#10#10;

  // When rules + index do not fit in one result, the split is between FILES:
  // the first arrives whole and the second is asked for by name. Never half a
  // file - and it mirrors how the vault is read locally, one file per read.
  SN_VAULT_BOOTSTRAP_NEXT_FMT =
    #10 +
    '[VAULT-007] --- Missing %s (it does not fit together with the above ' +
    'in a single answer). Ask for it whole with vault_read {path: "%s"}.';

  // Decia "en este servidor ([Vault] ReadOnly=1)" y otra vez las dos mitades
  // estaban caducadas: el ajuste es del WORKSPACE y la clave se llama
  // VaultReadOnly. Ademas se daba esta respuesta cuando el workspace NO tenia
  // vault (ver SR_VAULT_UNSET), que es otra cosa.
  SR_VAULT_READONLY =
    '[VAULT-008 DENIED] The vault of YOUR workspace is READ-ONLY ' +
    '(read-only is the default; VaultReadOnly=0 in its ' +
    '[Workspace.<name>] section of the server''s settings.ini opens it ' +
    'for writing). You can consult it with vault_read and vault_search; ' +
    'if you need to write to it, ask for it with delphi_report.';

  SR_VAULT_GOVERNANCE =
    '[VAULT-009 DENIED] AGENTS-VAULT.md, AGENTS-VAULT-WRITE.md and ' +
    'MEMORY.md are the GOVERNANCE files of the vault (its rules and its ' +
    'index) and are only touched under human supervision. You can read ' +
    'them (vault_read without path). If a new note needs indexing, say ' +
    'so in your answer or send it in a delphi_report so a person does ' +
    'it; the note you created is valid anyway even if it is not in the ' +
    'index yet.';


  // ---------------------------------------------------------------------
  // delphi_paserver (connection profiles against a live PAServer)
  // The profile file is written by paclient.exe itself (--local), so the
  // format - password encrypted included - is always the IDE's own, never
  // invented here. --passfile was measured and REJECTED for add-profile:
  // it stores the passfile PATH in the profile, leaving the password in
  // plain text on disk forever; --password stores it encrypted inside.
  // ---------------------------------------------------------------------
  { Lo que cada subcomando hace vive en SP_PASERVER_COMMAND; aqui se contaba
    otra vez (revisor de tokens, 4-oct-2026): queda el mapa y lo que solo
    decia este texto. }
  SD_PASERVER =
    'The bridge for building and running on OTHER platforms (Linux, macOS) ' +
    'through PAServer: its installers, this server''s connection profiles ' +
    'and SDKs, and running what a project deployed on the target (each ' +
    'subcommand in "command"). The first time: packages (download the ' +
    'installer with delphi_fetch and run it on the target) -> add-profile ' +
    '(the password is stored encrypted) -> test-connection -> get-sdk (the ' +
    'libraries the linker needs, once per target and again after an OS ' +
    'upgrade there; minutes) -> delphi_build for that platform -> ' +
    'delphi_build target=Deploy -> remote-run. Enabling a platform in a ' +
    'project is delphi_config.';

  SP_PASERVER_COMMAND =
    'platforms (default: what this server can target + profile/SDK status) ' +
    '| packages (PAServer installers to download and run on the target) | ' +
    'profiles (connection profiles and SDKs) | reseat (write the missing ' +
    'IDE seats of profiles already on disk; no PAServer, no password) | ' +
    'add-profile (profile, host, password; optional port, platform. The host ' +
    'must be allowed in the workspace''s RemoteHosts: registering a profile ' +
    'IS declaring where this machine may connect. An existing name is ' +
    'refused, never overwritten; the profile shows in the IDE too) | ' +
    'remove-profile (that profile, from the IDE too; profiles live outside the ' +
    'workspace, so there is no trash: a copy of its file is kept first in the ' +
    'server''s own folder and the answer says where) | test-connection (with profile: full ' +
    'handshake; with host+port and no profile: raw TCP probe, same host rule) ' +
    '| get-sdk (pull the sysroot from the PAServer of "profile" into ' +
    'a folder of its own named after the target distro, registered for ' +
    'delphi_build AND the IDE SDK Manager; minutes. An .sdk file or SDK ' +
    'record it replaces is copied first and the answer says where: ' +
    'previousSdkCopy, previousSdkRecordCopy) | reseat-sdk (rewrite ' +
    'the IDE seat of an SDK already on disk, no network; "sdk" names one, ' +
    'none = all) | remove-sdk (its .sdk file - copied first: removedCopy - and IDE seat; the sysroot ' +
    'stays on disk and the answer says where) | remote-run (run what THAT ' +
    'project deployed on the target of "profile" - nothing else - and ' +
    'return exit code and output; nothing to install, PAServer runs it. On ' +
    'timeout it is NOT killed: a program with a window stays up, you get ' +
    'its partial output and stillRunning=true) | kill (stop a job a ' +
    'remote-run left running: profile, project and its job id; only a job of ' +
    'THAT project on THAT machine) | output (what a running job wrote ' +
    'SINCE its answer: so far while it lives; once it ended, all of it ' +
    'with its exit code, and then it is deleted on the target; same profile, ' +
    'project and job as kill)';
  SP_PASERVER_PROJECT =
    'remote-run, kill, output: the ABSOLUTE path of the .dproj (or its .dpr) whose ' +
    'DEPLOYED program it is (not its name); the server derives the path on ' +
    'the target (<user>-<profile>/<Project>/<Project>, what target=Deploy ' +
    'wrote) - nothing else there can be run.';
  SP_PASERVER_EXE =
    'remote-run OPTIONAL: another file of that same deploy folder to run ' +
    'instead of the project binary - a plain file name, no path.';
  SP_PASERVER_ARGS =
    'remote-run: optional command-line arguments for the program (no shell ' +
    'metacharacters)';
  SP_PASERVER_TIMEOUT =
    'remote-run: max milliseconds to wait for the program (default 30000, ' +
    'max 300000)';
  SP_PASERVER_NAME =
    'The PAServer connection profile, by name (letters, digits, "_", "-") - ' +
    'the same "profile" delphi_build and delphi_desktop take: add-profile ' +
    'creates it; test-connection, get-sdk, remote-run, kill and output use it';
  SP_PASERVER_HOST =
    'Host or IP where the target PAServer listens (add-profile, or ' +
    'test-connection without profile for a raw TCP probe)';
  SP_PASERVER_PORT =
    'Port of the target PAServer (add-profile / test-connection). ' +
    'Default: 64211';
  SP_PASERVER_PASSWORD =
    'The PAServer password (add-profile). Used once to create the profile, ' +
    'stored encrypted, never shown back';
  SP_PASERVER_PLATFORM =
    'Platform of the profile, one that paclient takes (Linux64, OSX64, ' +
    'Win64...; a wrong one is refused with the list). Default: Linux64';

  { Un parametro que no es del comando (Lsp.Guard.ParametroQueNoVa; decima).
    Solo se nombra el parametro, nunca su valor (password). }
  SR_PASERVER_NO_VA_CON_COMANDO_FMT =
    '[PAS-051 INVALID_PARAM] "%s" does not go with command=%s (it would ' +
    'be ignored). Nothing was done: %s takes %s.%s';
  // lo que toma un modo sin parametros propios (Lsp.Guard.ParametroQueNoVa)
  SF_MODO_SIN_PARAMETROS =
    'no parameters';
  SF_PASERVER_NAME_ES_PROFILE =
    ' ("name" is the old spelling of "profile" here and is read as it; ' +
    'an SDK goes in "sdk".)';

  SR_PASERVER_CMD =
    '[PAS-001 INVALID_PARAM] Command must be platforms | packages | ' +
    'profiles | reseat | add-profile | remove-profile | test-connection ' +
    '| get-sdk | reseat-sdk | remove-sdk | remote-run | kill | output';
  { Lo que significa un salto de linea al FINAL de "new", dicho igual en
    delphi_edit, delphi_textedit y delphi_changeset (LineasDeNew, Lsp.Patch). }
  SP_NEW_SALTO_FINAL =
    '. A final line break is dropped; each extra one adds a blank line. ' +
    'Same rule for one-line and block anchors.';
  SP_PASERVER_JOB =
    'kill / output: the "jobId" a remote-run answer gave you; with profile ' +
    'and project (the same .dproj path) - only a job of THAT project on ' +
    'THAT machine.';
  SR_PASERVER_JOB_NEEDS_FMT =
    '[PAS-002 INVALID_PARAM] %s needs "profile", "project" (the ' +
    '.dproj of that remote-run) and "job" (the jobId it returned). Only ' +
    'a job this server started for that project on that machine is ' +
    'touched.';
  SR_REMOTERUN_BADJOB =
    '[RUN-001 INVALID_PARAM] "job" is not a job id of this server ' +
    '(date-time-fragment, as remote-run returns it).';
  SN_REMOTERUN_KILL_FMT =
    '[RUN-002] If it hung or you no longer need it: delphi_paserver ' +
    'command=kill profile=%s project=<the same .dproj> job=%s. It kills ' +
    'only that job: nothing else on that machine.';
  SN_REMOTERUN_KILL_NOTE =
    '[RUN-003] kill stops ONLY the program that job started (the ' +
    'launcher reads the <job>.pid its watcher left, in the folder of ' +
    'THAT project): with killed=false and the launcher''s JOB-006 note, ' +
    'there was nothing to kill. The ___RC of the killed job is written ' +
    'by its watcher into its own output: you read it with command=output ' +
    'and the same job.';
  SN_REMOTERUN_OUTPUT_FMT =
    '[RUN-004] What it writes from now on -an error on closing, its exit ' +
    'code- you read with delphi_paserver command=output profile=%s ' +
    'project=<the same .dproj> job=%s: while it lives, what it has so ' +
    'far; once it ends, all of it and its code, and then it is deleted ' +
    'from the target.';
  SN_REMOTERUN_OUTPUT_ALIVE_FMT =
    '[RUN-005] Still alive: this is what it has written so far. Ask ' +
    'again whenever you want; once it ends it brings everything and its ' +
    'exit code, and then it is deleted from the target. To stop it: ' +
    'command=kill profile=%s project=<the same .dproj> job=%s.';
  SN_REMOTERUN_OUTPUT_DONE =
    '[RUN-006] Finished: its whole output and its exit code. Read in ' +
    'full, it has been deleted from the target (like a mailbox): asking ' +
    'for it again brings nothing.';
  SR_REMOTERUN_NO_OUTPUT_FMT =
    '[RUN-018 NOT_FOUND] There is no output of job %s on the target: ' +
    'either it was already read in full (a finished output is deleted ' +
    'when read), or it ended before its remote-run returned (and you ' +
    'already had it in its answer), or that job does not belong to this ' +
    'project on that machine.';

  SR_REMOTERUN_PROJECT_DENIED_FMT =
    '[RUN-007 DENIED] The project "%s" is not in the list of projects ' +
    'this server allows to run on a target ([Workspace.<name>] ' +
    'RemoteRunProjects). Allowed: %s. Only the operator extends that list, ' +
    'in the server''s settings.ini: it is what may run on a target, so no ' +
    'tool changes it - ask the operator.';

  SR_REMOTERUN_NODO_DENIED_FMT =
    '[RUN-020 DENIED] delphi_desktop works through this server''s own ' +
    'desktop node (%s), and seeing and typing on a target''s desktop is a ' +
    'permission of its own: the operator grants it by adding %0:s (or all) ' +
    'to [Workspace.<name>] RemoteRunProjects in the server''s settings.ini. ' +
    'No tool changes that list - ask the operator.';

  SR_PASERVER_RUN_DISABLED =
    '[PAS-003 DENIED] Remote execution is OFF on this server. The ' +
    'operator turns it on with [Workspace.<name>] AllowRemoteRun=1 in ' +
    'the settings.ini next to the executable (or the variable ' +
    'DELPHI_MCP_ALLOW_REMOTE_RUN=1) and restarts the server. Also, only ' +
    'the binary that project deployed is run, and only if the project is ' +
    'in [Workspace.<name>] RemoteRunProjects.';

  SR_PASERVER_RUN_NEEDS =
    '[PAS-004 INVALID_PARAM] remote-run needs "profile" (the PAServer profile) and ' +
    '"project" (the .dproj whose deployed program you want to run). The ' +
    'server derives the path on the target: ' +
    '<user>-<profile>/<Project>/<Project>. Nothing else on the remote ' +
    'machine is run.';

  SR_PASERVER_RUN_NOPROJ_FMT =
    '[PAS-005 NOT_FOUND] The project %s does not exist on this server. ' +
    'remote-run runs what that .dproj has deployed (delphi_build ' +
    'target=Deploy).';

  SR_PASERVER_RUN_EXENAME =
    '[PAS-006 INVALID_PARAM] "exe" is optional and, if given, must be a file ' +
    'NAME of that project''s deploy folder (no "/", no "\" and no ".."). ' +
    'By default the project binary is run.';

  SR_REMOTERUN_NO_PACLIENT =
    '[RUN-008 INTERNAL] The RAD Studio this server uses ships no ' +
    'bin\paclient.exe: without it there is no transport to PAServer.';

  SR_REMOTERUN_NOPROJLIST =
    '[RUN-009 DENIED] This workspace does not declare ' +
    'RemoteRunProjects, so it cannot run ANYTHING on a target (it fails ' +
    'closed: what is not declared does not exist). The operator adds ' +
    'RemoteRunProjects=<proj1>;<proj2> to this workspace''s section in ' +
    'settings.ini.';

  SR_REMOTERUN_PUT_FMT =
    '[RUN-010 DENIED] Could not send the job to the target ' +
    '(paclient exit %d): %s. Is PAServer alive? Does the profile point ' +
    'to the right host?';
  SR_REMOTERUN_NO_RUNJOB_FMT =
    '[RUN-011 INTERNAL] The launcher node\%s is missing next to the ' +
    'server. PAServer only starts a binary without arguments: that ' +
    'launcher is what reads the job and runs the program (it ships in ' +
    'the release, node folder: McpRunJob for a Linux, McpRunJob.exe for ' +
    'a Windows).';
  SN_REMOTERUN_ENV_WIN_FMT =
    '[RUN-012] Windows: the program runs in interactive session %s of ' +
    'the PAServer user, with a desktop';
  SN_REMOTERUN_ENV_WIN0 =
    '[RUN-013] Windows: PAServer runs as a SERVICE, in session 0, which ' +
    'has no desktop: a program with a window will not be seen or be ' +
    'operable. Start PAServer inside the user''s session (from their ' +
    'desktop)';
  SN_REMOTERUN_ENV_INHERITED =
    '[RUN-014] inherited from PAServer: DISPLAY/WAYLAND_DISPLAY were ' +
    'already set, nothing to add';
  SN_REMOTERUN_ENV_ADDED_FMT =
    '[RUN-015] the target''s PAServer runs OUTSIDE the graphical session ' +
    '(a service): the script has filled in %s from the open session, so ' +
    'a program with a window starts anyway';
  SN_REMOTERUN_ENV_NONE =
    '[RUN-016] no graphical session on the target: neither DISPLAY nor ' +
    'WAYLAND_DISPLAY, and no X or Wayland socket of the PAServer user. A ' +
    'console program runs anyway; one with a window will die on startup ' +
    '(GTK, exit 134). An open session on the target with the SAME user ' +
    'that runs PAServer is needed';
  SN_REMOTERUN_TIMEOUT_FMT =
    '[RUN-019] the program IS STILL RUNNING on the target: it had not ' +
    'finished after %d s and it is NOT killed, because an application ' +
    'with a window is meant to stay up. In "output" you have what it had ' +
    'written so far, and what it writes later you read with ' +
    'command=output (outputNote). If you expected something that ' +
    'finishes, give it more time with timeoutms; if it is a GUI, it is ' +
    'already running and you can operate it with delphi_desktop (folder ' +
    '%s of the target).';

  SN_REMOTERUN_NOTE =
    '[RUN-017] Run on the target by PAServer, with nothing installed ' +
    'there. Only the NATIVE BINARY that project deployed is run, in its ' +
    'folder of the scratch dir - never the rest of the machine, and ' +
    'never a script in that folder (the file signature is checked, not ' +
    'its extension). exitCode/output come from the program. If ' +
    'stillRunning=true appears, it did not finish in time and is still ' +
    'alive: "output" brings its PARTIAL output, and the rest -up to its ' +
    'exit code- is read later with command=output.';

  SR_SHELL_META_FMT =
    '[SYS-003 DENIED] The argument contains "%s", a shell metacharacter ' +
    'that would break the command line. Remove it.';

  SR_PASERVER_SDK_PLATFORM_FMT =
    '[PAS-007 DENIED] get-sdk covers the Linux64 platform today and ' +
    'profile "%s" is for %s. For other platforms (macOS needs a real Mac ' +
    'with PAServer) report it with delphi_report: that is the signal to ' +
    'build them.';

  SR_CONFIG_SDK_PLATFORM_FMT =
    '[CFG-007 INVALID_PARAM] "%s" is not a valid Delphi platform. Valid: ' +
    '%s.';

  SR_CFG_NEED_SDK_FMT =
    '[CFG-105 INVALID_PARAM] Missing "sdk": the SDK to pin for %s ' +
    '(registered: %s), or "none" to remove the pin. Nothing was written.';

  SR_CFG_NEED_PROFILE_FMT =
    '[CFG-106 INVALID_PARAM] Missing "profile": the PAServer profile to ' +
    'pin for %s (registered: %s), or "none" to remove the pin. Nothing ' +
    'was written.';

  { add-platform con sdk/profile es UN gesto: si una parte se rechaza, el
    .dproj vuelve como estaba (Mcp.Tools.Config). }
  SN_CONFIG_ADDPLATFORM_NADA =
    '[CFG-008] Nothing written: the platform has NOT been added EITHER ' +
    '(platform, SDK and profile go in a single step; fix it and repeat ' +
    'the whole thing).';
  SR_CONFIG_SDK_NOEXISTE_FMT =
    '[CFG-009 NOT_FOUND] There is no SDK called "%s". Registered for %s: ' +
    '%s. They are brought in with delphi_paserver command=get-sdk (one ' +
    'per target machine, each in its own folder).';

  SN_CONFIG_SDK_PUESTO_FMT =
    '[CFG-010] The project will compile %s with SDK %s (before: %s). It ' +
    'is the PlatformSDK property, the same one the IDE sets in Project ' +
    'Options, so it applies to delphi_build and to compiling from the ' +
    'IDE. Prior copy of the .dproj in __delphi-patch.';

  SN_CONFIG_SDK_QUITADO_FMT =
    '[CFG-011] The project no longer pins an SDK for %s (before: %s): it ' +
    'will go back to using the one the SDK Manager has as default for ' +
    'that platform. Registered: %s.';

  SR_BUILD_SDK_NOEXISTE_FMT =
    '[BUILD-020 NOT_FOUND] I have no SDK called "%s". Registered for this ' +
    'platform: %s. They are brought in with delphi_paserver ' +
    'command=get-sdk (one per target machine, each in its own folder).';

  SR_BUILD_SDK_VARIOS_FMT =
    '[BUILD-021 INVALID_PARAM] There are SEVERAL SDKs for %s and nobody says ' +
    'which one to use: %s. I do not choose - linking against the wrong ' +
    'sysroot gives a binary that dies on the target with "GLIBC_2.xx not ' +
    'found". Pass sdk=<name> in this call, or pin it in the project ' +
    '(PlatformSDK) so you never have to repeat it.';

  SN_BUILD_SDK_PROYECTO_FMT =
    '[BUILD-022] The SDK is set by the project (PlatformSDK=%s); I have ' +
    'not touched it.';

  SN_BUILD_SDK_DEFAULT_FMT =
    '[BUILD-023] I compiled with %s, which is the default SDK for this ' +
    'platform in the IDE SDK Manager. There is more than one (%s): for ' +
    'another, pass sdk=<name> or pin it in the project (PlatformSDK) and ' +
    'you will not have to repeat it.';

  SN_BUILD_SDK_ELEGIDO_FMT =
    '[BUILD-024] I compiled with %s. There is more than one registered ' +
    '(%s): if this is not the one you wanted, pass sdk=<name> or pin it ' +
    'in the project.';

  SN_BUILD_SDK_MEZCLA_FMT =
    '[BUILD-025] WARNING: SDK %s points to a sysroot with TWO distros ' +
    'inside (%s): it has the Debian/Ubuntu tree and the Red Hat/Fedora ' +
    'tree at once, with two libc.so.6 and two gcc trees, and the paths ' +
    'of both go to the linker. What comes out of here compiles, but ' +
    'against a mix nobody chose. Fetch the SDK again with ' +
    'delphi_paserver command=get-sdk (now each machine goes to its own ' +
    'folder).';

  SP_PASERVER_SDK =
    'get-sdk optional: the NAME of the SDK folder to write. Default: the ' +
    'target distro from its /etc/os-release (zorin18, fedora44, ' +
    'ubuntu2404). Pass one to keep "the one this shop builds with". ' +
    'reseat-sdk: the SDK whose IDE seat is rewritten (none = all). ' +
    'remove-sdk: the SDK to remove, by name (command=profiles lists them).';

  SP_PASERVER_ACTIVE =
    'get-sdk optional: "yes" makes it the ACTIVE SDK of the platform (the ' +
    'bold entry of the IDE SDK Manager, used by projects that declare ' +
    'none). Default: nothing is touched - what a project builds with ' +
    'belongs to the project (delphi_config set-sdk) or to you.';

  SR_PASERVER_SDK_NOFILE_FMT =
    '[PAS-008 NOT_FOUND] I have no SDK called "%s" (delphi_paserver ' +
    'command=profiles lists them). They are brought in with ' +
    'command=get-sdk.';

  SN_PASERVER_SDK_REMOVED =
    '[PAS-009] Taken out of the way: its .sdk file and its SDK Manager ' +
    'seat (the IDE stops listing it on its next start). The SYSROOT ' +
    'stays ON DISK and it is gigabytes: the path is in ' +
    '"sysrootLeftBehind" and you delete it whenever you want. Deleting ' +
    'folders like that is not a job for a tool.';

  SN_PASERVER_SDK_RESEAT =
    '[PAS-010] SDK Manager seats rewritten from the SDKs already on disk ' +
    '- no network and nothing downloaded again. The IDE reads that list ' +
    'at STARTUP, so it will see them on its next start. If you still do ' +
    'not see them, the server that wrote the seat was not the one you ' +
    'started: relaunch it from your session and repeat.';

  SR_PASERVER_SDK_OTRA_FMT =
    '[PAS-011 DENIED] The SDK "%s" already exists and is for %s; this ' +
    'profile is for %s. I do NOT overlay it: two distros in the same ' +
    'folder leave two libc and two gcc trees, and the linker ends up ' +
    'mixing them without warning. Run get-sdk without "sdk" (it will be ' +
    'called %s) or give me another name.';

  SN_PASERVER_SDK_GENERIC_FMT =
    '[PAS-012] This sysroot has glibc %s. The rule to have ONE SINGLE ' +
    'SDK that works for all your Linux machines: ALWAYS compile with the ' +
    'OLDEST glibc in your fleet - a binary linked against an old glibc ' +
    'runs on the new ones, and the other way round it dies with ' +
    '"GLIBC_2.xx not found". delphi_paserver command=profiles lists the ' +
    'glibc of each SDK you have.';

  SN_PASERVER_SDK_MEZCLA_FMT =
    '[PAS-013] WARNING: %s has two distros INSIDE (the Debian/Ubuntu ' +
    'tree and the Red Hat/Fedora tree at once), so it carries two ' +
    'libc.so.6 and two gcc trees, and the paths of both go to the ' +
    'linker. It dates from when get-sdk dumped every target into a ' +
    'single folder. Download them again (now each one goes to its own) ' +
    'and delete this one by hand when you no longer need it.';

  SN_PASERVER_SDK_OK =
    '[PAS-014] SDK provisioned: the target libraries now live on this ' +
    'server, in a folder OF THEIR OWN, and the SDK is registered for ' +
    'msbuild and in the IDE SDK Manager - the same model RAD Studio uses ' +
    'for the Android SDKs: one folder per SDK, and the project says ' +
    'which one it builds with (delphi_build sdk=<name>, or the project''s ' +
    'own PlatformSDK). Note: C++ headers are NOT pulled (this server ' +
    'links Delphi); re-run get-sdk after OS/toolchain upgrades on the ' +
    'target.';

  SR_PASERVER_NAME_FMT =
    '[PAS-015 INVALID_PARAM] "%s" is not valid as a profile name. Use letters, ' +
    'digits, "_" or "-" (max 64): the name becomes a file <name>.profile ' +
    'on the server.';

  SR_PASERVER_HOST_FMT =
    '[PAS-016 INVALID_PARAM] "%s" is not valid as a host. Use a hostname or an ' +
    'IP (letters, digits, ".", "-" and ":" for IPv6), without spaces or ' +
    'quotes.';

  SR_PASERVER_PORT_FMT =
    '[PAS-017 INVALID_PARAM] "%s" is not a valid port (1-65535). PAServer ' +
    'listens on 64211 by default.';

  SR_PASERVER_PLATFORM_FMT =
    '[PAS-018 INVALID_PARAM] "%s" is not a paclient platform. Valid: %s.';

  SR_PASERVER_PASSWORD =
    '[PAS-019 INVALID_PARAM] The password contains double quotes or control ' +
    'characters, which would break the paclient command line. Set a ' +
    'password without those characters on the PAServer and call again.';

  SR_PASERVER_NO_PACLIENT =
    '[PAS-020 INTERNAL] The RAD Studio this server uses ships no ' +
    'bin\paclient.exe, which is needed to manage PAServer profiles.';

  SR_PASERVER_NEED_FMT =
    '[PAS-021 INVALID_PARAM] add-profile needs "%s". Parameters: profile (its ' +
    'name), host (IP or hostname of the PAServer), password (the ' +
    'PAServer one); optional port (default 64211) and platform (default ' +
    'Linux64).';

  SR_PASERVER_NO_PROFILE_FMT =
    '[PAS-022 NOT_FOUND] The profile "%s" does not exist. List the ' +
    'registered ones with command=profiles, or create one with ' +
    'command=add-profile (profile, host, password; optional port and ' +
    'platform). To know only whether there IS A ROUTE to your PAServer, ' +
    'call test-connection with host and port WITHOUT profile (TCP probe, no ' +
    'credentials).';

  SR_PASERVER_NEED_NAME =
    '[PAS-049 INVALID_PARAM] Missing "profile": the PAServer profile ' +
    '(command=profiles lists them).';

  SR_PASERVER_NEED_SDK =
    '[PAS-050 INVALID_PARAM] Missing "sdk": the name of the SDK (its ' +
    '.sdk file, e.g. fedora44).';

  SN_PASERVER_PROFILE_OK =
    '[PAS-023] Profile stored with the password encrypted inside, and ' +
    'REGISTERED in the IDE too (its Connection Profile Manager reads the ' +
    'registry, not the .profile folder - measured 2026-09-19). Verify ' +
    'the link with command=test-connection, then delphi_build with this ' +
    'platform builds against the target PAServer.';
  SR_PASERVER_PROFILE_EXISTS_FMT =
    '[PAS-024 DENIED] A profile "%s" already exists (it points to %s). A ' +
    'credential is not overwritten silently: use it as it is ' +
    '(test-connection profile=%0:s) or remove it first with ' +
    'command=remove-profile.';
  SN_PASERVER_DUP_HOST_FMT =
    '[PAS-025] NOTE: the profile "%s" already points to that same host ' +
    'and port - consider reusing it instead of duplicating profiles.';

  SN_PASERVER_CONNECTED =
    '[PAS-026] PAServer alive and credentials accepted. delphi_build can ' +
    'now target this platform through the profile.';

  SN_PASERVER_TCP_OK =
    '[PAS-027] TCP route open: this server reaches that host:port. This ' +
    'only proves the route - the full PAServer handshake with ' +
    'credentials is test-connection with a profile (add-profile ' +
    'first).';

  SN_PASERVER_TCP_FAIL =
    '[PAS-028] No TCP route from this server to that host:port. Check, ' +
    'in order: the PAServer is running and listening there; if the ' +
    'target is a container or behind NAT, the port is ' +
    'published/forwarded on the reachable host (and then use THAT host ' +
    'ip here); firewalls on both sides allow the port.';

  // ---------------------------------------------------------------------
  // delphi_adb (Android devices hanging off THIS server's machine/network)
  // ---------------------------------------------------------------------
  SR_FETCHTARGET_BADPATH =
    '[FETCH-001 INVALID_PARAM] The file to fetch is named RELATIVE to the ' +
    'folder the project deployed (e.g. "capture.png"). No absolute paths ' +
    'and no "..".';
  SR_FETCHTARGET_FAIL_FMT =
    '[FETCH-004 DENIED] Could not fetch the file from the target ' +
    '(paclient %d): %s';
  SR_FETCHTARGET_NOFILE_FMT =
    '[FETCH-005 NOT_FOUND] The target did not leave "%s" where expected: ' +
    'did the program that writes it run?';

  SD_ADBLINUX =
    'The desktop of the machine behind a PAServer profile (a Linux or ' +
    'Windows target, or this server itself when a PAServer runs in its ' +
    'user session), like adb for Android: SEE it and ACT on it. A small ' +
    'Delphi node does the work there; this server deploys and updates it ' +
    'by itself (leave "project" empty) - nothing else is installed or ' +
    'compiled on the target. THE FLOW: command=screenshot brings the whole ' +
    'desktop; measure the pixel you want on it and tap (or type, which ' +
    'presses there first) at that x,y - the node handles the screen scale. ' +
    'Every capture lists "windows" (title and rectangle in capture pixels; ' +
    'on Linux the X11/Xwayland ones, which is every FMX application - ' +
    'native Wayland windows show in the image but are not listed) and ' +
    'graphicalEnv. The target needs a graphical session open for the user ' +
    'PAServer runs as: a headless box, a locked Windows or a Windows ' +
    'service (session 0) has nothing to show (command=status says what to ' +
    'ask the operator for). It is a permission of its own: ' +
    'AllowRemoteRun=1, the profile''s host in RemoteHosts and ' +
    'McpDesktopNode (or all) in RemoteRunProjects - only the operator sets ' +
    'them, and a refusal names the missing one.';
  SP_ADBLINUX_COMMAND =
    'screenshot (default: the whole desktop as a PNG) | tap (press at x,y ' +
    'measured on that screenshot) | type (write "text"; with x,y it ' +
    'presses there first and pays the startup once (tap + type pays it ' +
    'twice). Typed means the keys were SENT: nothing checks ' +
    'where the focus was, so read the screenshot each answer brings) | key ' +
    '(one key: Linux code on a Linux target, key NAME on a Windows one) | ' +
    'overview (when one window covers another - Linux: the Super overview ' +
    'brings every window into view; Windows: only a fresh capture with the ' +
    'windows list) | ' +
    'status (is the desktop reachable, and what to ask for if not)';
  SP_ADBLINUX_PROFILE =
    'PAServer profile of the target machine - Linux, Windows, or this ' +
    'server in its user session (delphi_paserver command=profiles lists ' +
    'them). The desktop is THAT machine''s, never yours.';
  SP_ADBLINUX_PROJECT =
    'OPTIONAL: empty = the node bundled with this server, deployed on ' +
    'first use and updated when its version changes. A .dproj path only ' +
    'when you develop the node itself (deployed with delphi_build ' +
    'target=Deploy).';
  SP_ADBLINUX_X =
    'tap/type: horizontal pixel measured on the screenshot this tool ' +
    'returned (pass its frame too and the server converts)';
  SP_ADBLINUX_Y =
    'tap/type: vertical pixel measured on the screenshot this tool ' +
    'returned (pass its frame too and the server converts)';
  SP_ADBLINUX_MODIFIERS =
    'key OPTIONAL: keys held while it is pressed, comma separated - ctrl, ' +
    'shift, alt, super (Ctrl+K on Linux: code=37 modifiers=ctrl; Alt+F4 on ' +
    'Windows: code=f4 modifiers=alt). Pressed in that order and released ' +
    'in reverse.';
  SR_ADBLINUX_MODIFIERS_BAD_FMT =
    '[DESK-001 INVALID_PARAM] modifiers does not know "%s": the valid ones are ' +
    'ctrl, shift, alt and super (comma-separated).';
  SP_ADBLINUX_CODE =
    'key. Linux target: the evdev key code (NOT an X11 keycode): Escape 1, ' +
    'Tab 15, Enter 28, left Alt 56, Super 125. Windows target: the key ' +
    'NAME - escape, enter, tab, space, backspace, delete, home, end, up, ' +
    'down, left, right, super, alt, ctrl, shift, f1..f12, or a letter a..z. ' +
    'The other kind is refused.';
  SP_ADBLINUX_TEXT =
    'type: the text to write. Windows: typed as Unicode. Linux: key by key ' +
    'with the target''s own keyboard layout (Shift, AltGr, dead keys); a ' +
    'character it cannot compose (an emoji) is refused by name, and the ' +
    'answer says which keyboard was used. Typed as ' +
    'TEXT, never run. With x,y it presses there first to focus the field.';
  SR_ADBLINUX_NEEDTEXT =
    '[DESK-002 INVALID_PARAM] type needs "text". If you also pass x and y, it ' +
    'presses there before writing: that is the real gesture, "write this ' +
    'here", and it starts up only once.';
  SR_ADBLINUX_NONODE =
    '[DESK-021 INVALID_PARAM] delphi_desktop: neither "project" nor a ' +
    'bundled node for that system. Either the operator leaves the node ' +
    'next to the server (node\McpDesktopNode for a Linux, ' +
    'node\McpDesktopNode.exe for a Windows: the distribution ships both, ' +
    'and then it is deployed and updated by itself), or pass project= ' +
    'with the .dproj of the node deployed via delphi_build target=Deploy.';
  { UNA descripcion para el "out" de toda la familia de capturas, porque es
    UNA regla (CaptureTarget, Lsp.Guard). Va aqui arriba porque una constante
    se declara antes de su primer uso. }
  SP_CAPTURE_OUT_RULE =
    ': a FOLDER (existing, or ending in \ - the server names the file) ' +
    'or a FILE whose extension matches the capture''s real format. Empty ' +
    '= __delphi-temp\<agent>, wiped on server restart. On THIS server, jailed like any ' +
    'path. With inline=false the capture stays there and the answer ' +
    'carries its download link.';
  SP_ADBLINUX_OUT =
    'screenshot: where the capture lands' + SP_CAPTURE_OUT_RULE;
  SP_ADBLINUX_REGION =
    'screenshot OPTIONAL: "x,y,w,h" in desktop pixels - only that piece, ' +
    'at full resolution (every image is shrunk to one fixed size, so a ' +
    'crop is how you read a small dialog). The answer carries origin ' +
    '{x,y}: press at (origin.x + x, origin.y + y), or pass its frame. Not ' +
    'with window: for a piece of a window, add the window''s origin and use ' +
    'region. When in doubt (a dialog may open elsewhere), capture the ' +
    'whole desktop.';
  // Lsp.InlineImages: la entrega de una captura, la misma en toda tool que capture.
  // tambien la de un gesto (8.6 de la 1.18.0, Hermes: no sabia que tap la traia)
  SP_CAPTURE_INLINE =
    'Default true: the capture this answer brings - a screenshot, the one ' +
    'every gesture returns (tap, type, swipe...), a preview - comes back IN ' +
    'this answer as an image ' +
    '(scaled to maxwidth), and no file is kept to download later. false = a ' +
    'file and its ' +
    'download link (a client without vision, or one that wants the bytes).';

  SP_CAPTURE_MAXWIDTH =
    'Inline only: the width the image is scaled to before it travels (0 = ' +
    '1280). The answer says inlineScale: divide what you measure on the ' +
    'inline image by it to get capture pixels, or use the answer''s frame ' +
    '(a tap takes it, and delphi_desktop''s type too; preview''s converts ' +
    'to form units).';

  SN_CAPTURE_INLINE_NOTE_FMT =
    '[CAPT-001] The image is IN this answer (scaled %s of the capture). ' +
    'To press what you see, measure x,y ON THIS IMAGE and pass them to ' +
    'tap/type with frame (below): the server converts - never divide or ' +
    'add yourself. Its temp file was consumed: need it again, take ' +
    'another screenshot; inline=false gives file + download instead; a ' +
    'capture with out= is yours and stays.';

  SR_BORRADO_DENEGADO_FMT =
    '[GUARD-017 DENIED] NOT DELETING "%s": %s. The tree deleter only ' +
    'deletes inside a disposable folder of the server (temporaries, ' +
    'trash) or a temporary download of its own, and never a workspace ' +
    'root, the vault, the server folder or a system folder, nor anything ' +
    'that contains them.';

  SR_MUDANZA_PROTEGIDA_FMT =
    '[MOVE-001 DENIED] "%s" is not moved or deleted as a whole: it is or ' +
    'contains %s, which this workspace cannot write. Moving a folder or ' +
    'sending it to the trash takes EVERYTHING inside it. Move or delete ' +
    'separately what is inside that IS yours.';

  SN_LUGAR_PROTEGIDO =
    '[MOVE-008] a protected place (a workspace root, a reference ' +
    'project, a read-only folder or a system folder)';

  SR_MUDANZA_OTRA_UNIDAD_FMT =
    '[MOVE-002 DENIED] "%s" and "%s" are on different drives, and a ' +
    'folder only moves by RENAMING it on the same drive: whole or ' +
    'nothing. Across drives it would have to copy and delete file by ' +
    'file, which is left half-done if something fails, and crosses the ' +
    'links. To take it there: delphi_move copy=true and then ' +
    'delphi_delete of the source.';

  { ...y lo que es un VAULT (de las tools vault_*, de cualquier workspace):
    se copiaba el de OTRO workspace (octava revision). }
  SN_COPY_LINKS_NOT_FOLLOWED_FMT =
    '  [FILE-032] %d item(s) NOT copied: links that point to something ' +
    'this workspace cannot read (outside its roots, its ReadOnlyRoots and ' +
    'the library zone), or a knowledge vault (it belongs to the vault_* ' +
    'tools): %s. The rest has been ' +
    'copied. If that content is needed, the operator declares it in ' +
    'ReadOnlyRoots.';

  SN_CAPTURE_OUT_TEMP_HINT =
    '[CAPT-002] A capture does not need out: leave it out and the image ' +
    'arrives in the same answer, with no file to collect or pile up. ' +
    'out= is only for saving it in a folder of YOURS in the project.';

  SP_CAPTURE_FRAME =
    'tap (and type, on delphi_desktop): the "frame" of the screenshot you ' +
    'measured on, copied verbatim; then x,y are pixels of THAT image and ' +
    'the server converts them (inline scale, crop origin, device display). ' +
    'Without it, x,y are capture pixels.';

  SN_CAPTURE_FRAME_NOTE =
    '[CAPT-003] To press something you see in this image: tap (or type) ' +
    'with x,y measured ON THIS IMAGE and frame=<the frame above>, copied ' +
    'as it is. The server converts scale, crop origin and display for ' +
    'you.';

  SR_CAPTURE_FRAME_BAD_FMT =
    '[CAPT-004 INVALID_PARAM] frame "%s" does not have the shape of the ' +
    'captures (<width>x<height>@<width>x<height>+<x>+<y>). Copy it ' +
    'EXACTLY from the answer of the capture you measured on; nothing was ' +
    'pressed.';

  SR_CAPTURE_FRAME_OUT_FMT =
    '[CAPT-005 INVALID_PARAM] (%s,%s) falls outside the image of that frame ' +
    '(%dx%d). Measure on the image that frame came with, or ask for ' +
    'another capture; nothing was pressed.';

  SP_ADBLINUX_WINDOW =
    'screenshot OPTIONAL: part of a window title; the capture is cropped ' +
    'to the first window of "windows" whose title contains it ' +
    '(case-insensitive), with origin {x,y} like region, plus the whole ' +
    'list (a dialog outside the crop still shows there). A native Wayland ' +
    'window has no rectangle: use region. Not with region.';
  SR_ADBLINUX_REGION_OR_WINDOW =
    '[DESK-003 INVALID_PARAM] region and window do not combine: either a ' +
    'rectangle or a window.';
  SR_ADBLINUX_CROP_ONLY_SHOT =
    '[DESK-004 INVALID_PARAM] region and window are only valid with ' +
    'command=screenshot (the gestures are still on the whole desktop).';
  SR_ADBLINUX_REGION_BAD =
    '[DESK-005 INVALID_PARAM] region must be "x,y,w,h" with four integers and ' +
    'w,h > 0, in pixels of the desktop capture.';
  { La lista de ventanas viaja con cada captura (24-sep-2026): estas notas
    dicen que contiene en cada sistema, y en Linux como leer la vista que
    abre command=overview. }
  SN_DESKTOP_WINDOWS_WIN =
    '[DESK-006] windows: every visible top-level window, title and ' +
    'rectangle in pixels of THIS capture (tap inside one). To crop to ' +
    'one: screenshot window=<part of its title>.';
  SN_DESKTOP_WINDOWS_LINUX =
    '[DESK-007] windows: the X11/Xwayland windows -every FMX application ' +
    'is one-, title and rectangle in pixels of THIS capture. Native ' +
    'Wayland windows (the terminal, Files, a browser) do NOT appear in ' +
    'the list even though the capture shows them: for those, look at the ' +
    'image and use region. To crop to one of the list: screenshot ' +
    'window=<part of its title>.';
  SN_DESKTOP_OVERVIEW_LINUX =
    '[DESK-008] This capture was taken 0.8 s after pressing Super: it is ' +
    'the ACTIVITIES OVERVIEW, with each window drawn REDUCED and its ' +
    'application icon below it (with two windows they show almost at ' +
    'real size, side by side). Press on one to bring it to the front and ' +
    'leave the overview, or key code=1 (Escape) to close it without ' +
    'choosing. The "windows" list of this answer carries the REAL ' +
    'positions of the windows (the X11 ones), not where the overview ' +
    'draws them: to press one here, measure on the image.';
  SR_ADBLINUX_WINDOW_NOMATCH_FMT =
    '[DESK-022 NOT_FOUND] No visible window has "%s" in its title: look ' +
    'at "windows" in this same answer and repeat with part of one of ' +
    'those titles.';
  SN_ADBLINUX_CROP_NOTE_FMT =
    '[DESK-009] CROP of the desktop: pass to tap the x,y measured on ' +
    'THIS image with its frame and the server adds the origin; without ' +
    'frame, tap x=(%d + your x) y=(%d + your y). When in doubt (a dialog ' +
    'that opened outside it), capture the whole desktop. Download it ' +
    'with delphi_fetch';
  { Dos textos que sobrevivieron a delphi_desktop LOCAL (retirada en 1.0.16):
    los usa la tool por perfil cuando el destino es un Windows. }
  SN_DESKTOP_LOCKED =
    '[DESK-024] The desktop is LOCKED (or the session has no screen): ' +
    'Windows allows neither looking nor touching from here. It is the ' +
    'twin of the "no DISPLAY" of Linux. Ask the operator to unlock the ' +
    'session.';
  SR_DESKTOP_NEEDCODE =
    '[DESK-010 INVALID_PARAM] The target is Windows and key needs "code" with ' +
    'the key NAME: escape, enter, tab, space, backspace, delete, home, ' +
    'end, up, down, left, right, super, alt, ctrl, shift, f1..f12 or a letter ' +
    'a..z.';

  SR_ADBLINUX_CMD =
    '[DESK-011 INVALID_PARAM] command must be screenshot, tap, type, key, ' +
    'overview or status.';
  SR_ADBLINUX_NEEDPROFILE =
    '[DESK-012 INVALID_PARAM] "profile" is missing: the PAServer profile of the ' +
    'machine whose desktop you want (delphi_paserver command=profiles ' +
    'lists them).';
  SR_ADBLINUX_NEEDXY =
    '[DESK-013 INVALID_PARAM] tap needs x and y, measured on the screenshot ' +
    'that command=screenshot returns.';
  SR_ADBLINUX_NEEDCODE =
    '[DESK-014 INVALID_PARAM] key needs "code", the Linux code of the key ' +
    '(Escape 1, Tab 15, Enter 28).';
  { Por que una respuesta de delphi_desktop viene SIN captura, cuando toda
    (menos status) la trae en esta misma llamada (Lsp.RemoteRun.
    MotivoSinCaptura). Decia "el nodo no dijo donde dejo la captura": la
    fontaneria, no el motivo (David, 26-sep-2026). }
  SR_DESKTOP_SIN_CAPTURA_FMT =
    '[DESK-023 DENIED] No screenshot: %s.';
  SN_DESKTOP_MOTIVO_SIN_SESION =
    '[DESK-015] the target has no graphical session open (graphicalEnv): ' +
    'open one with the SAME user that runs PAServer and repeat';
  SN_DESKTOP_MOTIVO_DENEGADA =
    '[DESK-016] Windows denies it: the session is locked, disconnected ' +
    'or has no desktop (hint)';
  SN_DESKTOP_MOTIVO_NODO_FMT =
    '[DESK-017] the target could not take it (%s)';
  SN_DESKTOP_MOTIVO_NINGUNO =
    '[DESK-018] the node did not say why; its whole output is in ' +
    'nodeOutput';

  SD_ADB =
    'Android devices for remote development: phones/tablets hang off THIS ' +
    'server (USB or wifi adb) while you program from anywhere. Each ' +
    'subcommand is in "command"; discover gives the ip:port of what ' +
    'announces wireless debugging (no address to know up front), and ' +
    'connect makes the device ask for authorization the first time. The ' +
    'adb used is the one of the IDE''s own Android SDK. Building the .apk ' +
    'is delphi_build target=Deploy (the deployment manifest is generated ' +
    'if missing). screenshot (the screen, in this answer), tap and key are ' +
    'your eyes and hands on the device, and logcat shows what the app did. ' +
    'Typical flow: discover -> connect -> devices -> delphi_build ' +
    'target=Deploy -> install -> run -> screenshot -> tap -> logcat.';

  SP_ADB_COMMAND =
    'discover (devices announcing wireless debugging, by mDNS, with their ' +
    'ip:port) | devices (attached devices; default) | connect (over the ' +
    'network: address) | disconnect (address) | install (an .apk: apk, ' +
    'device) | run (launch an installed app: app, device - the IDE''s ' +
    'Deploy and Run) | logcat (the device log, bounded: device, optional ' +
    'filter and lines) | screenshot (the screen, in this answer: device, ' +
    'optional out) | tap (x, y measured on a screenshot, device) | key (a ' +
    'navigation key: key, device)';
  SP_ADB_ADDRESS =
    'ip:port of the device for connect/disconnect (from command=discover, ' +
    'or the device''s wireless-debugging screen)';
  SP_ADB_DEVICE =
    'Device serial or ip:port (from command=devices). REQUIRED for every ' +
    'command that touches a device, and it must be in the workspace''s ' +
    'AdbAllowedDevices: the device is named, never implied, even when only ' +
    'one is attached.';
  SP_ADB_APK =
    'Path of the .apk to install (inside the workspace)';
  SP_ADB_APP =
    'run: package name of the installed app to launch (e.g. ' +
    'com.embarcadero.MyApp - the build/install results state it)';
  SP_ADB_OUT =
    'screenshot, optional: where the capture lands' +
    SP_CAPTURE_OUT_RULE +
    ' logcat: an optional .txt/.log FILE to dump into instead of answering ' +
    'inline - read it in ranges with delphi_read.';
  SP_ADB_X =
    'tap: X measured on a screenshot; pass its frame and the server ' +
    'converts to display pixels. Without frame, X is display pixels ' +
    '(multiply by tapScale.x when the answer carried it).';
  SP_ADB_Y =
    'tap: Y measured on a screenshot; pass its frame and the server ' +
    'converts to display pixels. Without frame, Y is display pixels ' +
    '(multiply by tapScale.y when the answer carried it).';
  SP_ADB_KEY =
    'key: back | home | enter | appswitch | wakeup | up | down | left | ' +
    'right | tab';
  SP_ADB_FILTER =
    'logcat: only lines containing this text (e.g. your app tag or package). ' +
    'Optional';
  SP_ADB_LINES =
    'logcat: how many recent lines (default 300, max 5000; 0 = the ' +
    'default). An inline ' +
    'answer carries at most the newest 400 - for more, pass out=<file.txt> ' +
    'and read it in ranges.';

  { Un parametro que no es del comando (Lsp.Guard.ParametroQueNoVa; decima). }
  SR_ADB_NO_VA_CON_COMANDO_FMT =
    '[ADB-028 INVALID_PARAM] "%s" does not go with command=%s (it would ' +
    'be ignored). Nothing was done: %s takes %s.';

  SR_ADB_CMD =
    '[ADB-001 INVALID_PARAM] Command must be discover | devices | ' +
    'connect | disconnect | install | run | logcat | screenshot | tap | ' +
    'key';

  { El "out" de TODA la familia de capturas (delphi_desktop, delphi_adb_linux,
    delphi_adb): una regla y un texto, en CaptureTarget (Lsp.Guard). El
    formato lo dice la CAPTURA, no una constante: el dia que un nodo devuelva
    otra cosa que PNG, esto sigue siendo verdad sin tocarlo. }
  SR_CAPTURE_EXT_FMT =
    '[CAPT-006 INVALID_PARAM] The capture is %0:s and "out" names a %1:s file. ' +
    'Name the file %0:s, or pass a FOLDER (one that already exists, or ' +
    'ending in \) and I pick the name. I do not write an image with the ' +
    'extension of another format.';

  SR_ADB_NEED_XY =
    '[ADB-002 INVALID_PARAM] tap needs "x" and "y" (screen pixels; measure them ' +
    'on a command=screenshot).';

  SR_ADB_XY_FMT =
    '[ADB-003 INVALID_PARAM] "%s" is not valid as a screen coordinate (digits ' +
    'only).';

  SR_ADB_KEY_FMT =
    '[ADB-004 INVALID_PARAM] "%s" is not an allowed key. Use back | home | ' +
    'enter | appswitch | wakeup | up | down | left | right | tab.';

  SR_ADB_ALLOWLIST_FMT =
    '[ADB-005 DENIED] The device "%s" is not in the allowed list of this ' +
    'workspace (AdbAllowedDevices= in its section of settings.ini; ' +
    'absent = none). Outside that list, nothing. The operator extends it ' +
    'if appropriate.';

  SR_ADB_ALLOWLIST_DEVICE =
    '[ADB-006 INVALID_PARAM] Devices go by the workspace list ' +
    '(AdbAllowedDevices=): pass "device" explicitly with one from the ' +
    'list (command=devices lists them).';

  SR_ADB_GONE_FMT =
    '[ADB-007 DENIED] NO CONNECTION TO THE DEVICE. adb over wifi drops ' +
    'by itself after a while of inactivity - that is the device, not ' +
    'this server. What to do: retry command=connect to the SAME ip:port ' +
    '(on many devices the port persists); if it does not get in, have ' +
    'the developer re-enable wireless debugging on the device and find ' +
    'the new port with command=discover (Android 11+ randomizes it on ' +
    're-enable). command=devices says what is attached RIGHT NOW.'#10 +
    'adb said:'#10 +
    '%s';

  SR_ADB_FALLO_FMT =
    '[ADB-027 DENIED] exit=%d - adb did not do it; its own answer ' +
    'follows and says why:'#10 +
    '%s';

  SR_ADB_OUT_LOG =
    '[ADB-008 INVALID_PARAM] The logcat "out" must end in .txt or .log.';

  SN_ADB_LOGFILE =
    '[ADB-009] The dump is in this file ON THE SERVER. Read it in ranges ' +
    'with delphi_read (400 lines per call), search it with ' +
    'delphi_search, or download it to your machine with delphi_fetch.';

  SN_ADB_TAIL_FMT =
    '[ADB-010] (logcat: %d lines captured; here are the %d MOST RECENT. ' +
    'For the full dump repeat with out=<file.txt> and read it by ranges ' +
    'with delphi_read, or narrow it with filter.)';

  SN_ADB_SCREENSHOT =
    '[ADB-011] The device screen comes in this answer (with ' +
    'inline=false, as a file and its download link). Coordinates ' +
    'measured on it are exactly what command=tap takes: the image is the ' +
    'size of the display in force ("display": physical, override and ' +
    'density from wm size / wm density).';
  SN_ADB_TAP_SCALE_FMT =
    '[ADB-012] The device screen is in this PNG on the server - download ' +
    'it with delphi_fetch. CAREFUL: the image is %dx%d but the display ' +
    'in force is %dx%d, and command=tap takes DISPLAY pixels: multiply ' +
    'what you measure on the image by tapScale (x by %s, y by %s) before ' +
    'tapping - or simply pass frame with x,y measured on the image and ' +
    'the server converts.';

  SR_ADB_NEED_APP =
    '[ADB-013 INVALID_PARAM] run needs "app" (the installed package name, e.g. ' +
    'com.embarcadero.MyApp - the build and install results declare it).';

  SR_ADB_APP_FMT =
    '[ADB-014 INVALID_PARAM] "%s" is not valid as an Android package name. ' +
    'Letters, digits, ".", "_" and "-" (e.g. com.embarcadero.MyApp).';

  SR_ADB_NO_SDK =
    '[ADB-015 INTERNAL] This server has no Android SDK configured ' +
    '(there is no .sdk with SDKAdbPath). It is installed once with the ' +
    'IDE SDK Manager; after that this tool uses its adb.';

  SR_ADB_NEED_ADDRESS =
    '[ADB-016 INVALID_PARAM] connect/disconnect need "address" (ip:port of the ' +
    'device with wireless debugging on, e.g. 192.168.1.50:5555).';

  SR_ADB_NEED_APK =
    '[ADB-017 INVALID_PARAM] install needs "apk" (path of the compiled .apk, ' +
    'inside the workspace). Compile with delphi_build platform=Android64 ' +
    'target=Deploy (the result declares where the .apk ends up).';

  SR_ADB_TARGET_FMT =
    '[ADB-018 INVALID_PARAM] "%s" is not valid as a device address or serial. ' +
    'Use letters, digits, ".", ":", "_" and "-" (like the ones ' +
    'command=devices lists).';

  SN_ADB_DEVICES =
    '[ADB-019] These devices hang off the SERVER machine. Attach one ' +
    'over the network with command=connect address=ip:port. Deploy an ' +
    'app to one: delphi_build platform=Android64 target=Deploy builds ' +
    'the .apk (generating the deployment manifest if the project has ' +
    'none), then command=install puts it on the device.';

  SN_ADB_DISCOVER =
    '[ADB-020] Devices announcing wireless debugging on the server''s ' +
    'network. Take an ip:port and command=connect to it (the device ' +
    'shows an authorize prompt the first time). Nothing here means none ' +
    'is announcing - the device''s wireless-debugging screen must be ' +
    'OPEN, or the developer can read the ip:port off it and give it to ' +
    'you directly.';

  SR_ADB_LINES_FMT =
    '[ADB-021 INVALID_PARAM] "%s" is not a valid number of lines for logcat ' +
    '(1-5000; 0 or nothing = the default, 300).';

  // ---- /files download route + delphi_fetch ----

  SD_FETCH =
    'Download a file FROM the server - the "get the deploy" tool: after ' +
    'delphi_build, fetch the exe (and the companion files delphi_list ' +
    'shows) to run GUI apps on YOUR machine. Two ways: (1) the answer''s ' +
    '"download" field is a direct HTTP GET on this same server ' +
    '(/files?path=...): run it with curl and your same Bearer token - the ' +
    'standard way for any file, installers and binaries included; (2) ' +
    'base64 chunks inline, for small files or clients without a shell: ' +
    'loop offset until eof=true, concatenate the decoded chunks, verify ' +
    'the sha256 (of the whole file, given on the offset=0 call). Files ' +
    'over 1 MB answer with the download link only; maxbytes<=1048576 ' +
    'forces inline chunks instead. Jailed to the workspace roots and the ' +
    'read-only library zone.';

  SN_FETCH_CAPTURE_CONSUMED =
    '[FETCH-002] Desktop capture: it is deleted from the server the ' +
    'moment it has been fetched whole (last chunk served, or one GET on ' +
    'the download link). Nothing is cached or kept: if you need it ' +
    'again, take a new screenshot; a capture requested with out= is ' +
    'yours and stays.';

  SN_FETCH_DOWNLOAD =
    '[FETCH-006] Direct download: GET this path on the SAME host:port ' +
    'you use for /mcp, with the SAME Authorization: Bearer header, e.g. ' +
    'curl -H "Authorization: Bearer <token>" -o <file> ' +
    '"http://<host>:<port><download>". The response carries ' +
    'X-File-SHA256 to verify with sha256sum.';

  SN_FETCH_BIG_FMT =
    '[FETCH-003] This file is %s: use the "download" link (curl) - no ' +
    'chunk was included. For inline base64 chunks instead, pass ' +
    'maxbytes=1048576 (or less) and loop offset until eof=true.';

  SR_FILES_NEED_PATH =
    '[FILE-033 INVALID_PARAM] Missing parameter path: GET ' +
    '/files?path=srvd:\...\file';

  SR_FILES_DIR =
    '[FILE-001 INVALID_PARAM] It is a directory. /files downloads files, it ' +
    'never lists folders.';

  SR_FILES_MISSING =
    '[FILE-034 NOT_FOUND] The requested file does not exist.';

  // Appended to a READ refusal outside the jail: the library zone exists,
  // but only the folders the IDE registers (and their subfolders) - not their
  // parents.
  SN_READ_ZONE_HINT =
    '[READ-003] For READING, besides the roots the library zone is ' +
    'allowed: the folders the IDE registers in its Library Path ' +
    '(RTL/VCL/FMX sources and those of installed components), the ' +
    'install root of each component (one level up: Library, Redist, ' +
    'Examples) and their subfolders. delphi_workspace lists them.';

  // ---- delphi_config: search paths ----

  SP_CONFIG_VERSION =
    'set-version: 2 to 4 numbers (1.2, 1.2.3, 1.2.3.4; a suffix like -beta ' +
    'is ignored - VERSIONINFO is numeric). Written to the Windows VerInfo ' +
    'numbers AND the FileVersion/ProductVersion keys at once, which is ' +
    'what drifts by hand. Android and iOS versions are NOT touched.';

  SP_CONFIG_SDK =
    'set-sdk: the SDK this PROJECT builds that platform with, by name ' +
    '(delphi_paserver command=profiles lists them with their glibc); ' +
    'without it everything rides on the SDK Manager default. "none" = back ' +
    'to that default. add-platform takes it too, in the same call (all or ' +
    'nothing).';

  SP_CONFIG_PROFILE =
    'set-profile: the PAServer profile this PROJECT deploys and runs that ' +
    'platform with (delphi_paserver command=profiles lists them) - the ' +
    'twin of set-sdk: in the IDE a target gets both. "none" = back to the ' +
    'platform''s active profile. add-platform takes it too, in the same ' +
    'call (all or nothing).';

  SR_CONFIG_PROFILE_LOCAL_FMT =
    '[CFG-012 INVALID_PARAM] %s is compiled and run ON this machine, so it ' +
    'takes no PAServer profile. Profiles are for remote targets ' +
    '(Linux64, OSX64, Android...).';

  SR_CONFIG_SDK_LOCAL_FMT =
    '[CFG-108 INVALID_PARAM] %s is compiled ON this machine, so it takes ' +
    'no SDK. SDKs are for remote targets (Linux64, OSX64, Android...).';

  SR_CONFIG_PROFILE_NOEXISTE_FMT =
    '[CFG-013 NOT_FOUND] There is no profile named "%s". Registered: %s. ' +
    'Profiles are created with delphi_paserver command=add-profile ' +
    'against the live PAServer of that machine.';

  SN_CONFIG_PROFILE_PUESTO_FMT =
    '[CFG-014] The project will deploy and run %s through profile %s ' +
    '(before: %s). It is the Profile property, the one msbuild reads, so ' +
    'target=Deploy no longer needs to be told the profile on every call. ' +
    'Backup of the .dproj in __delphi-patch.';

  SN_CONFIG_PROFILE_QUITADO_FMT =
    '[CFG-015] The project no longer pins a profile for %s (before: %s): ' +
    'it will use the active one of the platform again. Registered: %s.';

  SP_CONFIG_PATH =
    'add/remove-searchpath: the folder where the compiler looks for ' +
    '.pas/.dcu (e.g. an installed component''s Source; delphi_workspace ' +
    'lists the readable library zone); $(BDS)-style macros accepted, ' +
    'relative = from the project folder; it must exist inside the ' +
    'workspace or the library zone. add/remove-unit: the .pas. ' +
    'add/remove-deployfile: the file to ship. add/remove-project: the ' +
    '.dproj, in the .groupproj given in project.';

  SR_CONFIG_NEED_PATH =
    '[CFG-095 INVALID_PARAM] Missing "path": the folder to add to/remove ' +
    'from the search path (e.g. the Source folder of an installed ' +
    'component). If your tool schema has no "path" parameter, the server ' +
    'was updated after you connected: reconnect the MCP session to ' +
    'receive the new schema.';

  SR_CONFIG_PATH_CHARS =
    '[CFG-016 INVALID_PARAM] The path contains characters that are not allowed ' +
    '(< > " ; | or control characters, and & except in a search path) or ' +
    'is too long. One path per call, without ";".';

  SR_CONFIG_PATH_MACRO_FMT =
    '[CFG-017 INVALID_PARAM] I cannot resolve "%s" (unknown macro or invalid ' +
    'path). Use a real path or an IDE macro such as $(BDS).';

  { Un parametro que no es del comando: se ignoraba (set-output con path=
    contestaba "puesto en Compiled", el valor por defecto; sexta revision). }
  { ...y el de delphi_create: formname con una unit, content con un
    proyecto o un form se ignoraban (septima revision). }
  SR_CREATE_NO_VA_CON_KIND_FMT =
    '[CREATE-035 INVALID_PARAM] "%s" does not go with kind=%s (it would ' +
    'be ignored). Nothing was created: kind=%s takes %s.';

  SR_CONFIG_NO_ES_DEL_COMANDO_FMT =
    '[CFG-110 INVALID_PARAM] "%s" does not go with command=%s (it would ' +
    'be ignored). Nothing was done: %s takes %s.';

  SR_CONFIG_PATH_A_MEDIAS_FMT =
    '[CFG-109 INVALID_PARAM] "%s" hangs from the root of a drive (a leading ' +
    '\ or /, or a drive letter with no \ after it): that is neither ' +
    'relative to the project nor a full path, and it would land on ' +
    'whatever drive the server happens to be on. Give it relative to the ' +
    'project folder (sub\file.ext) or in full, drive letter and all.';

  SR_CONFIG_PATH_MISSING_FMT =
    '[CFG-018 NOT_FOUND] The folder "%s" does not exist on the server. ' +
    'Find the right one with delphi_list (library zone) before adding it.';

  SN_CONFIG_PATH_ADDED_FMT =
    '[CFG-019] ADDED "%s" to the search path of %s (resolves to %s). The ' +
    'PropertyGroups of the platform were created the way the IDE would ' +
    'if they did not exist; backup of the .dproj in __delphi-patch. ' +
    'Verify with delphi_build {platform:"%s"}.';

  SN_CONFIG_PATH_PRESENT_FMT =
    '[CFG-020] "%s" was already in the search path of %s. Nothing to ' +
    'change.';

  SN_CONFIG_PATH_REMOVED_FMT =
    '[CFG-021] REMOVED "%s" from the search path of %s. Backup of the ' +
    '.dproj in __delphi-patch.';

  SN_CONFIG_PATH_ABSENT_FMT =
    '[CFG-022] "%s" is not in the search path of %s. See the current ' +
    'ones with command=view.';

  SN_CONFIG_NO_PATHS =
    '[CFG-023] The project declares no unit search paths of its own: the ' +
    'compiler finds units through the IDE library path of each platform. ' +
    'A platform added later gets none of that - add-searchpath fixes ' +
    '"unit not found" on one platform only.';

  // ---- delphi_config: deployment files ----

  SP_CONFIG_REMOTEDIR =
    'add-deployfile: destination folder on the target, relative to the ' +
    'deployment root (the IDE''s RemoteDir). Default: next to the binary - ' +
    'for a .so on Android, the apk''s library\lib\<abi>\. No absolute ' +
    'paths, no "..".';

  SR_CONFIG_DEPLOY_NEED_PATH =
    '[CFG-096 INVALID_PARAM] Missing "path": the file that must travel ' +
    'with the deployment (e.g. the native library a component loads at ' +
    'runtime). If your tool schema has neither "path" nor "remotedir", ' +
    'the server was updated after you connected: reconnect the MCP ' +
    'session to receive the new schema.';

  SR_CONFIG_DEPLOY_PLATFORM_FMT =
    '[CFG-024 INVALID_PARAM] "%s" is not a valid Delphi platform ' +
    '(add/remove-deployfile needs one: Linux64, OSX64, Android64...).';

  SR_CONFIG_DEPLOY_NOT_FILE_FMT =
    '[CFG-025 INVALID_PARAM] "%s" is a folder. add-deployfile takes FILES, one ' +
    'per call.';

  SR_CONFIG_DEPLOY_MISSING_FMT =
    '[CFG-026 NOT_FOUND] The file "%s" does not exist on the server. ' +
    'Locate it with delphi_list (library zone) before adding it.';

  SR_CONFIG_REMOTEDIR_CHARS =
    '[CFG-027 INVALID_PARAM] remotedir must be a simple relative folder (no ' +
    '"..", no ":", no leading slash and no special characters), e.g. ' +
    'MyApp\lib\.';

  SN_CONFIG_DEPLOY_ADDED_FMT =
    '[CFG-028] ADDED to the deployment of %s: "%s" -> %s%s (Debug and ' +
    'Release). %sBackup of the .deployproj in __delphi-patch. To ' +
    'actually deploy you need an IDE CONNECTION PROFILE: delphi_build ' +
    'target=Deploy platform=%s only works if the user of this server has ' +
    'one configured (otherwise msbuild answers "Missing profile name" ' +
    'even for Win32). Remotely, delphi_build target=Deploy ' +
    'profile=<name> does the real deployment; locally, the .deployproj ' +
    'stays written and the IDE will use it when it opens the project.';

  SF_CONFIG_DEPLOY_GENERATED =
    'The project had no deployment manifest: the standard one (the ' +
    'binary) was generated before adding the file.';

  SN_CONFIG_DEPLOY_PRESENT_FMT =
    '[CFG-029] "%s" already travels in the deployment of %s. Nothing to ' +
    'change.';

  SN_CONFIG_DEPLOY_REMOVED_FMT =
    '[CFG-030] REMOVED "%s" from the deployment of %s (%d entries). ' +
    'Backup in __delphi-patch.';

  SN_CONFIG_DEPLOY_ABSENT_FMT =
    '[CFG-031] "%s" is not in the deployment of %s. See the entries with ' +
    'command=view.';

  SN_CONFIG_NO_DEPLOYPROJ =
    '[CFG-032] No deployment manifest (.deployproj) next to the project ' +
    'yet: add-deployfile writes one (with the binary in it) and adds ' +
    'your file. Note that RUNNING a deployment needs an IDE connection ' +
    'profile on this machine: without one, delphi_build target=Deploy ' +
    'fails with "Missing profile name" even for Win32. delphi_build ' +
    'target=Deploy with a profile is what deploys remotely.';

  // ---- project units (Lsp.ProjectUnits: add-unit / remove-unit / create / delete / move) ----

  SR_UNIT_NEED_PROJECT =
    '[CFG-097 INVALID_PARAM] Missing "project": the .dproj (or .dpr / ' +
    '.dpk) of the project.';

  SR_UNIT_PROJECT_EXT_FMT =
    '[CFG-033 INVALID_PARAM] "%s" is not a project (.dproj, .dpr or .dpk).';

  SR_UNIT_NO_DPR_FMT =
    '[CFG-034 NOT_FOUND] The main source of the project does not exist ' +
    '(%s); units are registered in the .dpr (uses) or in the .dpk ' +
    '(contains), and without it there is no project.';

  SR_UNIT_NEED_PATH =
    '[CFG-098 INVALID_PARAM] Missing "path": the .pas unit to register ' +
    'or remove. If your client does not show the parameter, reconnect ' +
    'the MCP session (the server was updated).';

  SR_UNIT_PAS_MISSING_FMT =
    '[CFG-035 NOT_FOUND] %s does not exist. To create a new unit use ' +
    'delphi_create kind=unit (or form-vcl / form-fmx).';

  SR_UNIT_NOT_PAS_FMT =
    '[CFG-036 INVALID_PARAM] "%s" is not a .pas unit.';

  SR_UNIT_NO_HEADER_FMT =
    '[CFG-037 DENIED] %s has no "unit X;" header - it is not a Delphi ' +
    'unit.';

  { La cabecera existe pero su nombre no es un nombre de unit. Se dice la
    causa real en vez de "no tiene cabecera". Hasta el censo del 4-oct-2026
    se negaba tambien uno con acentos, que el compilador acepta (medido el
    23-sep, RAD Studio 13: "unit UArticulos;" con su i acentuada compila y
    enlaza) y que los analizadores del servidor no sabian leer en ~40
    sitios: ahora todos leen EL identificador (Lsp.Pascal). }
  SR_UNIT_HEADER_NONASCII_FMT =
    '[CFG-038 DENIED] The header of %s says "unit %s;", and that is not a ' +
    'unit name: a Pascal identifier (an ASCII letter, _ or any non-ASCII ' +
    'character, then also digits), or several joined by dots. Fix the header ' +
    '(delphi_edit) or rename the unit and its file (delphi_move).';

  SR_UNIT_HEADER_MISMATCH_FMT =
    '[CFG-039 DENIED] The header says "unit %s;" but the file is named ' +
    '%s. In Delphi they must match; fix one of the two with delphi_edit ' +
    '/ delphi_move.';

  SR_UNIT_NO_USES_FMT =
    '[CFG-040 DENIED] I cannot find the units clause (uses / contains) ' +
    'of %s.';

  { Un proyecto del camino que no se puede LEER mientras se busca si lista
    una unit (move / delete): salia el SYS-028 pelado y parecia un intento
    de escribirlo (decima revision). El resultado es el de la causa. }
  SR_PROYECTO_NO_LEIDO_AL_BUSCAR_FMT =
    '[CFG-111 DENIED] %s could not be read while checking whether it lists ' +
    'the unit %s - nothing was touched. %s';

  SN_UNIT_ADDED_FMT =
    '[CFG-041] ADDED unit %s (%s) to project %s: %s clause of %s + ' +
    'DCCReference in the .dproj. Backups in __delphi-patch.';

  SN_UNIT_ADDED_FORM_FMT =
    '[CFG-042] ADDED unit %s (%s) with its form %s: %s to project %s: %s ' +
    'clause of %s%s + DCCReference in the .dproj. Backups in ' +
    '__delphi-patch.';

  SN_UNIT_CREATEFORM =
    ' [CFG-043] + Application.CreateForm';

  SN_UNIT_PRESENT_FMT =
    '[CFG-044] Unit %s was already in %s. Nothing to change (.dproj ' +
    'entry refreshed).';

  { Estaba en la uses por el NOMBRE, sin clausula in: antes "ya estaba, nada
    que cambiar" y el build en F2613 porque dcc no encuentra una unit de otra
    carpeta sin la ruta. Medido 2026-09-23 (Hermes, bateria 1.2). }
  SN_UNIT_COMPLETED_FMT =
    '[CFG-045] COMPLETED the entry of unit %s in the uses of %s: it was ' +
    'there by name but WITHOUT an in clause, and without it dcc does not ' +
    'find a unit in another folder (F2613). It is now "%s in ''%s''" + ' +
    'DCCReference in the .dproj. Backup in __delphi-patch.';

  SN_UNIT_NO_RUN_ANCHOR =
    '[CFG-046] There is no Application.Run nor any other CreateForm in ' +
    'the .dpr: create the form instance where it belongs (delphi_edit).';

  SN_UNIT_NO_ITEMGROUP =
    '[CFG-047] The .dproj has no ItemGroup to hang the DCCReference on; ' +
    'the IDE will complete it when it opens the project (MSBuild ' +
    'compiles anyway through the uses).';

  SN_UNIT_NO_DPROJ =
    '[CFG-048] The project has no .dproj: only the .dpr was updated.';

  { add-requires: la clausula requires de un .dpk, lo que el IDE ofrece tras
    un build con W1033. }
  SR_REQUIRES_NOT_PACKAGE_FMT =
    '[CFG-049 INVALID_PARAM] %s is not a package (.dpk): the requires clause ' +
    'only exists in packages.';
  SR_REQUIRES_BAD_NAME_FMT =
    '[CFG-050 INVALID_PARAM] "%s" is not a package name (a Pascal identifier, ' +
    'dots allowed, as in the IDE: vcl, dbrtl, fmx, IndyCore).';
  SR_REQUIRES_NEED_NAMES =
    '[CFG-051 INVALID_PARAM] Missing "requires": the package names to add, ' +
    'separated by ; (the ones requiresSuggested from the build named).';
  SN_REQUIRES_PRESENT_FMT =
    '[CFG-052] All those packages were already in the requires of %s. ' +
    'Nothing to change.';
  SN_REQUIRES_ADDED_FMT =
    '[CFG-053] ADDED to the requires of %s: %s. The clause is now: %s. ' +
    'Compile again: the units of those packages stop being duplicated ' +
    'inside yours. Backup in __delphi-patch.';

  { adduses de delphi_edit (David, 2026-09-23): la unit entra en el uses de
    OTRA unit y la clausula la escribe el motor. }
  SR_ADDUSES_NOT_PAS_FMT =
    '[USES-002 INVALID_PARAM] adduses is for units (.pas); %s is a ' +
    'project. To put a unit into a .dpr/.dpk use delphi_config ' +
    'command=add-unit, which also registers the DCCReference in the ' +
    '.dproj.';
  SR_ADDUSES_NEED_NAMES =
    '[USES-003 INVALID_PARAM] Missing "adduses": the unit names to add, ' +
    'separated by ; (System.SysUtils;UCustomer).';
  SR_ADDUSES_BAD_NAME_FMT =
    '[USES-004 INVALID_PARAM] "%s" is not a unit name (a Pascal identifier, ' +
    'dots allowed: System.SysUtils, Modules.API).';
  SR_ADDUSES_BAD_SECTION_FMT =
    '[USES-005 INVALID_PARAM] "section"="%s" is not valid: interface or ' +
    'implementation (implementation by default, which is where a new ' +
    'unit goes unless one of its types is used in the interface).';
  SR_ADDUSES_NO_FILE_FMT =
    '[USES-006 NOT_FOUND] %s does not exist.';
  SR_ADDUSES_NO_SECTION_FMT =
    '[USES-007 DENIED] I cannot find the %s section in %s (a unit has ' +
    'interface and implementation; if the file is not a unit, edit its ' +
    'uses with old/new).';
  SN_ADDUSES_IN_OTHER_FMT =
    ' [USES-008] Already in %s, and a unit cannot go in both sections ' +
    '(E2004): %s.';
  SN_ADDUSES_PRESENT_OTHER_FMT =
    '[USES-009] Nothing to write: %s is already in the %s uses of %s, ' +
    'and a unit cannot go in both sections (E2004 Identifier ' +
    'redeclared). If you want it in the other one, remove it first with ' +
    'removeuses.';
  SN_ADDUSES_PRESENT_FMT =
    '[USES-010] Already there: %s in the %s uses of %s. Nothing to write.';
  SN_ADDUSES_SOME_PRESENT_FMT =
    ' [USES-011] Already there: %s.';
  SN_ADDUSES_CREATED_FMT =
    ' [USES-012] The %s section had no uses: created below the section ' +
    'keyword.';
  SN_ADDUSES_ADDED_FMT =
    '[USES-013] ADDED to the %s uses of %s: %s.%s%s Backup in ' +
    '__delphi-patch.'#10 +
    'The clause is now (re-read from disk):'#10 +
    '%s';

  { removeuses: la inversa de adduses. }
  SR_REMOVEUSES_NOT_PAS_FMT =
    '[USES-014 INVALID_PARAM] removeuses is for units (.pas); %s is a ' +
    'project. To take a unit out of a .dpr/.dpk use delphi_config ' +
    'command=remove-unit.';
  SR_REMOVEUSES_NEED_NAMES =
    '[USES-015 INVALID_PARAM] Missing "removeuses": the unit names to remove, ' +
    'separated by ; (UCustomer;UOther).';
  SN_REMOVEUSES_NO_CLAUSE_FMT =
    '[USES-016] The %s section of %s has no uses: nothing to remove.';
  SN_REMOVEUSES_ABSENT_FMT =
    '[USES-017] Not there: %s in the %s uses of %s. Nothing to write.';
  SN_REMOVEUSES_SOME_ABSENT_FMT =
    ' [USES-018] Not there: %s.';
  SN_REMOVEUSES_GONE_FMT =
    '[USES-019] (the %s section is left without a uses clause: it was ' +
    'removed entirely)';
  SN_REMOVEUSES_REMOVED_FMT =
    '[USES-020] REMOVED from the %s uses of %s: %s.%s Backup in ' +
    '__delphi-patch.'#10 +
    'The clause is now (re-read from disk):'#10 +
    '%s';

  SN_UNIT_REMOVED_FMT =
    '[CFG-054] REMOVED unit %s from project %s (%s%s%s). The file %s is ' +
    'still on disk; delete it with delphi_delete if you no longer want ' +
    'it. Backups in __delphi-patch.';

  SN_UNIT_REMOVED_GONE_FMT =
    '[CFG-055] REMOVED unit %s from project %s (%s%s%s). The file %s ' +
    'goes to the trash with this same delete. Backups in __delphi-patch.';

  SN_UNIT_ABSENT_FMT =
    '[CFG-056] Unit %s is not in project %s. See the units with ' +
    'command=view.';

  SN_UNIT_RENAME_NOT_WRITTEN_FMT =
    '  [CFG-057] %d project file(s) NOT rewritten because this workspace ' +
    'cannot write them (outside its roots, in a reference or read-only): ' +
    '%s. They still name the old unit; if they are yours in another ' +
    'workspace, change them there.';

  SR_BUILD_SDK_NAME_FMT =
    '[BUILD-026 INVALID_PARAM] sdk "%s" is not an SDK name: only letters, ' +
    'digits, ".", "-" and "_" (for example zorin18.sdk), no folder.';

  SN_UNIT_RENAMED_FMT =
    '[CFG-058] RE-POINTED unit %s (%s) -> %s (%s) in project %s (%s ' +
    'clause + DCCReference in the .dproj). References rewritten: %d in ' +
    '%d file(s) (uses of the other units and OldUnit.X qualifiers).';

  SN_FILE_PROJECTS_UPDATED_FMT =
    '  [FILE-035] projects that list it (%d): %s';

  SN_FILE_PROJECTS_NONE =
    '  [FILE-002] (no .dpr or .dpk listed it, looking from its folder - ' +
    'and in a move, also from the destination one - upward to the edge ' +
    'of the workspace; if another project uses it, remove it with ' +
    'delphi_config command=remove-unit)';

  SN_FILE_COPY_NO_PROJECT =
    '  [FILE-003] (a COPY is a new unit that no project lists yet: ' +
    'delphi_config command=add-unit when you want it in one)';

  SR_MOVE_COPY_FROM_TRASH =
    '[MOVE-003 DENIED] Not copy=true from the trash: to recover a copy ' +
    'MOVE it out (delphi_move without copy), which is what a restore ' +
    'does.';

  SR_COPIA_DENTRO_DE_SI_FMT =
    '[MOVE-009 INVALID_PARAM] "%s" is inside "%s": a folder is not copied or ' +
    'moved inside itself (it would copy without end). Choose a ' +
    'destination outside it.';

  SR_MOVE_COPY_PROJECT_FMT =
    '[MOVE-004 DENIED] That is or contains a project (%s), and a project ' +
    'never lives in two places. To start a project from another one, ' +
    'delphi_create; to take it somewhere else in your workspace, ' +
    'delphi_move without copy. A REFERENCE project is read where it is: ' +
    'from it you copy units or folders without a project.';

  SP_MOVE_COPY =
    'true = COPY instead of move: the source stays untouched, no trash ' +
    'copy, and NO project is re-pointed (the copy is a new unit nobody ' +
    'lists yet - delphi_config add-unit). A unit copied under another name ' +
    'gets its "unit X;" header rewritten and its .dfm/.fmx copied along. ' +
    'The source only has to be READABLE (your roots, ReadOnlyRoots, the ' +
    'library zone): the way to bring a file in from a reference project. ' +
    'Refused for a folder that holds a .dproj/.dpk (a project never lives ' +
    'in two places) and for anything inside the trash.';

  SN_FILE_PROJECT_DENIED_FMT =
    '    [FILE-004] %s: outside the allowed workspaces, NOT touched ' +
    '(remove the unit with delphi_config command=remove-unit from a ' +
    'project inside the jail).';

  { Una carpeta que no se pudo llevar a la papelera por otra cosa que un
    bloqueo (una ruta demasiado larga para la papelera...): FILE-036 lo
    atribuia todo a "algo la tiene abierta" (septima revision). }
  SR_FILE_CARPETA_NO_MOVIDA_FMT =
    '[FILE-041 DENIED] I have NOT deleted "%s" and I have NOT touched ' +
    'ANYTHING: moving it to the trash failed (%s). The contents are still ' +
    'INTACT in place.';

  { ColocaProducto (Lsp.Patch) mueve y borra el producto que coloca: solo uno
    NUESTRO - de la temporal del servidor, o ya en la carpeta del destino,
    la que aprueba la puerta. Otro es un fallo de quien llama (revisor de P4,
    9-oct-2026). }
  SR_COLOCA_PRODUCTO_AJENO_FMT =
    '[FILE-042 INTERNAL] %s is not a file this server made (its temp, or ' +
    'the destination''s own folder), so it is not moved over %s. Nothing ' +
    'was written.';

  SR_FILE_DELETE_LOCKED_FMT =
    '[FILE-036 DENIED] I have NOT deleted "%s" and I have NOT touched ' +
    'ANYTHING: something has the folder open and moving it as a whole ' +
    'failed (%s). The contents are still INTACT in place; there is no ' +
    'half copy in the trash to confuse you. It is usually a .exe from an ' +
    'earlier build still running, the IDE with the project open, or a ' +
    'git process. Close whatever is locking it and retry. (I do not kill ' +
    'processes on this machine: someone may be working on the other ' +
    'side.)';

  SR_FILE_PARTIAL_FMT =
    '[FILE-005 INTERNAL] Failed %s: %s'#10 +
    'WARNING: before the failure these changes had already been applied ' +
    '(backups in __delphi-patch):%s';

  SN_FILE_DESIGNER_TOO_FMT =
    '  [FILE-006] designer %s: %s';

  // ---- delphi_diagnostics ----

  SF_DIAG_IN_PROGRESS =
    '{"status":"in-progress","note":"The lint is still running in the ' +
    'LSP (large units take more than a minute the first time). Call ' +
    'delphi_diagnostics again with the same file: the lint does NOT ' +
    'restart while the file does not change, and the next call returns ' +
    'the result."}';

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
    'The text .style file (view/get/set/clone) or the styles FOLDER ' +
    '(lint/build; a file there stands for its folder). Binary styles (FMX_STYLE / .bin.style) are refused ' +
    'for editing: edit the text one and run build.';

  SR_STYLES_NEED_PATH =
    '[STYLE-030 INVALID_PARAM] Missing "path": the text .style ' +
    '(view/get/set/clone) or the styles folder (lint/build). If your ' +
    'client does not show the parameter, reconnect the MCP session (the ' +
    'server was updated).';

  SR_STYLES_MISSING_FMT =
    '[STYLE-001 NOT_FOUND] %s does not exist. Locate the styles with ' +
    'delphi_list pattern=*.style.';

  SR_STYLES_NEED_FILE =
    '[STYLE-002 INVALID_PARAM] view/get/set/clone/delete need ONE text ' +
    '.style file - not a folder, not a file of another kind (delphi_list ' +
    'pattern=*.style lists them).';

  { lint/build con un FICHERO: su carpeta, como en la 1.6.2 (documentado:
    "a file is accepted too"), pero DICIENDOLO. La quinta revision lo cambio
    por un rechazo (STYLE-038, retirado) que rompia a quien lo usaba. }
  { Un parametro que no es del comando: delete con child/prop borraba el
    estilo ENTERO pidiendo una parte (octava revision). }
  SR_STYLES_NO_VA_CON_COMANDO_FMT =
    '[STYLE-043 INVALID_PARAM] "%s" does not go with command=%s (it would ' +
    'be ignored). Nothing was done: %s takes %s.';

  SN_STYLES_CARPETA_DEL_FICHERO_FMT =
    '[STYLE-042] %s is a file: lint and build work on a whole styles ' +
    'folder, so they ran on its folder, %s.';

  SR_STYLES_BINARY_FMT =
    '[STYLE-003 DENIED] %s is BINARY (a compiled style, the product of ' +
    'command=build, or a binary resource), and this server cannot READ ' +
    'it: the format is a compiled DFM, not text, so I cannot even list ' +
    'its StyleNames for you. Work on the text .style it comes from (same ' +
    'name without the .bin) and run command=build again. If your only ' +
    'copy is the binary, say so with delphi_report.';

  SR_STYLES_NEED_STYLE =
    '[STYLE-031 INVALID_PARAM] Missing "style": the StyleName of the ' +
    'style (command=view lists them).';

  SR_STYLES_NEED_PROP =
    '[STYLE-032 INVALID_PARAM] Missing "prop": the property to change, ' +
    'as it appears in the file (Fill.Color, Size.Height, Visible...). ' +
    'command=get shows the style.';

  SR_STYLES_PROP_CHARS_FMT =
    '[STYLE-004 INVALID_PARAM] "%s" is not a property name (a Pascal ' +
    'identifier, dots allowed: Font.Size).';

  SR_STYLES_NEED_VALUE =
    '[STYLE-033 INVALID_PARAM] "value" is missing: the value as it is ' +
    'written in a .style (xFFF6ECDB, 44.000000000000000000, True, ' +
    '''text'', Center). To remove the property use delete=true.';

  SR_STYLES_VALUE_LINE =
    '[STYLE-005 DENIED] value must be ONE line. Multi-line values ' +
    '(collections, binaries) are edited with delphi_textedit on the file.';

  SR_STYLES_NEED_NAME =
    '[STYLE-034 INVALID_PARAM] "name" is missing: the StyleName of the ' +
    'new style.';

  SR_STYLES_NAME_CHARS_FMT =
    '[STYLE-006 INVALID_PARAM] "%s" is not valid as a StyleName: a letter ' +
    '(of any alphabet) or _ first, then letters, digits, _, dots and ' +
    'hyphens.';

  SR_STYLES_NAME_TAKEN_FMT =
    '[STYLE-007 DENIED] A style ''%s'' already exists in the file. Choose ' +
    'another name or change the existing one with set.';

  SR_STYLES_NO_TEXT_FMT =
    '[STYLE-008 NOT_FOUND] There is no TEXT .style in %s (.bin.style files ' +
    'and binaries do not count). Export the style as text from the ' +
    'Bitmap Style Designer or point to the right folder.';

  SR_STYLES_PROJECT_NO_EXISTE_FMT =
    '[STYLE-041 NOT_FOUND] project=%s does not exist: give the .dproj (or ' +
    'its folder) whose .fmx/.pas the lint checks the StyleLookup of.';

  SR_STYLES_NO_CONVERTER =
    '[STYLE-009 INTERNAL] DelphiStyleConvert.exe (the text<->binary ' +
    'converter) is missing next to the server. Tell the operator: it is ' +
    'deployed with the server.';

  SN_STYLES_VIEW_NOTE =
    '[STYLE-010] StyleLookup of a control resolves to one of these ' +
    'StyleNames (case-insensitive). get shows a style; set changes one ' +
    'property; clone adds a variant. After editing run command=build so ' +
    'the app embeds the change.';

  SN_STYLES_PROP_SET_FMT =
    '[STYLE-011] %s: %s (style %s%s, %s). Backup in __delphi-patch. ' +
    'Remember command=build to regenerate the binary the app embeds.';

  SN_STYLES_PROP_DELETED_FMT =
    '[STYLE-012] REMOVED property %s from style %s%s (%s). Backup in ' +
    '__delphi-patch.';

  SN_STYLES_PROP_ABSENT_FMT =
    '[STYLE-013] Property %s is not in style %s%s (nothing to remove; ' +
    'command=get shows it).';

  SN_STYLES_CLONED_FMT =
    '[STYLE-014] CLONED: new style ''%s'' from ''%s'' (lines %d-%d of %s). ' +
    'Adjust its properties with set and regenerate with build; in the ' +
    '.fmx it is used with StyleLookup = ''%0:s''.';

  SN_STYLES_DELETED_FMT =
    '[STYLE-015] DELETED style ''%s'' (lines %d-%d of %s; %d styles left). ' +
    'The copy in __delphi-patch\<day>\ (delphi_list includetrash=true pattern=*.style shows ' +
    'it) is the file as it was before its FIRST change today: putting ' +
    'it back (delphi_delete the file, then delphi_move that copy to its ' +
    'name) also undoes the other changes of the day. To undo only this ' +
    'one, read the style''s lines in that copy and put them back ' +
    'with delphi_textedit. Regenerate ' +
    'with build; a StyleLookup that used it is left without a style ' +
    '(command=lint will say so).';

  SN_STYLES_LINT_NOTE =
    '[STYLE-016] lookupsWithoutStyle: a control with that StyleLookup ' +
    'will render with the default look (no error at runtime) - define ' +
    'the style (clone) or fix the name. duplicatedStyleNames: the last ' +
    'one wins silently. lookupsStandard are names the platform default ' +
    'style provides.';

  SN_STYLES_NO_DEFAULTS =
    '[STYLE-017] The platform default style names could not be extracted ' +
    '(converter missing): standard lookups such as buttonstyle may ' +
    'appear as missing.';

  SN_STYLES_BUILD_NOTE =
    '[STYLE-018] The .bin.style files are what the app embeds (.rc ' +
    'RCDATA -> .res). Rebuild the project afterwards (delphi_build ' +
    'target=Build) so the new .res goes in; MSBuild reuses an old .res ' +
    'otherwise.';

  // ---- delphi_messages ----

  SD_MESSAGES =
    'Your MAILBOX: messages the operator leaves for you (the way back of ' +
    'delphi_report). command=read delivers every pending message in YOUR ' +
    'box and DELETES it (read once, nothing kept); check only lists what ' +
    'waits. While mail for you waits, every tool answer ends with a ' +
    'PENDING MESSAGES line - read it then: it may change what you are ' +
    'doing. PRIVACY, honestly: the box is indexed by the agent id YOU ' +
    'declare and nothing ties that id to the caller - everyone here shares ' +
    'one token - so anyone can list and consume the mail of an id they ' +
    'guess, and a consumed message is gone. Treat it as a shared ' +
    'noticeboard: read YOUR id, not other people''s, and send nothing ' +
    'secret.';

  SN_MESSAGES_PENDING_FMT =
    #10#10 +
    '[MSGS-001] PENDING MESSAGES: %d in your mailbox (%s). Read them ' +
    'with delphi_messages command=read.';

  SN_MESSAGES_NONE_FMT =
    '[MSGS-002] No messages for "%s".';

  SN_MESSAGES_NONE_NO_AGENT =
    '[MSGS-003] Without an agent id there is no mailbox: pass ' +
    'agent=<your id> (the same "agent" you give delphi_report).';

  SN_MESSAGES_CHECK_FMT =
    '[MSGS-006] Pending messages: %d (command=read delivers and deletes ' +
    'them):';

  SN_MESSAGES_DELIVERED =
    '[MSGS-004] (read and deleted: they will not appear again. If they ' +
    'ask for something, do it and, if appropriate, answer with ' +
    'delphi_report.)';

  // ---- delphi_build: F2613 helper ----

  SN_BUILD_MISSING_UNITS_NOTE =
    '[BUILD-042] Units the compiler cannot find, and where their .pas ' +
    'lives (your workspace first, then the server''s library zone). ' +
    'Register the folder for this ' +
    'platform with delphi_config command=add-searchpath ' +
    'platform=<platform> path=<folder> and repeat the build. No ' +
    'candidates: the component is not installed or ships no source for ' +
    'this platform (delphi_components platform=<platform>, and if it is ' +
    'missing, delphi_report).';
  { En un paquete el F2613 tiene otra salida mas: la unit vive en OTRO
    paquete propio (Hermes, bateria 1.2 A.2, 2026-09-23): hace falta el
    requires Y el .dcp a mano; el search path solo no lo resuelve. }
  SN_BUILD_MISSING_UNITS_PACKAGE =
    ' [BUILD-027] In a package, a unit that lives in ANOTHER package of ' +
    'yours needs both things: that package in the requires ' +
    '(delphi_config command=add-requires) and the folder where its .dcp ' +
    'ends up (the output of its build) in the search path; the search ' +
    'path alone is not enough, without the requires dcc does not open ' +
    'the .dcp.';

  // ---- delphi_rename_symbol ----

  SD_RENAME =
    'SEMANTIC RENAME of a Delphi symbol: point at the identifier (path + ' +
    '0-based line/character, like delphi_definition) and give newname. ' +
    'mode=preview (default, never writes) lists every CONFIRMED occurrence ' +
    '(each re-resolved against the same definition), the files touched and ' +
    'whether the rename is APPLICABLE; mode=apply does the same and, when ' +
    'applicable, WRITES it through the changeset engine (all files or ' +
    'none, fingerprints, a backup of each in __delphi-patch) and answers ' +
    'with the commit. Strict on purpose, in both modes: one unverified ' +
    'reference, a hit in a .dfm/.fmx (form bindings break), a hit inside a ' +
    'string literal (FindComponent/RTTI/StyleLookup by name), a symbol ' +
    'defined outside the workspace (RTL/components) or a collision with ' +
    'the new name = applicable=false with the reasons, and apply writes ' +
    'nothing. It renames CODE only: a mention in a comment keeps the old ' +
    'name (on an occurrence''s line too) and is reported as a warning for ' +
    'you to look at. Rebuild afterwards.';

  SP_RENAME_PATH =
    'The .pas/.dpr with the symbol (any occurrence works)';

  SP_RENAME_LINE =
    'Zero-based line of the identifier (a hit''s "line0"; same convention ' +
    'as delphi_definition)';

  SP_RENAME_CHARACTER =
    'Zero-based column inside the identifier (a hit''s "character0")';

  SP_RENAME_NEWNAME =
    'The new identifier (legal Delphi name, no reserved words)';

  SP_RENAME_MODE =
    'preview (default; never writes) | apply (writes it when applicable, ' +
    'through the changeset engine; refused with the blockers otherwise)';

  SR_RENAME_MODE =
    '[RENAME-001 INVALID_PARAM] Mode must be preview or apply.';

  SR_RENAME_NEED_PATH =
    '[RENAME-002 INVALID_PARAM] "path" is missing (the file with the symbol).';

  SR_RENAME_NEED_NEWNAME =
    '[RENAME-003 INVALID_PARAM] "newname" is missing (the new identifier).';

  SR_RENAME_NOT_APPLICABLE =
    '[RENAME-009 DENIED] NOT APPLIED: the rename is not applicable and ' +
    'nothing was written. The "blockers" say why; fix them (or rename by ' +
    'hand with the evidence in "changes") and repeat.';

  SR_RENAME_APPLY_FAILED_FMT =
    '[RENAME-010 DENIED] NOT APPLIED: the changeset engine did not let ' +
    'it through and everything is as it was (all or nothing). Reason: %s';

  SR_RENAME_LINE_GONE_FMT =
    '[RENAME-011 DENIED] line %d of %s no longer exists: the file ' +
    'changed between the analysis and the write';

  SR_RENAME_NOTHING_TO_STAGE =
    '[RENAME-012 DENIED] none of the lines in "changes" contains the ' +
    'identifier';

  SN_RENAME_APPLIED_NOTE =
    '[RENAME-004] APPLIED: every line of "changes" was written by the ' +
    'changeset engine (one edit per line, all or nothing, a backup of ' +
    'each file in __delphi-patch - "commit" has the detail). Recompile ' +
    '(delphi_build) to close the cycle, and review the "warnings": a ' +
    'mention in a comment keeps the old name (only code is renamed).';

  SR_RENAME_BAD_IDENT_FMT =
    '[RENAME-013 INVALID_PARAM] "%s" is not a valid Delphi identifier (an ' +
    'ASCII letter, _ or any non-ASCII character first, then also digits).';

  SR_RENAME_RESERVED_FMT =
    '[RENAME-014 INVALID_PARAM] "%s" is a Delphi reserved word.';

  SR_RENAME_SAME_NAME =
    '[RENAME-015 INVALID_PARAM] The new name is the same as the current ' +
    'one.';

  SR_RENAME_LIBRARY =
    '[RENAME-016 DENIED] The symbol''s definition lives OUTSIDE the ' +
    'workspace roots (RTL or an installed component): that is not ' +
    'renamed from here.';

  SR_RENAME_HOMONYMS_FMT =
    '[RENAME-017 DENIED] There are %d occurrence(s) of the same name ' +
    'that the engine resolves to ANOTHER definition (see "lookalikes"). ' +
    'They may really be something else and need no change... or they may ' +
    'be THIS one, seen from a different project with another ' +
    'configuration: that is what happened in the field, and the rename ' +
    'said yes while it left a project that did not compile. Check them ' +
    'one by one before applying anything; "scope" tells you where I ' +
    'searched.';

  SR_RENAME_UNVERIFIED_FMT =
    '[RENAME-018 DENIED] %d candidate references NOT semantically ' +
    'confirmed. The rule is strict: a single unconfirmed one = not ' +
    'applicable (a renamed false positive is a homonym broken silently).';
  SR_RENAME_ILEGIBLES_FMT =
    '[RENAME-022 DENIED] %d file(s) of the scope could not be read ' +
    '("unreadable"), so a reference in them would be missed: not applicable ' +
    'until they can be read.';

  SR_RENAME_DESIGNER_FMT =
    '[RENAME-019 DENIED] %d occurrences in designers (.dfm/.fmx): ' +
    'renaming a published member breaks the form''s binding (the IDE only ' +
    'repairs it interactively).';

  SR_RENAME_STRINGS_FMT =
    '[RENAME-020 DENIED] %d occurrences inside string literals ' +
    '(FindComponent, RTTI by name, StyleLookup...): a textual rename ' +
    'would leave them pointing to a name that no longer exists, and the ' +
    'compiler does not warn.';

  SR_RENAME_COLLISION_FMT =
    '[RENAME-021 DENIED] The new name "%s" already appears %d times in ' +
    'the code of the affected files (comments and strings do not count): ' +
    'possible collision or homonym.';

  SN_RENAME_DESIGNER_HIT_FMT =
    '[RENAME-005] %d occurrences in %s';

  SN_RENAME_QUALIFIED_FMT =
    '[RENAME-006] The definition is a QUALIFIED header ("%s"): renaming ' +
    'it changes ONLY the method part, never the class name.';

  { AVISO, no bloqueo: la tool renombra codigo. Hasta 2026-09-21 estas
    apariciones llegaban como "unverified" y tumbaban el rename entero; ahora
    no estorban, pero callarlas seria lo contrario del mismo error - el que
    renombra suele querer repasarlas. }
  SN_RENAME_MENTIONS_FMT =
    '[RENAME-007] The old name stays written in %d comment(s) or ' +
    'string(s): this tool renames CODE, not prose. delphi_references ' +
    'lists them in "mentions" with their line if you want to review them ' +
    'by hand.';

  SN_RENAME_PREVIEW_NOTE =
    '[RENAME-008] Preview: NOTHING was written. applicable=true means ' +
    'every occurrence is semantically confirmed and no ' +
    'designer/string/collision hit exists; repeat the same call with ' +
    'mode=apply and it is applied all or nothing. applicable=false lists ' +
    'the blockers - fix them or do the rename by hand with the evidence ' +
    'given. Each change carries BOTH line numbers: "line" is 1-based ' +
    '(what delphi_read shows and what delphi_changeset''s atline expects) ' +
    'and "line0" is the language server''s 0-based one. Use "line".';

  // ---- delphi_docs ----

  SD_DOCS =
    'THE DELPHI DOCUMENTATION installed with RAD Studio - the F1 help of ' +
    'the version installed here: classes, routines and properties (RTL, ' +
    'VCL, FMX, FireDAC, Indy...), the language, the IDE, code examples, ' +
    'and the help of installed components that register one. ' +
    'command=search query=<a concept or a class>: a short list of pages ' +
    '(id + title), best first - a qualified name ' +
    '(System.SysUtils.FormatDateTime, FMX.StdCtrls.TButton) lands on the ' +
    'exact page, a bare one (TButton, TStringList.Sort) or a concept ' +
    '("class helpers") finds it too; framework=vcl|fmx puts that ' +
    'framework''s page first when both have one. command=read id=<an id of ' +
    'that list>: the page as plain text, in chunks (offset); a long page ' +
    'first gives its introduction and its sections, and <id>#<section> ' +
    '(its anchor or its title as the text shows it) reads one alone. The ' +
    'first chunk also lists related: the pages around it (a class: its unit and ' +
    'member lists; a topic: its parent index); other pages it names (See ' +
    'Also, examples) are found with search. Read-only, in any workspace, ' +
    'only the help files the IDE registers. It says what something is for ' +
    'and how it is used; for its exact signature, the installed sources ' +
    'win (delphi_hover, delphi_definition). The manual of THIS server is ' +
    'delphi_help.';

  SP_DOCS_COMMAND =
    'search (find pages: query) | read (one page: id). Without it: read ' +
    'when there is an id (a query beside it is ignored), search when there ' +
    'is only a query';

  SP_DOCS_QUERY =
    'search: a concept or a class, as you would type it in the IDE help: ' +
    'FormatDateTime, TStringList.Sort, FMX.StdCtrls.TButton, "anonymous ' +
    'methods"';

  SP_DOCS_ID =
    'read: the id of a page, as a search gives it ' +
    '(system:System.SysUtils.FormatDateTime.htm); with #section, that ' +
    'section alone (its anchor or its title as the text shows it)';

  SP_DOCS_FRAMEWORK =
    'search optional: vcl | fmx - the page of that framework first, when ' +
    'VCL and FMX both have one (TButton, TEdit)';

  SP_DOCS_OFFSET =
    'read optional: where to start in the text of the page (the nextOffset ' +
    'of the previous chunk)';

  SP_DOCS_LIMIT =
    'search optional: how many results (default 10, at most 25)';

  SR_DOCS_SIN_AYUDA_FMT =
    '[DOCS-001 NOT_FOUND] The Delphi in use (%s) has no help installed: ' +
    'none of the help files its IDE registers (Help\HtmlHelp1Files) is on ' +
    'disk - the documentation is an option of the RAD Studio installer. ' +
    'The declarations are still there: delphi_hover or delphi_definition ' +
    'on the symbol, or its unit with delphi_read (library zone).';

  SR_DOCS_CMD =
    '[DOCS-002 INVALID_PARAM] command must be search (with query) or read ' +
    '(with id).';

  SR_DOCS_SIN_CONSULTA =
    '[DOCS-003 INVALID_PARAM] command=search needs "query": a concept or a ' +
    'class (FormatDateTime, TStringList.Sort, "class helpers").';

  SR_DOCS_SIN_ID =
    '[DOCS-004 INVALID_PARAM] command=read needs "id": one that a ' +
    'delphi_docs search gave.';

  SR_DOCS_FRAMEWORK_FMT =
    '[DOCS-005 INVALID_PARAM] framework "%s" is not one of vcl | fmx.';

  SR_DOCS_NADA_FMT =
    '[DOCS-006 NOT_FOUND] Nothing in the installed help for "%s". Try the ' +
    'class or routine alone (TStringList, FormatDateTime), its qualified ' +
    'name (System.Classes.TStringList), or fewer words for a concept.';

  SR_DOCS_NO_PAGINA_FMT =
    '[DOCS-007 NOT_FOUND] There is no page "%s" in the installed help. ' +
    'Take the id from a delphi_docs search (it looks like ' +
    'system:System.SysUtils.FormatDateTime.htm).';

  SN_DOCS_BUSQUEDA =
    '[DOCS-008] total = the pages of the index that matched. Read one with ' +
    'command=read id=<its id>.';

  { %s: el fichero de ayuda y su fecha }
  SN_DOCS_FUENTE_FMT =
    '[DOCS-009] From the RAD Studio help installed here (%s, %s). It says ' +
    'what this is for and how it is used; for an exact signature, what the ' +
    'installed sources declare wins: delphi_hover or delphi_definition on ' +
    'the symbol.';

  SN_DOCS_SIN_SECCION_FMT =
    '[DOCS-010] There is no section "%s" in this page: this is the page ' +
    'from its start (a long one, its introduction and its sections).';

  { %d: lo dado, el total, por donde seguir }
  SN_DOCS_SIGUE_FMT =
    '[DOCS-011] It goes on: up to character %d of %d. The rest: the same ' +
    'id with offset=%d.';

  { una seccion de la que cuelga el resto de la pagina (Description en las
    de la API): acaba en su primer subtitulo }
  SN_DOCS_SUBSECCIONES =
    '[DOCS-016] The rest of the page hangs from this one title, so this ' +
    'section stops where its first sub-section starts. subsections lists ' +
    'them; <id>#<one of them> reads it.';

  { %s: el id tal como llego (enmascarado). DOCS-012 era la negativa de un
    workspace sin LibraryZone, retirada antes de publicar: la ayuda no pide
    interruptor (David, 2-oct-2026) }
  SR_DOCS_ID_MAL_FMT =
    '[DOCS-013 INVALID_PARAM] "%s" is not the id of a page: it looks like ' +
    '<help>:<page>.htm, optionally with #<section> ' +
    '(system:System.SysUtils.FormatDateTime.htm) - take it from a ' +
    'delphi_docs search.';

  { %s: el fichero de ayuda, sin carpeta }
  SR_DOCS_NO_ABRE_FMT =
    '[DOCS-014 INTERNAL] The help file %s is registered and on disk, but ' +
    'Windows'' help storage (itss.dll) does not open it: it may be damaged. ' +
    'Report it with delphi_report.';

  SR_DOCS_NINGUNA_ABRE =
    '[DOCS-015 INTERNAL] The help files are registered and on disk, but ' +
    'Windows'' help storage (itss.dll) opens none of them. Report it with ' +
    'delphi_report.';

  { %s: los antepasados de una clase, el mas cercano primero, unidos por ' > ' }
  SF_DOCS_ANCESTROS_FMT =
    'Ancestors: %s';

  { %s la ruta del .chm, %x el HRESULT: la excepcion de Lsp.Chm (no sale al
    agente: quien abre una ayuda la recoge) }
  SE_CHM_NO_ABRE_FMT =
    'the help file %s did not open (HRESULT %.8x)';

  // ---- delphi_help ----

  SD_HELP =
    'THE MAP of this server, so you do not have to work it out by trial ' +
    'and error. command=tasks (default) gives the task -> tool table, ' +
    'one line each: what to use to read, to edit, to build, for several ' +
    'files at once, to rename, for tests, to deploy. command=tool ' +
    'name=<tool> gives ONE whole tool (description + parameters) without ' +
    'asking for tools/list again, which brings them ALL at once. ' +
    'command=conventions gives the rules that apply to all of them: ' +
    'paths and virtual drives, the jail, how editing by anchor works, ' +
    'backups and encodings. The Delphi documentation itself (classes, ' +
    'routines, the language) is delphi_docs. Start here if you have just ' +
    'connected.';

  SP_HELP_COMMAND =
    'tasks (task -> tool table; default) | tool (one whole tool, with ' +
    '"name") | conventions (the rules common to all of them)';

  SP_HELP_NAME =
    'command=tool: name of the tool (delphi_edit, or just "edit")';

  SR_HELP_CMD =
    '[HELP-001 INVALID_PARAM] Command must be tasks | tool | conventions.';

  SR_HELP_NEED_NAME =
    '[HELP-007 INVALID_PARAM] command=tool needs "name". The ones there are:';

  SN_HELP_ASSUMED_FMT =
    '[HELP-008] (There is no tool "%s"; I took it that you meant %s, the ' +
    'only one that resembles it. If it was not that one, delphi_help ' +
    'command=tasks lists them all.)';

  SR_HELP_NO_TOOL_ALL_FMT =
    '[HELP-002 NOT_FOUND] There is no tool "%s", nor anything resembling ' +
    'it. These are ALL the ones there are: %s';

  SR_HELP_NO_TOOL_FMT =
    '[HELP-003 NOT_FOUND] There is no tool "%s". These resemble what you ' +
    'ask for: %s';

  SN_HELP_TOOL_NOTE =
    '[HELP-004] What rules is the tool''s description: this is the same ' +
    'one tools/list serves, only on its own. If something does not match ' +
    'what it really does, say so with delphi_report: contracts are ' +
    'corrected with real cases.';

  SN_HELP_TASKS =
    '[HELP-005] WHAT TO USE FOR EACH THING (the detail is in the ' +
    'description of each tool)'#10#10 +
    'FINDING YOUR WAY'#10 +
    '  where am I, what can I touch ....... delphi_workspace'#10 +
    '  what projects exist (repo/branch) .. delphi_projects'#10 +
    '  what Delphi is on this machine ..... delphi_installs'#10 +
    '  this table, or one whole tool ...... delphi_help'#10 +
    '  search text in the code ............ delphi_search'#10 +
    '  list the files of a folder ......... delphi_list'#10#10 +
    'READING AND UNDERSTANDING'#10 +
    '  read a file (or a range) ........... delphi_read'#10 +
    '  symbols of a unit .................. delphi_symbols'#10 +
    '  where it is defined / used ......... delphi_definition, ' +
    'delphi_references'#10 +
    '  errors without compiling ........... delphi_diagnostics'#10 +
    '  what components are installed ...... delphi_components'#10 +
    '  what IS this (type and doc) ........ delphi_hover'#10 +
    '  what the RAD Studio help says ...... delphi_docs'#10 +
    '  what parameters this call takes .... delphi_signature'#10 +
    '  what can I write here .............. delphi_completion'#10#10 +
    'WRITING'#10 +
    '  before NEW code: look around ....... conventions, point 14'#10 +
    '  change Pascal by ANCHOR ............ delphi_edit'#10 +
    '  change text that is not Pascal ..... delphi_textedit'#10 +
    '  several files ALL-OR-NOTHING ....... delphi_changeset'#10 +
    '  create project/unit/form/frame ..... delphi_create'#10 +
    '  delete / move a file ............... delphi_delete, delphi_move'#10 +
    '  upload a binary or a chunk ......... delphi_upload'#10 +
    '  rename a symbol .................... delphi_rename_symbol ' +
    '(preview, then mode=apply)'#10#10 +
    'PROJECT'#10 +
    '  framework, platforms, search path .. delphi_config'#10 +
    '  add/remove a unit of the project ... delphi_config add-unit / ' +
    'remove-unit'#10 +
    '  compile ............................ delphi_build'#10 +
    '  know whether it WORKS .............. delphi_test'#10 +
    '  run the program .................... delphi_paserver remote-run ' +
    '(on the target; nothing runs on the server)'#10#10 +
    'FORMS AND STYLES'#10 +
    '  what a class publishes ............. delphi_designer info / prop'#10 +
    '  review a .dfm/.fmx ................. delphi_designer lint / tree ' +
    '/ get / check-binding / layout'#10 +
    '  see a form as the designer does .... delphi_designer preview'#10 +
    '  add a control, change, remove ...... delphi_designer insert / set ' +
    '/ delete'#10 +
    '  FMX styles ......................... delphi_styles'#10#10 +
    'TAKING IT AWAY AND DEPLOYING'#10 +
    '  download a file .................... delphi_fetch'#10 +
    '  package a folder ................... delphi_package'#10 +
    '  deploy to a target ................. delphi_build target=Deploy'#10 +
    '  run it there ....................... delphi_paserver remote-run, ' +
    'delphi_adb run'#10 +
    '  Android ............................ delphi_adb'#10 +
    '  see and use a target''s desktop ..... delphi_desktop'#10#10 +
    'GIT AND MEMORY'#10 +
    '  branches, commit, diff, stash ...... delphi_git'#10 +
    '%s'#10 +
    'TALKING TO WHOEVER RUNS THE SERVER'#10 +
    '  report a failure or a friction ..... delphi_report'#10 +
    '  read what was left for you ......... delphi_messages'#10#10 +
    'WHAT EACH ONE IS CALLED is answered here; HOW TO CALL ONE, with ' +
    'delphi_help command=tool name=<whichever>, which gives you its ' +
    'whole description and ALL its parameters. That is what saves you ' +
    'from discovering the hard way that delphi_create accepts "content" ' +
    'with the whole source, or that delphi_edit accepts "edits" with ' +
    'several edits at once.'#10#10 +
    'And the common rules: delphi_help command=conventions.';

  SF_HELP_TASKS_VAULT_LEER =
    '  project memory ..................... vault_read, vault_search'#10;

  SF_HELP_TASKS_VAULT_ESCRIBIR =
    '  write to the memory ................ vault_append, vault_patch, ' +
    'vault_create'#10;

  { La credencial de solo lectura: tools/list no le anuncia las tools enteras
    de escritura (Lsp.Guard.ToolHiddenFromList), y la tabla de arriba se las
    nombraria igual (6-oct-2026). }
  SF_HELP_TASKS_SOLO_LECTURA =
    #10#10'YOUR CREDENTIAL IS READ-ONLY: the tools that only write are not ' +
    'announced to you (they would refuse), and the mixed ones answer only ' +
    'their reading commands - tools/list says which in _meta.access and ' +
    'readOnlyCommands.';

  { Lo que tools/list no anuncia y POR QUE (Lsp.Guard.MotivoToolOculta): un
    agente conto 37 tools donde la documentacion dice 42 y creyo que se
    habian fusionado (Hermes, validacion de la 1.16.0). }
  SF_HELP_TASKS_SIN_VAULT =
    #10#10'NO VAULT IN THIS WORKSPACE: the vault_* tools (the project memory: ' +
    'vault_read, vault_search, vault_append, vault_patch, vault_create) are ' +
    'not in tools/list here, so it has fewer tools than the documentation ' +
    'lists. Nothing was merged or removed: there is no memory to read.';
  SF_HELP_TASKS_VAULT_LECTURA =
    #10#10'THE VAULT IS READ-ONLY HERE: vault_append, vault_patch and ' +
    'vault_create are not in tools/list (they would refuse); vault_read and ' +
    'vault_search work.';
  SF_HELP_TASKS_PERFIL_FMT =
    #10#10'LEFT OUT OF tools/list BY THIS WORKSPACE''S TOOL PROFILE (the ' +
    'operator''s choice): %s.';

  SN_HELP_CONVENTIONS =
    '[HELP-006] HOUSE RULES (they apply to every tool)'#10#10 +
    '1. PATHS. The server''s drives travel VIRTUAL: srvd:, srvc:... Use ' +
    'them as they are in any path parameter; they only exist inside this ' +
    'MCP and never resolve on your disk. You will never receive a real ' +
    'drive letter.'#10#10 +
    '2. THE JAIL. Writing, only inside the "roots" that delphi_workspace ' +
    'reports. Reading, also in the library zone (RTL/VCL/FMX sources, ' +
    'components, SDK): look yes, touch no. Anything outside is always ' +
    'refused, with the reason.'#10#10 +
    '3. EDITING IS BY ANCHOR, not by line number. "old" is ONE whole ' +
    'line, copied literally from what you just read, and it has to be ' +
    'unique; if it appears twice, narrow it down with "atline". Never ' +
    'rewrite a whole file to change three lines: if the anchor fails, ' +
    'the file stays as it was and the answer tells you why.'#10#10 +
    '4. BACKUPS. Every tool that writes leaves a copy in the __delphi-patch ' +
    'trash next to the file, BEFORE touching it. An EDIT keeps one copy ' +
    'per day and file: the version before the first change of the day, ' +
    'which is what restore brings back. Replacing or deleting a WHOLE ' +
    'file (delphi_upload over one, delphi_delete, a changeset delete, ' +
    'to-text / to-binary, an out= that already existed) keeps, EVERY ' +
    'time, what the file said at that moment, stamped, in a drawer that ' +
    'says why: deleted, replaced, before-restore (the answer names the ' +
    'copy). A live file ALWAYS goes through there ' +
    'first: that is the safety net. When you no longer need a copy, ' +
    'delphi_delete with purge=true really deletes it, but ONLY inside ' +
    'the trash and only YOURS (see rule 12).'#10#10 +
    '5. ENCODING AND LINE ENDINGS are kept as they are. Do not convert a ' +
    'file in passing; if you need a character that does not fit in its ' +
    'codepage, use the Pascal literal (#$2714) OUTSIDE the quotes, ' +
    'concatenated.'#10#10 +
    '6. SEVERAL FILES AT ONCE: delphi_changeset. Stack (stage), look ' +
    '(preview), apply (commit). Either everything goes in or nothing ' +
    'does, and if something fails halfway, what was already done is ' +
    'undone. unstage removes a single operation.'#10#10 +
    '7. COMPILING IS NOT WORKING: delphi_build says "0 errors", ' +
    'delphi_test says "17 pass, 1 fails". Finish with the second.'#10#10 +
    '8. ONE ERROR BREEDS THE OTHERS. In a failed build start with ' +
    '"firstError": what comes after it is usually its shadow.'#10#10 +
    '9. RUNNING IS OPTIONAL AND IS OFF unless the operator turns it on ' +
    '(AllowTests, AllowRemoteRun, AllowBuildScripts). If it is refused, ' +
    'do not insist: say so with delphi_report and go on with something ' +
    'else.'#10#10 +
    '10. THE MAILBOX IS A NOTICE BOARD, NOT PRIVATE MAIL. It is indexed ' +
    'by the id you declare yourself, and all of you working here share ' +
    'the same token: anyone can read, and CONSUME, the mail of an id ' +
    'they guess. Read yours and do not dig into anyone else''s; the ' +
    'operator sends nothing secret through here, and neither do you.'#10#10 +
    '11. HOW TO READ AN ANSWER. Every refusal or failure STARTS with a ' +
    'tag [AREA-NNN OUTCOME], and the OUTCOME says what to do. ' +
    'INVALID_PARAM = the call itself is malformed (a parameter missing, ' +
    'a value with the wrong shape, two that do not combine): fix THE ' +
    'CALL and repeat. NOT_FOUND = the call is right but what it names is ' +
    'not there (a file, an anchor, a profile): find the right name and ' +
    'repeat. DENIED = the call is right and the thing exists, but a rule ' +
    'refuses it or something stands in the way (the jail, read-only, a ' +
    'feature the operator turned off, a file another process holds): the ' +
    'same call will fail again - do what the reason says, or change ' +
    'course. INTERNAL = I broke inside or a piece of my installation is ' +
    'missing; that is ALWAYS my failure, report it with delphi_report. A ' +
    'success declares no outcome. The same four codes are in ' +
    'structuredContent.code.'#10#10 +
    '12. WHO YOU ARE. You identify yourself ONCE, in the handshake, with ' +
    'clientInfo.name; the server binds it to your session and from then ' +
    'on knows who you are in every request without you repeating it. ' +
    'With that: delphi_messages reads YOUR mail without typing the id, ' +
    'and what YOU send to the trash only you can purge (another agent ' +
    'that tries gets a DENIED). It is not a password: the token is ' +
    'common to all and the name is what each client declares, so it ' +
    'keeps honest agents from stepping on each other - it does not stop ' +
    'one that lies about its name. Work in YOUR project folder and you ' +
    'will not step on anyone. If your client does not let you set ' +
    'clientInfo.name (it presents itself as "mcp" or with a generic ' +
    'name), pass agent=<your id> to delphi_report and delphi_messages on ' +
    'EVERY call: agent= wins over the handshake. Measured: an agent that ' +
    'was "hermes" by day and "mcp" by night left six notes unread.'#10#10 +
    '13. IF SOMETHING CANNOT BE DONE THROUGH HERE, THAT IS A FINDING. ' +
    'Report it with delphi_report (kind=limitation) with the exact call ' +
    'and what you expected: this whole server has been built from those ' +
    'reports.'#10#10 +
    '14. BEFORE WRITING NEW CODE, LOOK AT THE LANDSCAPE. One search ' +
    'answers most of it: (a) search for what the code DOES - a ' +
    'characteristic line of its body, one per delphi_search (it searches ' +
    'line by line; regex=true when needed) - not for the name you would ' +
    'give it; (b) where else ' +
    'does this rule live? Fix it where it lives, not where you happen to ' +
    'be looking (delphi_references gives the callers); (c) does something ' +
    'like it exist already? Often it is a parameter on what exists, not a ' +
    'sibling (delphi_symbols on a FOLDER says what each unit offers); (d) ' +
    'written twice is a helper with parameters, and a FORMAT (a name, a ' +
    'path, a key) has ONE function that writes it and one that reads it; ' +
    '(e) a diagnosis is a theory until it is measured: measure the cause ' +
    'before changing code for it.';

  // ---- delphi_test ----

  SD_TEST =
    'TESTS: the difference between "it compiles" and "it works". discover ' +
    '(path = a folder or project): the test projects underneath (a .dpr ' +
    'that uses DUnitX, or a console one whose name says test/spec). run ' +
    '(project = the test .dproj): builds and runs that runner and returns ' +
    'the STRUCTURED result - total, passed, failed, errored (a DUnitX test ' +
    'that raised; it fails the run too), the failures, exitCode, duration ' +
    'and the tail of its output - read from the DUnitX summary or the ' +
    'PASS/FAIL + ExitCode convention of a hand-written runner; verdictFrom ' +
    '(counts or exitCode) says where the verdict comes from, never ' +
    'invented. Running tests is RUNNING, the only thing that runs on this ' +
    'server, behind its own switch [Workspace.<name>] AllowTests (without ' +
    'it, discover works and run is refused). The binary runs in a Windows ' +
    'container of its own, on a COPY of its output folder: it reads and ' +
    'writes that copy and only what Windows gives every container (its own ' +
    'temp folder, deleted with it, and the system files) - no other file, ' +
    'no network, no network drive - and it is cut off at the timeout. So a ' +
    'test here is for LOGIC: what it reads has to travel in its output ' +
    'folder, and a project built with runtime packages (UsePackages) is ' +
    'refused before building: build it whole. What it writes in that ' +
    'folder comes back in "files" (text files with their content, capped).';

  SP_TEST_COMMAND =
    'discover (list the test projects under "path") | run (build and run ' +
    'the one in "project"). Default: discover';

  SP_TEST_PATH =
    'discover: folder (or project) under which to look for test projects';

  SP_TEST_PROJECT =
    'run: the .dproj (or .dpr) of the test project to run';

  SP_TEST_CONFIG =
    'run: configuration to build and run (Debug by default)';

  SP_TEST_FILTER =
    'run optional: test filter for frameworks that read it (DUnitX --run:, ' +
    'through TDUnitX.CheckCommandLine, which the delphi_create ' +
    'kind=project-test project calls); a runner that does not read its ' +
    'command line ignores it.';

  SP_TEST_TIMEOUT =
    'run optional: maximum run time in milliseconds (120000 by default, ' +
    'maximum 600000); a test that hangs is cut off and the answer says so.';

  SP_TEST_NOBUILD =
    'run optional: true = run the binary that already exists, without ' +
    'building first (by default it builds: running an old binary is lying).';

  SP_TEST_PLATFORM =
    'run optional: platform to build and run - by default the project''s ' +
    'own, as the IDE. Only one the project declares and of THIS machine: ' +
    'the binary runs here';

  SR_TEST_PLATFORM_UNKNOWN_FMT =
    '[TEST-001 INVALID_PARAM] "%s" is not a Delphi platform. Valid for ' +
    'running here: Win32 and Win64.';

  SR_TEST_NOBINARY_NOBUILD =
    '[TEST-002 INVALID_PARAM] You asked for nobuild=true (do not build) ' +
    'and there is no binary there to run. Either build first (remove ' +
    'nobuild, or delphi_build with that SAME platform and config), or ' +
    'point to the config that does have a binary.';

  SN_TEST_STALE_FMT =
    '[TEST-003] NOTE: %s is NEWER than the binary I just ran. You ' +
    'touched the code after building it, so these numbers are from the ' +
    'previous version. Remove nobuild=true and launch it again.';

  SN_TEST_NEAR_MISS_FMT =
    '[TEST-004] NOTE: there are %d line(s) that LOOK like a result and ' +
    'that I did NOT count; the first is "%s". Check the format in ' +
    'command=discover ("countsFormat"): the first word has to be ' +
    'PASS/PASSED/OK or FAIL/FAILED/ERROR. If those lines were failures ' +
    'of yours, the verdict above falls short.';

  SR_TEST_NAME_NOT_PATH_FMT =
    '[TEST-005 INVALID_PARAM] "%s" looks like the NAME of the project, ' +
    'and here its full PATH is needed: dir + name of its entry in ' +
    'delphi_projects or delphi_test discover.';

  SR_TEST_CONFIG_FMT =
    '[CFG-107 NOT_FOUND] The configuration "%s" does not exist in this ' +
    'project. It has these: %s.';

  SR_TEST_PLATFORM_FMT =
    '[TEST-007 DENIED] %s cannot be RUN on this machine, and running is ' +
    'what this tool is about. Build for that platform with delphi_build ' +
    'and take it there with delphi_paserver / delphi_adb.';

  SN_TEST_TIMEOUT_NOTE =
    '[TEST-008] TIME RAN OUT and I KILLED the process: it is not that ' +
    'the tests fail, it is that they did not finish. That is why ' +
    'exitCode comes as 1. The numbers you see are from what it managed ' +
    'to print BEFORE dying, so they are incomplete even if they look ' +
    'good: do not take them as the result. And if "outputTail" comes ' +
    'empty, it is because the output of a console program is kept in a ' +
    'buffer and only written out at the end, so killing it loses it; ' +
    'with Flush(Output) after each line you will see it. If you expect ' +
    'it to take long, raise "timeoutms".';

  SN_TEST_NO_COUNTS_FAILED_FMT =
    '[TEST-009] FAILED. I could not count the tests (the runner does not ' +
    'print a format I understand), but it returned exit code %d, and ' +
    'that is the runner itself saying something went wrong: do NOT take ' +
    'it as good. Look at outputTail to see what failed, and if you want ' +
    'the count, follow countsFormat (first word PASS/OK/FAIL/ERROR per ' +
    'line).';

  SN_TEST_NO_COUNTS =
    '[TEST-010] It finished fine but I could NOT count a single test, so ' +
    'I do not tell you "pass": a binary ending with exitCode 0 does not ' +
    'prove it tested anything. Either the project runs no tests, or its ' +
    'output follows neither of the two formats I can read (see ' +
    '"countsFormat" in command=discover).';

  SN_TEST_CONSOLE_FORMAT =
    '[TEST-011] For me to count your tests, print ONE LINE PER CHECK ' +
    'whose FIRST WORD is PASS, PASSED or OK when it goes well, and FAIL, ' +
    'FAILED or ERROR when it goes wrong, followed by the description: ' +
    '"PASS sum of two integers" / "FAIL invalid email: expected False". ' +
    'Upper or lower case does not matter, and neither do leading spaces; ' +
    'what has to be exact is the WORD: "PASSABLE" does not count (it is ' +
    'not PASS), and "[ OK ] 12 something" does not either (it starts ' +
    'with a bracket). If you print lines that resemble it and do not ' +
    'count, I tell you in "linesNotCounted". And end with an ExitCode ' +
    'other than 0 if something failed. With DUnitX none of this is ' +
    'needed: its summary is read.';

  SN_TEST_RUNS_ON =
    '[TEST-012] command=run builds AND runs the SAME platform: the ' +
    'project''s own unless you pass platform=, the one delphi_build ' +
    'builds by default too. The program runs in a Windows container on a COPY of its ' +
    'output folder, with it as the current directory: it reads and ' +
    'writes that copy and, besides it, only what Windows gives every ' +
    'container (its own temp folder, deleted with it, and the system ' +
    'files under Windows and Program Files). ' +
    'TPath.GetTempPath comes back empty in there, so a file a Delphi ' +
    'test puts in it lands in the copy. Data files your tests read have ' +
    'to be in the output ' +
    'folder (copied there by the build, or written by the test itself): ' +
    'a path into the project (..\..\data) does not exist in there. No ' +
    'network: a connection to localhost hangs until TCP gives up (about ' +
    '21 s). What the test writes comes back in "files".';

  SN_TEST_NOBUILD_NOTE =
    '[TEST-013] nobuild=true: I did NOT build anything, I ran the binary ' +
    'that was already there ("builtAt" says when it is from). If you ' +
    'touched the code after that date, these numbers are from another ' +
    'program.';

  { Un parametro que no es del comando (Lsp.Guard.ParametroQueNoVa; decima). }
  SR_TEST_NO_VA_CON_COMANDO_FMT =
    '[TEST-025 INVALID_PARAM] "%s" does not go with command=%s (it would ' +
    'be ignored). Nothing was done: %s takes %s.';

  SR_TEST_CMD =
    '[TEST-014 INVALID_PARAM] Command must be discover | run';

  SR_TEST_NEED_PATH =
    '[TEST-015 INVALID_PARAM] discover needs "path" (the folder or the project ' +
    'under which to search).';

  SR_TEST_NEED_PROJECT =
    '[TEST-016 INVALID_PARAM] run needs "project" (the .dproj of the test ' +
    'project). command=discover lists them for you.';

  SR_TEST_NOPATH_FMT =
    '[TEST-017 NOT_FOUND] %s does not exist.';

  SR_TEST_NOTATEST_FMT =
    '[TEST-018 INVALID_PARAM] %s does not look like a test project. What counts ' +
    'as one is a .dpr that uses DUnitX, or one with {$APPTYPE CONSOLE} ' +
    'whose name says test/tests/spec. If yours is one and I do not ' +
    'detect it, say so with delphi_report: the criterion is refined with ' +
    'real cases.';

  SR_TEST_NOBINARY =
    '[TEST-019 INTERNAL] I cannot find the test project''s binary ' +
    'after building. Build by hand with delphi_build and look at what it ' +
    'declares in "output".';

  SR_TEST_DISABLED =
    '[TEST-020 DENIED] Running tests is OFF on this server. The operator ' +
    'turns it on with [Workspace.<name>] AllowTests=1 in the ' +
    'settings.ini next to the executable (or DELPHI_MCP_ALLOW_TESTS=1) ' +
    'and restarts. It is the only thing that runs on this machine: a ' +
    'binary from a project in the jail, in a container of its own and ' +
    'with a timeout. command=discover does work without it.';

  SN_TEST_NONE =
    '[TEST-021] There are no test projects under there. What counts as ' +
    'one is a .dpr with DUnitX or a console one whose name says ' +
    'test/spec.';

  SN_TEST_DISCOVER_NOTE =
    '[TEST-022] Run them with command=run project=<dir + name from the ' +
    'list> (the .dpr: run takes it for its .dproj). One with ' +
    'hasDproj=false cannot be built or run here (delphi_build takes a ' +
    '.dproj): opening it once in the IDE creates it, or create the test ' +
    'project with delphi_create kind=project-test.';

  SN_TEST_BUILD_FAILED =
    '[TEST-023] The test project does NOT compile, so there is nothing ' +
    'to run: look at "build.errors" (and "missingUnits" if a unit is ' +
    'missing). Fix that first.';

  // TEST-024 (de donde sale el veredicto, el contenedor) iba en cada
  // ejecucion; se retiro el 4-oct-2026: lo dice la descripcion de la tool.

  { La jaula de delphi_test: un contenedor por ejecucion (Lsp.Sandbox,
    2-oct-2026). Falla cerrado: sin contenedor, el test no corre. }
  SR_TEST_CONTENEDOR_FMT =
    '[TEST-026 INTERNAL] I could not prepare the Windows container the ' +
    'test runs in (code %s: %s), so I did NOT run it: a test never runs ' +
    'outside one. It is a problem of this server, not of your project: ' +
    'tell the operator.';

  SR_TEST_LANZAR_FMT =
    '[TEST-027 INTERNAL] Windows did not start the test inside its ' +
    'container (error %d: %s), and it was NOT run outside it either. ' +
    'The build is fine; if it happens again, tell the operator.';

  SR_TEST_PAQUETES_FMT =
    '[TEST-028 INVALID_PARAM] %s is built with runtime packages in %s/%s ' +
    '(UsePackages), and a test runs here as ONE whole binary: its ' +
    'container reads no .bpl of components or of your project (only ' +
    'those under Program Files), so the program would not even start. ' +
    'Build the test project without runtime packages for that ' +
    'configuration and run it again. Nothing was built.';

  SR_TEST_COPIA_TOPE_FMT =
    '[TEST-029 DENIED] The output folder of this test is too big to copy ' +
    'into its container (more than %d MB without the .dcu and .rsm ' +
    'files). Give the test project an output folder of its own ' +
    '(DCC_ExeOutput) instead of one it shares with big binaries.';

  SR_TEST_COPIA_FMT =
    '[TEST-031 INTERNAL] I could not copy the output folder of this test ' +
    'into its container (%s), so it did NOT run. Look at what that ' +
    'folder holds - a broken link, a file another program keeps open - ' +
    'and run it again.';

  { El job object es obligatorio en el contenedor: si el test no se puede
    confinar en uno, no corre (fail-closed, revision Opus 4.8 de la 1.11.0).
    Sin el codigo de Windows: cuando el job no se crea, GetLastError es basura
    de una llamada previa (medido: "error 18"). }
  SR_TEST_SIN_JAULA =
    '[TEST-032 INTERNAL] I could not confine the test to its Job Object, so ' +
    'it was NOT run: a test never runs unconfined here. It is a problem of ' +
    'this server, not of your project: tell the operator.';

  SN_TEST_FICHEROS_RECORTE_FMT =
    '[TEST-030] Not every file in "files" came back whole: the content of ' +
    'each text file is capped at %d characters and all of them together ' +
    'at %d (an emoji counts as two; "truncated" marks the cut ones), and ' +
    'a file over %d MB, or one past the total, comes without it - ' +
    '"noContent" says why for each file. Write a shorter log, or print ' +
    'what matters to the output.';

  SN_TEST_FICHEROS_FUERA_FMT =
    '[TEST-033] The test left %d more files that are not in "files": the ' +
    'list stops at %d. Write fewer files, or print what matters to the ' +
    'output.';

  // Un contenedor que Windows no quiso borrar: lo barre el siguiente
  // arranque (PurgaContenedoresHuerfanos), y queda apuntado (revision de la
  // 1.11.0: se perdia sin rastro)
  SL_TEST_CONTENEDOR_NO_BORRADO_FMT =
    'delphi_test: the container %s was not deleted (0x%s); the next start ' +
    'of this server purges it';
  // ...y su gemela, la copia que no se pudo borrar
  SL_TEST_COPIA_NO_BORRADA_FMT =
    'delphi_test: the copy %s was not deleted (%s); the next start of this ' +
    'server purges it';

  // EsperaJobVacio: el job del test no se pudo matar o consultar. No corta la
  // limpieza (va acotada por plazo), pero queda en el log (revision Opus 4.8)
  SL_TEST_JOB_TERMINAR_FMT =
    'delphi_test: could not terminate the test Job Object (error %d); ' +
    'waiting for its processes to end on their own';
  SL_TEST_JOB_CONSULTAR_FMT =
    'delphi_test: could not query the test Job Object (error %d); stopped ' +
    'waiting for its processes - the copy is cleaned up anyway';

  // El contenedor no arranca si su estacion/escritorio no concede acceso a
  // los AppContainers (ALL APPLICATION PACKAGES): user32 falla al iniciar
  // (0xC0000142). WinSta0\Default la trae; la estacion de un SERVICIO (sesion
  // 0) no. Medido 3-oct-2026: era por que delphi_test fallaba en produccion.
  SL_TEST_ESTACION_FMT =
    'delphi_test: could not grant AppContainers access to the %s (error %d); ' +
    'a test launched from a Windows Service would fail to start (0xC0000142)';

  // ---- delphi_designer ----

  SD_DESIGNER =
    'FORMS AND COMPONENTS, structured - never guess what a class publishes ' +
    'or what a form contains (each command in "command"). Classes (info, ' +
    'prop) are read from the source of the active Delphi - its library and ' +
    'browsing paths, so installed components with source are in too; forms ' +
    '(tree, get, lint, check-binding, layout) from the .dfm/.fmx, a BINARY ' +
    '.dfm read on the fly; preview DRAWS the form as the IDE designer shows ' +
    'it and returns the image. insert, set and delete EDIT the form and its ' +
    'unit the way the IDE does: to add a visual control use insert (its ' +
    'block is not written by hand; a non-visual component, or a class the ' +
    'table does not have, is - the refusal says how), to change one ' +
    'property set, to remove one delete; then preview to see it. ' +
    'to-text/to-binary convert a .dfm. A ' +
    'read-only credential gets the reading commands (preview leaves its PNG ' +
    'in the workspace temp, so it is not one of them).';

  SP_DESIGNER_COMMAND =
    'info (every property a class really publishes: kind and type, events ' +
    'apart) | prop (one property in detail, with the legal members of an ' +
    'enum/set) | tree (the component tree: name, class, line) | get (one ' +
    'component''s block, verbatim) | lint (first what the IDE''s own form ' +
    'parser says, then properties the class does not publish and values ' +
    'their type does not take, as set judges them; objects it could not check ' +
    '- a class not in the table, or ambiguous - go apart as notes) | ' +
    'check-binding (does the .dfm agree with the class in the .pas: ' +
    'components with no published field, events naming a method that is ' +
    'not published, published fields with no component, duplicate names - ' +
    'all of which COMPILE and then throw when the form is created) | ' +
    'layout (WHERE things end up on a VCL .dfm: resolves Align and returns ' +
    'every control''s rectangle plus those of size zero, outside their ' +
    'container, overlapping or clipped by the bands around them - a form ' +
    'can bind perfectly and still be unusable) | to-text (a BINARY .dfm ' +
    'becomes text on disk, the IDE''s own conversion, backup first - ' +
    'reading never needs it) | to-binary (the way back, the ' +
    'resource-wrapped form the IDE writes) | preview (a PNG of what the IDE ' +
    'designer shows for the .dfm/.fmx, in this answer: built in design mode ' +
    'with the IDE''s installed packages, no code run and nothing on any ' +
    'screen; nonVisual lists the non-visual components, fidelity says how ' +
    'it was painted) | insert (a NEW visual control: classname; component, ' +
    'its Name - the IDE''s Button1, Button2... by default; parent - the ' +
    'form by default; placed at 10,10 as the last child, with its published ' +
    'field in the form''s class and its unit in the uses; the answer is its ' +
    'numbered block) | set (ONE property: prop + value, checked against the ' +
    'property''s type and the ' +
    'class BEFORE writing; parent= alone moves the component; before=, ' +
    'after= or index= alone reorders it among its siblings; prop=Name ' +
    'renames it, its field and the form lines that name it) | delete (the ' +
    'component and what is inside it, the references to it in the form, its ' +
    'field and its EMPTY handlers; refused while a method of its own has ' +
    'code - the answer lists them with their line, to clean first). ' +
    'Default: info';

  SP_DESIGNER_PATH =
    'tree/get/lint/check-binding/layout/preview/insert/set/delete/to-text/' +
    'to-binary: the .dfm or .fmx file. The reading commands and preview ' +
    'read a binary .dfm too, on the fly; insert, set and delete edit a text ' +
    'form (command=to-text converts it, backup first). insert, delete and a ' +
    'rename also write its unit, the .pas of the same name';

  SP_DESIGNER_CLASS =
    'info/prop: the component class, e.g. TButton, TEdit, TLayout. insert: ' +
    'the class of the new control';

  SP_DESIGNER_PROP =
    'prop: the property name, e.g. Align, Caption, TextSettings. set: the ' +
    'property to write, dotted for a sub-property (Font.Size, Position.X); ' +
    'Name renames the component';

  SP_DESIGNER_COMPONENT =
    'get: the component Name as it appears in the form (object <Name>: ' +
    '<Class>). preview: crop the image to that component (one inside an ' +
    'inline frame goes as Frame1.Name); componentRect ' +
    'says where it is in the form. set/delete: the component to change or ' +
    'delete. insert optional: the Name of the new control (an identifier ' +
    'free in the form and its class), its text too when the class shows ' +
    'one; without it, the IDE''s own (Button1, Button2...)';

  SP_DESIGNER_FRAMEWORK =
    'info/prop: vcl | fmx (default vcl). preview: the file decides (.dfm = ' +
    'vcl, .fmx = fmx); if given, it must agree';

  SP_DESIGNER_FILTER =
    'info optional: only properties whose name contains this text';

  { tree con tope de niveles (nota de Hermes: un form grande daba un arbol
    enorme y no habia forma de pedir solo lo de arriba; 4-oct-2026) }
  SP_DESIGNER_MAXDEPTH =
    'tree optional: how many levels to show (1 = only the form; 0 or empty ' +
    '= all). An object on the last level shows childrenCount instead of its ' +
    'children';

  { preview (RenderForm, 1.17.0): el estado de vista, el estilo, los no
    visuales y donde cae el PNG. inline y maxwidth son los de la familia de
    captura (SP_CAPTURE_INLINE / SP_CAPTURE_MAXWIDTH). }
  SP_DESIGNER_STATE =
    'preview optional: a VIEW state applied before drawing, never written ' +
    'to the file - Component.Property=Value (inside an inline frame, ' +
    'Frame1.Component.Property=Value), several separated by ; ' +
    '(PageControl1.ActivePage=TabSheet2;Edit1.Text=hello). A value with a ; ' +
    'goes in single quotes as in a form (Edit1.Text=''a;b''; a quote inside ' +
    'is written twice); a quote that does not start the value is just a ' +
    'letter (Label1.Caption=It''s). A property that holds a component takes ' +
    'the component''s name. No double quotes.';

  SP_DESIGNER_STYLE =
    'preview optional. VCL: a .vsf file (the form is then drawn out of ' +
    'design mode: VCL styles never apply to designed controls) or none (the ' +
    'default, as the designer). FMX: empty = the form''s own StyleBook (as ' +
    'the designer), none = the Windows default, a .style file, or a ' +
    'platform of the designer''s Style list (android, ios, win11...; an ' +
    'unknown name is answered with the list). A file goes by absolute path.';

  SP_DESIGNER_NONVISUAL =
    'preview optional: true = draw the non-visual components (TTimer, ' +
    'TActionList, datasets...) where the designer puts them, with their ' +
    'icon and name. Default false: the image shows the form as it will ' +
    'look, and nonVisual lists them anyway.';

  SP_DESIGNER_OUT =
    'preview: where the PNG lands' + SP_CAPTURE_OUT_RULE;

  { insert / set (1.17.0) }
  SP_DESIGNER_PARENT =
    'insert: the container that receives the new control, by its Name (the ' +
    'form by default). set: MOVE the component, with its children, into this ' +
    'container - alone, without prop or value; it keeps its Left/Top, now ' +
    'relative to the new parent, and takes the next TabOrder there.';

  SP_DESIGNER_VALUE =
    'set: the new value, as the form file writes it: 120, True, alClient, ' +
    '[akLeft, akTop], clRed, the Name of another component (PopupMenu1), nil ' +
    'to clear one. A string goes quoted (''OK'', ''Acci''#243''n'') or not ' +
    '(OK): set writes it the way the IDE does, accents as #N and a long one ' +
    'in pieces; so does a number as typed (0.7).';

  SP_DESIGNER_PROPS =
    'insert / set optional: SEVERAL properties at once, Prop=value pairs ' +
    'separated by ; (Caption=Save;Left=24;Font.Style=[fsBold]) - each value ' +
    'as in "value", and a ; inside a quoted value does not split (a quote ' +
    'that does not start the value is just a letter: Caption=Don''t). insert: ' +
    'the initial properties of the new component; set: instead of ' +
    'prop/value. Each one is judged as set judges one, and it is all or ' +
    'none: one that does not pass and nothing is written. Name goes alone.';

  SP_DESIGNER_BEFORE =
    'set optional: put the component just BEFORE this sibling (its Name, the ' +
    'same parent), alone. Before writing, the IDE''s own writer is asked with ' +
    'the form loaded as the designer loads it: an order it would not keep ' +
    '(VCL graphic controls go before windowed ones, an inherited form places ' +
    'by its [n]...) is refused with the order it would save.';
  SP_DESIGNER_AFTER =
    'set optional: put the component just AFTER this sibling (its Name), ' +
    'alone - the same check as before.';
  SP_DESIGNER_INDEX =
    'set optional: the component''s position among its siblings in the file, ' +
    '1 = the first, alone - the same check as before. The file order is the ' +
    'z-order (a later one is drawn on top; an inherited form counts only what ' +
    'its own file writes); TabOrder is the keyboard order.';

  { Un parametro que no es del comando (Lsp.Guard.ParametroQueNoVa; decima). }
  SR_DESIGNER_NO_VA_CON_COMANDO_FMT =
    '[DSGN-047 INVALID_PARAM] "%s" does not go with command=%s (it would ' +
    'be ignored). Nothing was done: %s takes %s.';

  SR_DESIGNER_CMD =
    '[DSGN-001 INVALID_PARAM] Command must be info | prop | tree | get | ' +
    'lint | check-binding | layout | preview | insert | set | delete | ' +
    'to-text | to-binary';

  { delphi_designer command=preview: el renderizador (Lsp.FormRender) }
  SR_DESIGNER_SIN_RENDER_FMT =
    '[DSGN-060 INTERNAL] The form renderer %s is not next to the server ' +
    '(%s). It ships in the release zip beside DelphiLspMcp.exe; the ' +
    'operator copies it there. tree, get, lint and layout read the form ' +
    'without it.';

  SR_DESIGNER_RENDER_FALLO_FMT =
    '[DSGN-061 INTERNAL] The renderer could not draw %s: %s. The usual ' +
    'causes: the file is not a form it can read, a design package the form ' +
    'needs failed while loading, or a component failed while painting ' +
    '(that takes the renderer down, never the server). tree, lint and ' +
    'layout read the file without loading anything.';
  { preview con propiedades que el lector se salto (el Ignore del IDE): que
    guie al modelo, no solo que lo cuente (David, 7-oct-2026) }
  SN_DESIGNER_PREVIEW_IGNORADAS =
    '[DSGN-114] These properties were skipped as the IDE''s Ignore would, and ' +
    'the rest was drawn. The form will fail to open until they are fixed (the ' +
    'program cannot create it, and the IDE asks to ignore each one): set them ' +
    'with delphi_designer set, or remove them - line says where each one is.';
  { El recorte lo hace el SERVIDOR (RecortaPng), con la imagen ya pintada:
    decir que el renderizador no pudo dibujar era falso (segunda revision de
    la 1.17.0) }
  SR_DESIGNER_RECORTE_FALLO_FMT =
    '[DSGN-113 INTERNAL] %s was drawn, but cropping the image to %s failed: ' +
    '%s. Without component the whole form comes back.';

  SR_DESIGNER_RENDER_TIEMPO_FMT =
    '[DSGN-062 DENIED] %s did not answer in %d s and was stopped: something ' +
    'in the form waits (a package, a dialog it could not show). Nothing ' +
    'reached the server''s desktop.';

  SR_DESIGNER_RENDER_SIN_BPL_FMT =
    '[DSGN-063 INTERNAL] %s could not start: Windows did not find its ' +
    'runtime packages (rtl, vcl, fmx of RAD Studio %s; code 0x%.8x). They ' +
    'live in that RAD Studio''s bin folder, which has to be on the PATH of ' +
    'the account the server runs as.';

  SR_DESIGNER_LITERAL_FUERA_FMT =
    '[DSGN-115 DENIED] Property %s names a path outside the allowed ' +
    'read locations. Nothing was rendered. Keep referenced files in an allowed ' +
    'read location; the property value is never shown.';

  SR_DESIGNER_LITERAL_NO_VERIFICABLE =
    '[DSGN-116 DENIED] The form strings could not be checked before rendering. ' +
    'Nothing was rendered. Use tree or lint to inspect the form first.';

  SR_DESIGNER_LITERAL_TOPE_FMT =
    '[DSGN-117 DENIED] Form data to check exceeds the %d MiB rendering budget. ' +
    'Nothing was launched. Reduce embedded assets or use a smaller form folder.';

  { En FMX Left y Top los guarda TComponent (DefineProperties): son el sitio
    del ICONO de un no visual en el disenador, no el de un control, que va en
    Position.X/Y. set los escribia, contestaba bien y no movia nada (3.7 de
    la 1.18.0, Hermes); el lint lo avisa con el fragmento de abajo, sin
    etiqueta como todo fragmento. }
  SR_DESIGNER_FMX_LEFT_TOP_FMT =
    '[DSGN-118 INVALID_PARAM] In FMX the place of a control is Position.X / ' +
    'Position.Y: %s.%s would be written and would not move it (Left and Top ' +
    'are where the designer draws a NON-visual component''s icon). Nothing ' +
    'was written. Use prop=%s.';
  { Una ruta por una propiedad que en su bloque guarda una REFERENCIA a otro
    componente (PopupMenu = PopupMenu1 y prop=PopupMenu.AutoPopup): el
    cargador lee la ruta antes de resolver las referencias, la propiedad
    aun esta vacia y el form no carga. set la escribia en el boton y el lint
    decia CLEAN (3.3 de la 1.18.0, medido); el lint lo avisa con el
    fragmento de abajo. %s = el componente, la propiedad, el referido, el
    resto de la ruta, la propiedad, el referido dos veces y el resto. }
  SR_DESIGNER_SET_POR_REFERENCIA_FMT =
    '[DSGN-119 INVALID_PARAM] %s.%s holds a reference to another ' +
    'component, %s: %s is a property of that component, not a part of ' +
    'this one, and the form loader reads it before references are resolved ' +
    '(%s is still empty there and the form does not load). Nothing was ' +
    'written. Set it on %s: component=%s prop=%s.';
  { El juez de tipos de set (BaseQueNoCasa) tambien en lint: decia CLEAN de
    Color = 'hola', que el form no carga (3.1 de la 1.18.0). Fragmento: la
    linea la pone el lint. }
  SF_DSGN_LINT_TIPO_FMT =
    '%s is %s and takes %s, not %s.%s The form will not load.';
  SF_DSGN_FMX_LEFT_TOP_FMT =
    '%s does not place an FMX control (it is where the designer ' +
    'draws a non-visual component''s icon); its place is %s.';
  SF_DSGN_POR_REFERENCIA_FMT =
    '%s holds a reference to another component (%s = %s): %s is a ' +
    'property of that component, and the form loader reads this line ' +
    'before references are resolved - %s is still empty there and the ' +
    'form does not load (or it is the part the reference replaces, and the ' +
    'value is lost). Set %s on %s.';

  SR_DESIGNER_RENDER_NO_ARRANCA_FMT =
    '[DSGN-064 INTERNAL] %s could not be started: %s';

  SR_DESIGNER_VALOR_CON_COMILLAS_FMT =
    '[DSGN-065 INVALID_PARAM] "%s" carries a double quote or a control ' +
    'character, which cannot travel to the renderer as one value. Nothing ' +
    'was drawn: write it without them.';

  SR_DESIGNER_PREVIEW_SIN_COMPONENTE_FMT =
    '[DSGN-066 NOT_FOUND] There is no component %s drawn in %s, so there ' +
    'is nothing to crop to: delphi_designer command=tree lists its ' +
    'components, and one inside an inline frame goes as Frame1.Name. A ' +
    'non-visual one is drawn only with nonvisual=true, and only the ' +
    'form''s own (as the designer). Without component the whole form ' +
    'comes back.';

  SN_DESIGNER_FIDELIDAD_PRINT =
    '[DSGN-067] fidelity=print: drawn control by control (WM_PRINT), the ' +
    'way that works from a Windows service. Controls that paint their own ' +
    'way come out with the native look; geometry, text and layout are the ' +
    'real ones. A server in tray mode (an interactive session) paints them ' +
    'for real: fidelity=window.';

  SN_DESIGNER_SUSTITUIDAS =
    '[DSGN-068] substituted: classes no installed package registers, drawn ' +
    'as a pink box with the class name, at their place and size. If they ' +
    'should exist, the package that brings them is not installed in this ' +
    'RAD Studio (delphi_components lists what is).';

  SN_DESIGNER_NO_VISUALES_OCULTOS =
    '[DSGN-069] nonVisual: the non-visual components of the form, NOT ' +
    'drawn (nonvisual=false, the default). nonvisual=true draws each one ' +
    'with its icon and name where the designer puts it.';

  SN_DESIGNER_FRAME_NOTE =
    '[DSGN-070] frame (<imgW>x<imgH>@<srcW>x<srcH>+<ox>+<oy>) maps this ' +
    'image to the form: a point (x,y) measured ON THIS IMAGE is at ' +
    'ox + x*srcW/imgW, oy + y*srcH/imgH of the form''s client area, in ' +
    '.dfm/.fmx units (the renderer is not DPI-aware: 1 pixel = 1 unit). ' +
    'Left/Top in the file are relative to the control''s parent: subtract ' +
    'the parent''s componentRect.';

  SN_DESIGNER_INLINE_NOTE_FMT =
    '[DSGN-071] The image is IN this answer (scaled %s of the render). ' +
    'Measure on it and convert with frame (below). Its temp file was ' +
    'consumed: preview again for a new one; inline=false gives file + ' +
    'download instead; a preview with out= is yours and stays.';

  SR_DESIGNER_STYLE_VCL_FMT =
    '[DSGN-072 INVALID_PARAM] A VCL form takes a .vsf file as style (by ' +
    'absolute path) or none; "%s" is neither, and the designer''s platform ' +
    'styles are FMX.';

  SR_DESIGNER_STYLE_NOMBRE_FMT =
    '[DSGN-073 INVALID_PARAM] style "%s" is neither a file (an absolute ' +
    'path that exists) nor a platform name (letters, digits and -).';

  SR_DESIGNER_FW_NO_CASA_FMT =
    '[DSGN-074 INVALID_PARAM] framework=%s does not go with %s: a .dfm is ' +
    'VCL and a .fmx is FMX. Leave framework out for preview.';

  { delphi_designer insert / set / delete (Lsp.DesignerEdit, 1.17.0): editar
    el form y su unidad como el IDE, lo basico (David, 4 y 7-oct-2026). }
  SR_DESIGNER_EDIT_BINARIO_FMT =
    '[DSGN-075 INVALID_PARAM] %s is a BINARY .dfm: insert, set and delete ' +
    'edit a text form. Convert it first with command=to-text (backup first) ' +
    'and repeat.';

  SR_DESIGNER_EDIT_SIN_UNIDAD_FMT =
    '[DSGN-076 NOT_FOUND] The unit of %s is not next to it (%s): insert, ' +
    'delete and a rename write the form AND its class, where each component ' +
    'has its published field. The unit has the name of the form file.';

  SR_DESIGNER_EDIT_SIN_CLASE_FMT =
    '[DSGN-077 NOT_FOUND] The class %s of the form is not declared in %s, so ' +
    'its fields cannot be written. Nothing was written: command=check-binding ' +
    'says where the form and its unit disagree.';

  SR_DESIGNER_COMPONENTE_NO_ESTA_FMT =
    '[DSGN-078 NOT_FOUND] There is no component %s in %s. Nothing was ' +
    'written. Its components: %s. To add one, command=insert; one inside an ' +
    'inline frame (Frame1.Name) belongs to the frame''s own file: edit it ' +
    'there.';

  SR_DESIGNER_INSERT_NO_VISUAL_FMT =
    '[DSGN-079 INVALID_PARAM] %s is not a visual control (it does not descend ' +
    'from %s): insert places controls only, so nothing was written. A ' +
    'non-visual component (a TTimer, a dataset, an image list) goes in by ' +
    'hand: %s';

  SR_DESIGNER_PADRE_VCL_FMT =
    '[DSGN-080 INVALID_PARAM] %s (%s) cannot hold controls: in VCL a parent ' +
    'is the form or a windowed control whose class takes them in the ' +
    'designer (csAcceptsControls: TPanel, TGroupBox, TScrollBox, a TTabSheet ' +
    'rather than its TPageControl; not a TButton). Nothing was written.';

  SR_DESIGNER_PADRE_FMX_FMT =
    '[DSGN-081 INVALID_PARAM] %s (%s) is not a control, so it cannot hold ' +
    'one: in FMX a parent is the form or a control (TLayout, TRectangle, ' +
    'TPanel...). Nothing was written.';

  SR_DESIGNER_CLASE_SIN_TABLA_FMT =
    '[DSGN-082 INVALID_PARAM] %s is a %s, a class the %s table does not have ' +
    '(a component without source in the library paths, or of the other ' +
    'framework): %s cannot be checked, so nothing was written. %s';
  SF_DESIGNER_QUE_PROPIEDADES =
    'its properties';
  SF_DESIGNER_QUE_CONTENEDOR =
    'whether it holds controls';
  SF_DESIGNER_VIA_LINEA =
    'Edit the line with delphi_edit and run command=lint after.';
  SF_DESIGNER_VIA_CONTENEDOR_FMT =
    'To do it anyway, by hand: %s';
  { La salida de set parent= cuando el padre no se puede juzgar: mover es
    mover su bloque; el campo y la unidad ya estan (segunda revision de la
    1.17.0: le pedia escribirlos). }
  SF_DESIGNER_MOVER_A_MANO =
    'with delphi_edit, its object block (with everything inside it) moved ' +
    'inside that parent''s block, before its end; its field and its unit ' +
    'stay as they are. Then command=check-binding and layout.';
  { La salida de insert cuando no puede (no visual, clase sin tabla, padre
    sin tabla): el bloque, el campo y el uses a mano (revision de la 1.17.0:
    "su bloque nunca se escribe a mano" no dejaba camino). }
  SF_DESIGNER_A_MANO =
    'with delphi_edit, its object block inside its parent''s block in the ' +
    'form, before that parent''s end - a non-visual one in the form''s own ' +
    'block (object Timer1: TTimer ... end) -; its published field in the ' +
    'form''s class (Timer1: TTimer;); its unit in the uses of the interface ' +
    '(delphi_edit adduses=<unit> section=interface: without section it goes ' +
    'to the implementation, which the field cannot see). Then ' +
    'command=check-binding and lint.';
  SF_DESIGNER_INSERT_SIN_TABLA_FMT =
    ' To add it anyway, by hand: %s';
  SF_DESIGNER_INSERT_TRAS_USES_FMT =
    ' insert writes nothing until %s is in the uses: add it there by hand ' +
    '(delphi_edit, in the right branch) and repeat the insert - a unit ' +
    'already in the uses (in its first branch at least) is not added again.';

  SR_DESIGNER_DENTRO_DE_INLINE_FMT =
    '[DSGN-083 INVALID_PARAM] %s is part of the frame %s placed in this form ' +
    '(inline): its components belong to the frame''s own file. Insert, ' +
    'delete, rename or move them there.';

  SR_DESIGNER_HEREDADO_FMT =
    '[DSGN-084 INVALID_PARAM] %s is inherited from the ancestor form: it is ' +
    'deleted, renamed or moved in the ancestor''s file. Its properties can ' +
    'be set here.';

  SR_DESIGNER_RAIZ_FMT =
    '[DSGN-085 INVALID_PARAM] %s is the form itself: delete, rename and ' +
    'parent do not apply to it (set changes its properties).';

  { La regla de David (7-oct-2026): nunca codigo huerfano como el IDE. }
  SR_DESIGNER_DELETE_BLOQUEADO_FMT =
    '[DSGN-086 DENIED] %s was NOT deleted: it would leave %d method(s) of ' +
    'its own with code behind in %s - code that keeps compiling and never ' +
    'runs again. Clean each one first (move what it does elsewhere, or empty ' +
    'it) and repeat the delete; an empty one goes with the component:%s';
  SF_DESIGNER_METODO_LINEA_FMT =
    #10'  - %s (%s, %s)';
  SF_DESIGNER_POR_SU_NOMBRE =
    'named after it';

  SR_DESIGNER_SET_INVALIDO_FMT =
    '[DSGN-087 INVALID_PARAM] %s.%s = %s was NOT written: %s%s';
  SF_DESIGNER_QUIZAS_FMT =
    ' Did you mean %s?';

  SR_DESIGNER_SET_EVENTO_FMT =
    '[DSGN-088 INVALID_PARAM] %s is an event of %s: set does not bind ' +
    'events. To handle it: delphi_edit insert=metodo visibility=published in ' +
    'the form''s class, then the line %s = <method> in the component''s ' +
    'block (check-binding verifies the pair).';

  SR_DESIGNER_SET_BLOQUE_FMT =
    '[DSGN-089 INVALID_PARAM] %s.%s holds a list, a collection or a binary ' +
    'block (lines %d-%d of %s): set writes one-line values. Edit that block ' +
    'with delphi_edit.';

  SR_DESIGNER_SET_SIN_VALOR =
    '[DSGN-090 INVALID_PARAM] "value" is missing: set writes prop = value ' +
    '(or moves the component with parent=, alone).';

  SR_DESIGNER_SET_VALOR_LINEA =
    '[DSGN-091 INVALID_PARAM] value is one line: a form property holds no ' +
    'line break (#13#10 in a string value writes one).';

  SR_DESIGNER_SET_GRAMATICA_FMT =
    '[DSGN-092 INVALID_PARAM] value %s is not a one-line form value: a ' +
    'number, True/False, an identifier (alClient, clRed, a component name), ' +
    'a set [a, b] or a string. Nothing was written; lists, collections and ' +
    'binary blocks are edited with delphi_edit.';

  SR_DESIGNER_SET_TIPO_FMT =
    '[DSGN-093 INVALID_PARAM] %s.%s is %s and takes %s, not %s.%s Nothing ' +
    'was written.';
  SF_DESIGNER_TOMA_ENTERO =
    'a whole number';
  SF_DESIGNER_TOMA_ENTERO32 =
    'a whole number that fits in 32 bits, -2147483648 to 2147483647 (in hex, ' +
    'up to $7FFFFFFF): the form loader reads no more here';
  SF_DESIGNER_TOMA_ENTERO64 =
    'a whole number that fits in 64 bits';
  SF_DESIGNER_TOMA_VARIANTE =
    'a number, a string, True, False, Null or nil';
  SF_DESIGNER_TOMA_NUMERO =
    'a number';
  SF_DESIGNER_TOMA_CARACTER =
    'one character, quoted (''A'') or by its code (#65)';
  SF_DESIGNER_TOMA_CONSTANTE =
    'a whole number or one of the named constants of its type';
  SF_DESIGNER_TOMA_CONSTANTES_FMT =
    'a whole number or one of its named constants (%s)';
  { Una lista ABIERTA con sus formas leidas del fuente (generacion 12): lo
    que su IdentTo carga, y nada mas (segunda revision de la 1.17.0) }
  SF_DESIGNER_TOMA_ABIERTA_FMT =
    'a whole number, one of its named constants (%s), or what its reader ' +
    'also takes: %s. Anything else keeps the form from opening';
  SF_DESIGNER_FORMA_HEX_FMT =
    '%0:s and a hexadecimal number (%0:sFF00FF00)';
  SF_DESIGNER_FORMA_INSERTA_FMT =
    'one of those names without the %s it inserts%s';
  SF_DESIGNER_FORMA_INSERTA_EJEMPLO_FMT =
    ' (%s for %s)';
  SF_DESIGNER_TOMA_CADENA =
    'a string (quoted as the file writes it, or without quotes: set adds them)';
  SF_DESIGNER_TOMA_COMPONENTE =
    'the Name of a component of this form, or nil to clear it';
  SF_DESIGNER_TOMA_SUBPROPIEDADES =
    'no value of its own: it is an object the component keeps, set its ' +
    'sub-properties one by one (Font.Size)';
  SF_DESIGNER_TOMA_NUMERO_QUE_CABE =
    'a number its type holds (a Single up to 3.4E38, a Double up to 1.7E308)';

  SR_DESIGNER_SET_PARENT_SOLO =
    '[DSGN-094 INVALID_PARAM] parent moves the component and goes alone, ' +
    'without prop or value: change a property with another call.';

  SR_DESIGNER_NOMBRE_INVALIDO_FMT =
    '[DSGN-095 INVALID_PARAM] "%s" is not a valid component name: an ' +
    'identifier (letters, digits and _, not starting with a digit, not a ' +
    'reserved word).';

  SR_DESIGNER_NOMBRE_SIN_BOM_FMT =
    '[DSGN-111 DENIED] The name %s has letters outside ASCII and %s is not ' +
    'UTF-8 with BOM: %s. A file''s encoding is not changed on the way: save ' +
    'it as UTF-8 (with BOM) in the IDE first, or use an ASCII name. Nothing ' +
    'was written.';
  SF_DESIGNER_SIN_BOM_FORM =
    'the IDE, the build and the renderer read a form without BOM as ANSI, ' +
    'where no such letter can be part of a name';
  SF_DESIGNER_SIN_BOM_UNIDAD =
    'the compiler reads a unit without BOM as ANSI, and the field would get ' +
    'another name than its component';

  SR_DESIGNER_NOMBRE_OCUPADO_FMT =
    '[DSGN-096 INVALID_PARAM] The name %s is taken by %s. Nothing was ' +
    'written.';
  SF_DESIGNER_OCUPA_COMPONENTE =
    'another component of the form';
  SF_DESIGNER_OCUPA_CLASE =
    'the form''s class';
  SF_DESIGNER_OCUPA_CAMPO_FMT =
    'a field of %s';
  SF_DESIGNER_OCUPA_METODO_FMT =
    'a method of %s';
  SF_DESIGNER_OCUPA_PROPIEDAD_FMT =
    'a property of %s';
  // un componente que el form HEREDA (su .dfm no lo repite si no cambia): el
  // form saltaba EComponentError al crearse (3.2 de la 1.18.0)
  SF_DESIGNER_OCUPA_HEREDADO_FMT =
    'a component the form inherits from %s';

  SR_DESIGNER_PADRE_CICLO_FMT =
    '[DSGN-097 INVALID_PARAM] %s cannot go inside %s: that is itself or one ' +
    'of its own children.';

  SR_DESIGNER_REFERENCIA_NO_ESTA_FMT =
    '[DSGN-098 INVALID_PARAM] There is no component %s in %s for %s.%s to ' +
    'point at. Nothing was written. One inside an inline frame goes as ' +
    'Frame1.Name, and one of another form as Form2.Name: those are written ' +
    'as given (the form loader resolves them, set does not read the other ' +
    'file).';

  SR_DESIGNER_REFERENCIA_TIPO_FMT =
    '[DSGN-107 INVALID_PARAM] %s is a %s, and %s.%s takes a %s or a ' +
    'descendant of it (%s). Nothing was written.';
  SF_DESIGNER_CABEN_FMT =
    'in this form: %s';
  SF_DESIGNER_NO_CABE_NINGUNO =
    'none in this form';

  SR_DESIGNER_CAMPO_COMPARTIDO_FMT =
    '[DSGN-099 INVALID_PARAM] The field of %s shares a declaration with ' +
    'others across lines (%s): write it on a line of its own (Button1: ' +
    'TButton;) and repeat. Nothing was written.';

  SR_DESIGNER_CAMPO_LINEA_SUCIA_FMT =
    '[DSGN-108 INVALID_PARAM] The field of %s shares its line with a ' +
    'directive or with a comment that goes on past it (%s): taking the line ' +
    'away would leave the other half behind. Move the field to a line of its ' +
    'own and repeat. Nothing was written.';

  SN_DESIGNER_NADA_QUE_QUITAR_FMT =
    '[DSGN-112] %s.%s is not written in the form (the IDE writes no line for ' +
    'a reference that is nil): nothing was changed.';

  SN_DESIGNER_CONSTANTE_ABIERTA_FMT =
    '[DSGN-110] "%s" is not one of the names %s registers, and what else its ' +
    'reader takes could not be read from its source: it was written as ' +
    'given.%s A value its reader does not take keeps the form from opening: ' +
    'check it, or set it again.';

  SR_DESIGNER_SET_LISTA_FMT =
    '[DSGN-109 INVALID_PARAM] %s.%s is a %s, a list of strings: the form ' +
    'writes it as %s.Strings = ( ... ), which set does not write. Edit those ' +
    'lines with delphi_edit (command=get shows them). Nothing was written.';

  SN_DESIGNER_INSERT_NOTE =
    '[DSGN-100] Inserted with the minimum the IDE writes: position, its Name ' +
    'as text when the class shows one, TabOrder; its size is the class''s ' +
    'own (its constructor). It lands at 10,10 even when something is ' +
    'already there: place it with set Left/Top (Position.X/Position.Y in ' +
    'FMX). Change a property with command=set, move it with set parent=, ' +
    'see it with command=preview.';

  SN_DESIGNER_YA_ESTA_FMT =
    '[DSGN-101] %s is already inside %s: nothing to move.';

  SN_DESIGNER_DELETE_NOTE =
    '[DSGN-102] Deleted with everything inside it, the references to it in ' +
    'the form, its field and its empty handlers; handlersKept are used by ' +
    'something else and were not touched. usesInCode are lines of the unit ' +
    'that still name a deleted component: the compiler stops there (E2003) - ' +
    'fix them with delphi_edit.';

  SN_DESIGNER_RENAME_NOTE =
    '[DSGN-103] Renamed in the form - every line of it that names the ' +
    'component included - and in its field. Its methods keep their names, as ' +
    'in the IDE (methodsWithOldName); usesInCode are lines of the unit that ' +
    'still use the old name and will not compile until changed (delphi_edit).';

  SN_DESIGNER_IMPACTO_SIN_CLASE_FMT =
    '[DSGN-104] The class %s is not in %s: its code was not looked at.';

  SR_DESIGNER_SET_PROP_FMT =
    '[DSGN-105 INVALID_PARAM] "%s" is not a valid property name: an ' +
    'identifier, dotted for a sub-property (Font.Size, Position.X).';

  SN_DESIGNER_YA_SE_LLAMA_FMT =
    '[DSGN-106] The component is already called %s: nothing to rename.';

  SF_DESIGNER_SOBRECARGADO =
    'overloaded: several methods carry this name';
  SF_DESIGNER_LO_ATA_FMT =
    'bound by %s';
  SF_DESIGNER_LO_USA_FMT =
    'used at %s';
  SF_DESIGNER_COMPARTE_LINEAS =
    'its implementation shares lines with other code: left in place';
  SF_DESIGNER_USOS_MAS_FMT =
    '... and %d more lines';
  SF_DESIGNER_USES_EN_IMPL_FMT =
    '%s is in the implementation uses of %s, and the field in the interface ' +
    'needs it there: move it (delphi_edit removeuses, then adduses ' +
    'section=interface)';
  SF_DESIGNER_SIN_CAMPO_FMT =
    '%s had no published field in %s (command=check-binding says what else ' +
    'is missing)';

  SF_DESIGNER_RENDER_SIN_RESPUESTA_FMT =
    'exit code %d and no answer (%s)';

  SR_DESIGNER_FRAMEWORK =
    '[DSGN-002 INVALID_PARAM] framework must be vcl or fmx.';

  SR_DESIGNER_NEED_CLASS =
    '[DSGN-003 INVALID_PARAM] "classname" is missing (the class of the component, ' +
    'e.g. TButton).';

  SR_DESIGNER_NEED_PROP =
    '[DSGN-004 INVALID_PARAM] "prop" is missing (the property, e.g. Align).';

  SR_DESIGNER_NEED_PATH =
    '[DSGN-005 INVALID_PARAM] "path" is missing (the .dfm or .fmx).';

  SR_DESIGNER_NEED_COMPONENT =
    '[DSGN-006 INVALID_PARAM] "component" is missing (the Name of the component ' +
    'in the form).';

  SR_DESIGNER_NOT_FORM =
    '[DSGN-007 INVALID_PARAM] That is not a designer (.dfm/.fmx).';

  SR_DESIGNER_ILEGIBLE_FMT =
    '[DSGN-041 DENIED] %s cannot be read as a form: %s. A binary .dfm is ' +
    'converted with delphi_designer command=to-text; a damaged one has ' +
    'its last good copy in the __delphi-patch trash next to it.';

  { Un .dfm BINARIO ya se lee al vuelo (Lsp.DesignerBin, la conversion del
    propio IDE); solo uno danado sigue rechazado. Textos del 24-sep-2026,
    tras el reporte de Hermes (un form legacy dejaba ciego al agente). }
  SN_DESIGNER_BINARY_VIEW =
    '[DSGN-009] BINARY DFM on disk, read on the fly as text (what the ' +
    'IDE shows in "View as Text"): what you see is faithful. To EDIT it, ' +
    'convert it to text with command=to-text (backup first) and from ' +
    'there it is edited like any .dfm; command=to-binary is the way back.';
  SN_DESIGNER_TOTEXT_FMT =
    '[DSGN-010] CONVERTED %s to TEXT: %d binary bytes -> %d lines, the ' +
    'same conversion the IDE does. Backup: %s. The IDE opens it just the ' +
    'same and on saving keeps the format it finds; from now on it is ' +
    'read, searched and edited like any .dfm.';
  SN_DESIGNER_TOBINARY_FMT =
    '[DSGN-011] CONVERTED %s to BINARY: %d bytes, with the resource ' +
    'wrapper the IDE writes. Backup: %s. From here on it is read on the ' +
    'fly, but it is not edited until it is converted back to text.';
  SN_DESIGNER_ALREADY_FMT =
    '[DSGN-012] %s is already %s: nothing to do.';
  SR_DESIGNER_FMX_ALWAYS_TEXT =
    '[DSGN-013 DENIED] A .fmx is always text (FireMonkey has no binary ' +
    'format): to-text and to-binary are only for .dfm.';
  SN_READ_BINARY_DESIGNER =
    '[READ-004] BINARY DFM on disk, shown as text (the IDE''s own ' +
    'conversion, "View as Text"). What you read is faithful, but it is ' +
    'NOT edited this way: delphi_designer command=to-text converts it to ' +
    'text on disk (backup first) and from there it is edited like any ' +
    '.dfm.';
  { Lo que no vuelve igual por su codificacion se dice al LEERLO (la regla de
    ida y vuelta de los escritores, David 9-oct-2026): se leia callado, o
    reventaba con un SYS-006. %s = la codificacion. }
  SN_READ_BYTES_NO_VUELVEN_FMT =
    '[READ-007] NOTE: some bytes of this file do not fit its encoding (%s) ' +
    '- a mixed or damaged file. They are shown as U+FFFD, and delphi_edit, ' +
    'delphi_textedit and the other writers refuse to write it back ' +
    '(EDIT-038): fix it in its editor (the IDE for a source), or restore ' +
    'a good copy.';
  { ...con la primera linea que no cuadra y, en un UTF-8, como seria leida
    en la otra codificacion posible: el agente ve las dos (David,
    9-oct-2026). %s = la linea citada (CitaDeLinea); en la segunda, %s = esa
    codificacion y %s = la linea. }
  SF_READ_PRIMERA_NO_CUADRA_FMT =
    'The first line that does not fit: %s';
  SF_READ_OTRA_LECTURA_FMT =
    'Read as %s, that line would be: %s';
  { Un FUENTE en UTF-8 sin BOM con acentos (regla 5 de la 1.18.0, David
    9-oct-2026): se lee y se escribe como UTF-8, que es lo que son sus bytes
    y lo que ensena el editor del IDE (medido), pero dcc lo compila como ANSI
    (medido: mojibake en el exe) salvo con DCC_CodePage=65001 (medido). La
    salida es la del IDE: guardarlo le pone el BOM (medido). %s = la pagina
    ANSI de la maquina (EncName). }
  SN_READ_UTF8_SIN_BOM_FMT =
    '[READ-008] NOTE: this source is UTF-8 WITHOUT a BOM. The IDE shows its ' +
    'accents right, but the compiler reads a source without BOM as ANSI ' +
    '(%s) - unless its project sets DCC_CodePage=65001 - so its accented ' +
    'string literals and names reach the program as mojibake (accents in ' +
    'comments do no harm). The way out is the IDE''s: open it and save it, ' +
    'and the IDE writes it as UTF-8 with a BOM, which the compiler reads ' +
    'right. This server keeps the file as it is (its bytes are UTF-8).';

  SR_DESIGNER_EMPTY =
    '[DSGN-014 DENIED] The file contains no object.';

  SR_DESIGNER_CLASS_FMT =
    '[DSGN-015 NOT_FOUND] The class "%s" is not in the %s table of this ' +
    'Delphi (it is not a persistent class of the source its library and ' +
    'browsing paths reach: a typo, a class of the other framework, or a ' +
    'component whose source is not installed). delphi_components lists the ' +
    'installed packages.';

  SR_DESIGNER_PROP_FMT =
    '[DSGN-016 NOT_FOUND] %s is not a published property of %s. ' +
    'command=info lists them all.';

  SR_DESIGNER_COMPONENT_FMT =
    '[DSGN-017 NOT_FOUND] There is no component "%s" in that form ' +
    '(command=tree lists them).';

  SN_DESIGNER_INFO_NOTE =
    '[DSGN-018] Published properties read from the source of the active ' +
    'Delphi (inherited included), and in definedByCode what the class streams ' +
    'by code (its DefineProperties: written to the form without being ' +
    'published). A property absent from both does NOT stream in a .dfm/.fmx: ' +
    'do not write it - unless definedByCode has "*" (names built at run ' +
    'time, which the source does not tell).';

  { Una clase que no publica nada y tiene descendientes: la de una propiedad
    cuya instancia elige el codigo (revision de la 1.12.0). }
  SN_DESIGNER_INFO_FAMILIA_FMT =
    '[DSGN-057] %s publishes nothing itself: a property of this type holds a ' +
    'DESCENDANT chosen by code (TLabel.TextSettings holds a ' +
    'TLabelTextSettings). descendantsPublish lists what its descendants ' +
    'publish; which one a given property holds is not in the source.';

  { Las tablas del disenador salen del FUENTE de cada Delphi
    (Lsp.DesignerMetaGen). Sin fuente no hay tabla, y no se valida con la de
    otro Delphi: "no esta" dejaria de querer decir "no existe". }
  SR_DESIGNER_SIN_FUENTE_FMT =
    '[DSGN-050 INTERNAL] No designer table for %s: this installation has no ' +
    'Delphi source to read the published properties from (no System.pas in ' +
    'the IDE''s library or browsing paths). The server does not check a ' +
    'form against the table of another Delphi. Install the source with the ' +
    'RAD Studio installer, or check the form in the IDE.';

  { La primera vez tras instalar, actualizar o tocar las rutas del IDE la
    tabla se genera del fuente (segundos); quien llama espera un rato y, si
    no ha acabado, se le dice que vuelva. }
  SR_DESIGNER_GENERANDOSE_FMT =
    '[DSGN-051 DENIED] The designer table of %s is still being generated ' +
    'from its source (the first use after an install, an update or a change ' +
    'of the library paths). Try the same call again in a minute.';

  { Un fallo del generador no se repite en cada llamada: se recuerda un rato
    (Lsp.DesignerMetaGen) y se dice con su motivo. }
  SR_DESIGNER_TABLA_FALLO_FMT =
    '[DSGN-053 INTERNAL] The designer table of %s could not be generated from ' +
    'its source: %s. The server log has it; it is tried again in %d minutes ' +
    'or as soon as the source in the library paths changes.';

  { Ni MetaTable ni el lint tumban nada (revision de la 1.12.0): una
    excepcion (la tabla purgada por otro proceso entre mirarla y leerla...)
    se dice como lo que es, no como un fallo de la herramienta. }
  SR_DESIGNER_TABLA_ERROR_FMT =
    '[DSGN-054 INTERNAL] The designer table could not be used: %s';

  { El lint que va detras de cada edicion de un .dfm/.fmx no espera a la
    tabla: dice que no valido, y por que - con la edicion YA escrita, asi que
    nunca "vuelve a llamar" (un agente lo leia como repetir la edicion:
    revision de la 1.12.0). Las razones van en SF_DSGN_RAZON_*. }
  SN_DESIGNER_LINT_SIN_TABLA_FMT =
    '[DSGN-052] NOTE: the properties of this form were NOT checked against ' +
    'the framework: %s. The edit itself is done: do not repeat it.';
  SF_DSGN_RAZON_SIN_FUENTE_FMT =
    '%s has no Delphi source to read them from';
  SF_DSGN_RAZON_GENERANDOSE_FMT =
    'the table of %s is still being generated from its source (delphi_designer ' +
    'command=lint checks this form once it is ready)';
  SF_DSGN_RAZON_FALLO_FMT =
    'the table of %s could not be generated (%s)';
  SF_DSGN_RAZON_ERROR_FMT =
    'the check itself failed (%s)';

  SL_DESIGNER_TABLAS_GENERADAS_FMT =
    'Designer tables of %s (build %s) generated from its source: %d units ' +
    'read in %d ms; VCL %d facts, FMX %d facts.';
  SL_DESIGNER_TABLAS_FALLO_FMT =
    SL_MARCA_AVISO +
    ': the designer tables of %s could not be generated: %s';

  { Un filtro que no casa con nada devolvia properties:[] y total:0 sin mas,
    y un agente pequeno lo leia como un fallo de RTTI (Hermes, 28-sep-2026:
    TLabel FMX con filter=Font; la fuente va en TextSettings). }
  SN_DESIGNER_INFO_FILTRO_VACIO_FMT =
    '[DSGN-048] No published property or event of %s contains "%s" (it ' +
    'publishes %d; the filter is a substring of the name, case-insensitive). ' +
    'Not an RTTI failure: the class simply has no such member.';

  { La coda solo cuando toca: FMX y un filtro que busca la fuente (salia en
    cualquier clase y framework; undecima revision, r11b) }
  SF_DESIGNER_FUENTE_FMX =
    ' An FMX text control keeps its font in TextSettings, not in Font.';

  SN_DESIGNER_INFO_TRUNCATED =
    '[DSGN-042] The list is truncated: filter=<text> narrows it to the ' +
    'properties whose name contains it.';

  SN_DESIGNER_TREE_NOTE =
    '[DSGN-019] Component tree of the TEXT designer. get shows one ' +
    'component; lint checks classes, properties and enum values against ' +
    'the framework tables.';

  SN_DESIGNER_TREE_MAXDEPTH_FMT =
    '[DSGN-059] Cut at level %d: %d objects show only their childrenCount. ' +
    'Raise maxdepth, or ask for one of them with command=get component=<name>.';

  SN_DESIGNER_LINT_OK_FMT =
    '[DSGN-020] LINT CLEAN: %s has no unknown classes, unpublished ' +
    'properties or invalid enum values, and if it has a paired .pas it ' +
    'matches its class (check-binding: every event points to a declared, ' +
    'published method).';

  SN_DESIGNER_LINT_BAD_FMT =
    '[DSGN-038] %d designer warnings in %s (unpublished ' +
    'property or nonexistent enum value, or the .dfm does not match its ' +
    'class: event to a nonexistent or NOT published method, object ' +
    'without a field, repeated name):';

  SN_DESIGNER_BINDING_LINT_HEADER =
    '[DSGN-021] *** DESIGNER WARNING: the form does NOT match its class ' +
    '(check-binding). The build passes, because the compiler does not ' +
    'look at this, and the app dies when LOADING the form: an event ' +
    'wired to a method that is not published does not resolve ("Invalid ' +
    'property value" / EReadError). Fix it before deploying: ***';

  SN_PATCH_INSERT_PUBLISHED_BY_EVENT_FMT =
    '[EDIT-031] published section chosen by the tool: the paired ' +
    'designer %s wires ''%s'' as an event, and streaming only resolves ' +
    'published methods';

  // ---- delphi_git: ramas ----

  SR_BUILD_INCLUDE_OUTSIDE_FMT =
    '[BUILD-028 DENIED] I will not build this. The %s directive of %s ' +
    'brings into the build a file that is OUTSIDE what this server lets ' +
    'you read. The compiler opens it with the server''s permissions, and ' +
    'what goes in comes back out in two places: inside the binary (which ' +
    'is then downloaded) and quoted word for word in the errors when the ' +
    'file is not Pascal. The paths of {$I} and {$R} have to stay inside ' +
    'the workspace.';

  SR_BUILD_OUTPUT_DENIED_FMT =
    '[BUILD-029 DENIED] I will not build this. The project puts its ' +
    'output in %s = %s, and this session cannot write there: %s. A build ' +
    'writes the binary, the .dcu files and the rest into the output ' +
    'folders of the project (and a Clean deletes there): they have to ' +
    'stay inside the workspace. delphi_config set-output places the ' +
    'binary and .dcu ones inside.';

  SR_BUILD_OUTPUT_UNDECLARED_FMT =
    '[BUILD-030 DENIED] I will not build this. The project does not ' +
    'declare %s for this platform and config (neither in the global one ' +
    'nor in the specific one), and without it the IDE puts that output ' +
    'outside the project: the .dcu files next to each source (also those ' +
    'of a reference), the .bpl, .dcp and .hpp in their global folders. ' +
    'Declare it inside the project, for example .\$(Platform)\$(Config) ' +
    'as delphi_create does (delphi_config set-output sets the binary one ' +
    'and the .dcu one).';

  SR_BUILD_OUTPUT_UNRESOLVED_FMT =
    '[BUILD-031 DENIED] I will not build this. I do not know where the ' +
    'output of %s = %s goes (a macro or an escape that this server does ' +
    'not resolve), and an output folder that cannot be checked is not ' +
    'approved. Write it as a path relative to the project, with ' +
    '$(Platform) and $(Config) if needed.';

  SN_BUILD_LOCKED_OUTPUT =
    '[BUILD-032] F2039 "Could not create output file" is almost never a ' +
    'fault in your code: the binary this build wants to write is OPEN. ' +
    'It is usually the previous run still alive, the IDE with the ' +
    'project open, or an attached debugger. Wait for whatever is running ' +
    'to finish and repeat; if it was delphi_test that left it hanging, ' +
    'it has a timeout and gets killed on its own. I do NOT kill ' +
    'processes on this machine: someone may be working with the IDE on ' +
    'the other side. (I already retried several times for a few seconds ' +
    'before answering you: whatever holds it open is not a momentary ' +
    'thing.)';

  // PKG-002 (el zip que no se pudo colocar) retirado el 9-oct-2026: lo
  // coloca ColocaProducto (Lsp.Patch), que dice la causa por la regla de
  // todas (MotivoDelSistema) o la negativa de la puerta

  // El otro lado de lo mismo: reintento y SALIO. Un build que de pronto tarda
  // cinco segundos de mas sin explicacion invita a pensar que algo va mal.
  SN_BUILD_LOCKED_RETRY =
    '[BUILD-033] The binary was in use (F2039) when I started - ' +
    'typically a delphi_test run still alive - so I repeated the build ' +
    'until it was free. The result is good; it just took longer.';

  // ---- delphi_config view: SDK y perfil por plataforma remota ----
  SN_CONFIG_REMOTE_NOTE =
    '[CFG-059] sdk/profile per remote platform and where they come from. ' +
    'sdkSource: project (the .dproj sets it) | ide-default (the active ' +
    'SDK of the SDK Manager; set it with delphi_config command=set-sdk) ' +
    '| none (there is no SDK: delphi_paserver command=get-sdk and then ' +
    'set-sdk). profileSource: project | none (the project does not set ' +
    'PAServer: delphi_build target=Deploy takes it from profile=, or set ' +
    'it with command=set-profile). Android takes no profile: it deploys ' +
    'through delphi_adb.';

  SN_BUILD_DEVLINK_DONE_FMT =
    '[BUILD-034] The linker asked for a DEVELOPMENT name (libX.so) that ' +
    'the sysroot did not have, because the machine it was downloaded ' +
    'from does not have the -dev package; the library itself is there ' +
    '(libX.so.N). I completed it in the SDK with a copy -%s- and ' +
    'repeated the build. Nothing to install on the target.';
  SN_BUILD_DEVLINK_MISSING_FMT =
    '[BUILD-035] The linker cannot find %s and the sysroot has NO ' +
    'version of that library: the target machine is missing the whole ' +
    'package. Install the library there (with its -dev) and repeat ' +
    'delphi_paserver get-sdk; or remove that dependency from the project.';
  SN_BUILD_DEVLINK_DENIED_FMT =
    '[BUILD-047] The linker cannot find a development name that the ' +
    'sysroot COULD give - its libX.so.N is there -, but the server did not ' +
    'write it: %s. Nothing to install on the target: a library folder of ' +
    'the .sdk that is not inside a sysroot the IDE has registered is not ' +
    'the server''s to write (delphi_paserver reseat-sdk registers an SDK ' +
    'already on disk); the reason says why.';

  SR_PASERVER_IDE_OPEN =
    '[PAS-029 DENIED] The IDE (bds.exe) is OPEN on the server and ' +
    'paclient cannot save profiles meanwhile (it warns W0013 but exits ' +
    'with exit 0 and saves NOTHING). The profile has NOT been created. ' +
    'Retry when the operator closes the IDE, or ask them to create the ' +
    'profile from the IDE itself. I do NOT close the IDE: someone may be ' +
    'working with it.';

  SR_PASERVER_SDK_NOGROUP_FMT =
    '[PAS-030 DENIED] The target sysroot of "%s" does not match any ' +
    'distribution I know. I tried the gcc trees (%s) and the library ' +
    'folders (%s) and no variant delivered files. Send a delphi_report ' +
    'with your distro''s triplet (ls /usr/lib/gcc/) and we will add it.';

  SN_BUILD_QUEUED =
    '[BUILD-037] This build waited its turn: the server builds ONE AT A ' +
    'TIME because two simultaneous msbuild runs trample each other''s ' +
    '.dcu files, outputs and .deployproj. "queuedMs" is what you waited ' +
    'in the queue, not what the compiler took.';

  SN_BUILD_FIRST_ERROR =
    '[BUILD-038] Start with "firstError": one error can breed the others ' +
    '(an E2009 brings seven E2250 that look like a threading problem). ' +
    'Fix it and compile again before touching anything else.';

  { %s: el fichero; %d: cuantos objetos no se comprobaron. Va delante de las
    notas DSGN-039/055, en el lint y tras una edicion: no son avisos (iban
    bajo "the app CRASHES" y contaban como avisos; revision de la 1.12.0) }
  SN_DESIGNER_LINT_NOTAS_FMT =
    '[DSGN-058] Not checked in %s: %d object(s) whose class is not in ' +
    'this server''s table or is ambiguous - not an error in itself, but ' +
    'nothing inside them was checked; everything else was:';

  SN_LINT_UNKNOWN_CLASS_FMT =
    '[DSGN-039] "%s" is not in this server''s %s table (it comes from a ' +
    'third-party package, or it does not exist). That is not an error in ' +
    'itself, but I have NOT checked any property of that object or of ' +
    'anything inside it.';

  { Dos unidades declaran una clase persistente con el mismo nombre y otras
    propiedades publicadas (con las tablas leidas de las rutas de biblioteca,
    los forms de demo se llaman TForm1...): el form no dice de cual es, y no
    se juzga (revision de la 1.12.0). }
  SN_LINT_CLASE_AMBIGUA_FMT =
    '[DSGN-055] "%s" is declared by more than one unit of this server''s %s ' +
    'table, with different published properties (%s): the form does not say ' +
    'which one it is, so I have NOT checked any property of that object or ' +
    'of anything inside it.';
  SR_DESIGNER_CLASE_AMBIGUA_FMT =
    '[DSGN-056 NOT_FOUND] "%s" is declared by more than one unit of the %s ' +
    'table, with different published properties (%s): which one a form means ' +
    'depends on the uses of its unit, so this table does not answer for it.';

  SP_DESIGNER_UNIT =
    'check-binding, optional: the .pas with the form''s class. By ' +
    'default, the one with the same name as the .dfm.';

  SR_DESIGNER_NO_FORM_FMT =
    '[DSGN-022 NOT_FOUND] The form file %s does not exist.';

  SR_DESIGNER_NO_UNIT_FMT =
    '[DSGN-023 NOT_FOUND] I cannot find the form''s unit (%s). If it has a ' +
    'different name, pass it in "unit".';

  SN_DESIGNER_LAYOUT_OK =
    '[DSGN-024] The geometry CHECKS OUT: nothing has zero size, nothing ' +
    'sticks out of its container, nothing overlaps and every aligned ' +
    'control has room left. That is what cannot be seen from here: a ' +
    'form can bind perfectly and still be a pile of controls stacked on ' +
    'top of each other.';

  SN_DESIGNER_LAYOUT_BAD =
    '[DSGN-025] NOTE: this LOADS but does not look the way you think. ' +
    'None of what follows is reported by the compiler or the linker: a ' +
    'zero-size control is there and cannot be seen, one that sticks out ' +
    'of its container shows up clipped, and when two overlap the top one ' +
    'hides the one below. Fix it before calling the form done.';

  SN_DESIGNER_LAYOUT_HOW =
    '[DSGN-026] How I measure it: I resolve Align like ' +
    'TWinControl.AlignControls (each aligned control takes its band from ' +
    'the space that is left, in .dfm order), with one key detail: ' +
    'alClient does NOT shrink the rectangle, so two alClient controls ' +
    'get the WHOLE space and cover each other 100%. I apply the class''s ' +
    'default Align when the .dfm does not write it (TStatusBar=alBottom, ' +
    'TToolBar=alTop, TSplitter=alLeft, TTabSheet=alClient...). I skip ' +
    'what is invisible (Visible= False), I do not judge the children of ' +
    'a TGridPanel (they go by cells), I do not treat a ' +
    'TBevel/TShape/TImage as covering anything (it is decoration), and a ' +
    'TScrollBox may have larger content on purpose. In "boxes" you get ' +
    'the resolved rectangle of each control in form coordinates: that is ' +
    'where each thing ends up, so you can place the next one without ' +
    'seeing the screen. It is approximate: I take a container''s usable ' +
    'area as its Width/Height, and Anchors (which govern RESIZING) is ' +
    'not what I measure.';

  SN_COMPLETION_SNAPPED_FMT =
    '[LSP-027] I moved the position from column %d to column %d: you ' +
    'asked for member completion (trigger ".") but the column fell on ' +
    'the identifier, not AFTER the dot. "after Foo." is the column of ' +
    'the dot + 1; on the name, the LSP returns the whole global scope. ' +
    'These are the members of the type.';

  SR_DESIGNER_LAYOUT_FMX =
    '[DSGN-027 DENIED] command=layout is only for .dfm (VCL). A .fmx ' +
    'lays out with another model (Size.Width, Position.X, a different ' +
    'Align) that this server does not resolve yet; answering clean:true on a ' +
    '.fmx would be a lie. For .fmx use tree/get/lint for now.';

  SN_DESIGNER_LAYOUT_TRUNC =
    '[DSGN-040] NOTE: the .dfm looks TRUNCATED (there are more open ' +
    'objects than "end" lines closing them). What I tell you about the ' +
    'geometry may be incomplete: check that the file ends with the ' +
    'form''s "end".';

  SN_DESIGNER_LAYOUT_ESTIMATED =
    '[DSGN-028] NOTE: the form has no ClientWidth/ClientHeight, only ' +
    'Width/Height (the size of the WINDOW). I subtracted a nominal frame ' +
    'at 96 dpi to estimate the usable area; near the right or bottom ' +
    'edge the real clipping may vary by a few pixels depending on the ' +
    'BorderStyle.';

  SR_DESIGNER_BINDING_NOT_FORM =
    '[DSGN-029 INVALID_PARAM] check-binding compares a FORM with its class, so ' +
    '"path" must be the .dfm/.fmx. The unit goes in "unit" (and if it ' +
    'has the same name as the form, you do not need to pass it).';

  SR_DESIGNER_BINDING_UNIT_EXT =
    '[DSGN-030 INVALID_PARAM] "unit" must be a .pas. This tool reads the form''s ' +
    'class, not just any text file.';

  SR_DESIGNER_BINDING_NO_ROOT =
    '[DSGN-031 DENIED] This file does not start with a designer object ' +
    '("object <Name>: <TClass>"), so it is not a form I can compare.';

  SN_DESIGNER_BINDING_NOCLASS_FMT =
    '[DSGN-032] NOTE: the .dfm says this form is of class %s, but that ' +
    'class is NOT declared in %s. Either the .dfm points to another ' +
    'unit, or the class was renamed in only one place. I compare nothing ' +
    'else until that matches: it would mean making up the result.';

  SN_DESIGNER_BINDING_PARTIAL_FMT =
    '[DSGN-033] PARTIAL: the inheritance goes outside this unit (%s), so ' +
    'I cannot see the inherited components and methods from here. ' +
    'Anything I called EXTRA or MISSING would be false, so I do not list ' +
    'it; if you get clean:true, read it as "I found nothing wrong in what I ' +
    'CAN see". To check the inherited part, run check-binding on the ' +
    'parent form too.';

  SN_DESIGNER_BINDING_OK =
    '[DSGN-034] The form and its class MATCH: every object in the .dfm ' +
    'has its published field, every event points to a method that ' +
    'exists, and there is no extra field. That is what the compiler does ' +
    'NOT check: a mismatch here compiles just the same and blows up when ' +
    'the window is created.';

  SN_DESIGNER_BINDING_BAD =
    '[DSGN-035] NOTE: the .dfm and the class do NOT match. This compiles ' +
    'anyway and fails when the form is CREATED, at run time, with a ' +
    'message that does not point here. An object without a published ' +
    'field ends up nil; an event whose method does not exist makes the ' +
    'form fail to load. Fix the three lists before calling anything done.';

  SN_DESIGNER_SET_NOTE =
    '[DSGN-036] It is a SET: in the .dfm/.fmx it is written in square ' +
    'brackets, comma-separated, [goEditing, goTabs], and empty is [].';

  SR_PACKAGE_NEED_DIR =
    '[PKG-001 INVALID_PARAM] delphi_package needs "dir" (the folder to ' +
    'compress).';

  SR_PACKAGE_OUTFILE_ZIP_FMT =
    '[PKG-003 INVALID_PARAM] outfile must end in .zip (%s): the package ' +
    'is a zip, and an existing .zip there is replaced. Nothing was ' +
    'written.';

  SR_PACKAGE_RAIZ_SIN_OUTFILE_FMT =
    '[PKG-004 INVALID_PARAM] "dir" is the root of a drive (%s) and no ' +
    '"outfile" was given: the default zip goes NEXT to the folder, and a ' +
    'drive has nothing next to it. Pass "outfile" (a .zip inside your ' +
    'roots). Nothing was written.';

  SP_FETCH_MAXBYTES =
    'NOTE: maxbytes<=1048576 (1 MB) FORCES inline base64 chunks - the ' +
    'opposite of what you want with a large file. For a large download ' +
    'OMIT it: above 1 MB the answer carries the download LINK and no ' +
    'inline chunk ("inline":false, "bytes":0), the cheap way. maxbytes ' +
    'only sets the chunk size (max 8388608) when the content goes inline.';

  SR_STYLES_VALUE_GRAMMAR_FMT =
    '[STYLE-019 INVALID_PARAM] "%s" is not a value a .style can hold. A style ' +
    'file is a text DFM: a number (12, -3.5), a hexadecimal color ' +
    '($FF2A2A2A), an identifier (claRed, True, TAlignLayout.Top), text ' +
    'in single quotes (''OK'') or a set ([a, b]). If I write it as is, the ' +
    'file can no longer be read and you would only find out at ' +
    'command=build.';

  SR_STYLES_RENAME_EMPTY =
    '[STYLE-020 INVALID_PARAM] Empty StyleName. A style with no name cannot be ' +
    'found by anyone.';

  SR_STYLES_RENAME_DUP_FMT =
    '[STYLE-021 DENIED] That file already has a style named "%s". Two ' +
    'styles with the same StyleName is exactly what lint catches, and ' +
    'from then on delete/get work on the first one they find. Choose ' +
    'another name.';

  SN_STYLES_RENAMED_FMT =
    '[STYLE-022] RENAMED the style "%s" to "%s" in %s. NOTE: the ' +
    'StyleLookup entries in your .fmx files that pointed to the old name ' +
    'no longer find anything; run command=lint to see which ones.';

  SN_CONFIG_PLAT_ALREADY_FMT =
    '[CFG-060] The platform %s was ALREADY disabled: I did not touch ' +
    'anything (not even a backup, which would be of an identical file). ' +
    'add-platform re-enables it.';

  SR_CONFIG_PLAT_LAST_FMT =
    '[CFG-061 DENIED] %s is the LAST enabled platform of the project, ' +
    'and a project with none cannot be compiled from the IDE. First ' +
    'enable another one with add-platform, then remove this one.';

  SR_CONFIG_OUTPUT_INVALID =
    '[CFG-062 INVALID_PARAM] That is not valid as an output folder. It must be ' +
    'a simple RELATIVE name, like Compiled or bin\out: no drive or ' +
    'absolute path, no ".." and no special characters (spaces are ' +
    'allowed). output=default restores the standard RAD Studio layout.';

  SN_CONFIG_DPR_ONLY =
    '[CFG-063] This is the .dpr and there is no .dproj next to it, so I ' +
    'can only tell you its UNITS. The framework (VCL/FMX), the ' +
    'platforms, the configurations, the search paths and the deployment ' +
    'live in the .dproj: I do not know them, and I do not make them up. ' +
    'add-unit and remove-unit do work here; the other commands need a ' +
    '.dproj.';

  { Un .groupproj en delphi_config: view contestaba como si fuera un proyecto
    vacio, y una orden de escritura lo habria tocado como un .dproj
    (26-sep-2026). }
  SN_CONFIG_GROUP_VIEW_FMT =
    '[CFG-064] This is a project GROUP (.groupproj), not a project: it ' +
    'has no platforms or configurations of its own. It lists %d ' +
    'projects; %d are not where it says (fix-references looks for them). ' +
    'To configure one, pass ITS .dproj in "project"; add-project and ' +
    'remove-project change the list.';
  SR_CONFIG_GROUP_FMT =
    '[CFG-065 INVALID_PARAM] %s is a project GROUP, not a project, and ' +
    '"%s" is not valid on a group: view, add-project, remove-project and ' +
    'fix-references are; for anything else, pass the project''s .dproj. I ' +
    'did not touch anything.';
  { Un grupo que no se deja leer es un fallo de ESTE lado (Error: -> INTERNAL),
    no una llamada mal hecha. }
  SR_CONFIG_GROUP_READ_FMT =
    '[CFG-066 INTERNAL] Could not read the group %s: %s';
  SR_CONFIG_NOT_PROJECT_FMT =
    '[CFG-067 INVALID_PARAM] %s is not a project: delphi_config reads ' +
    'and changes a .dproj (or its .dpr/.dpk), and view also lists a ' +
    'group (.groupproj).';
  { Grupos de proyectos en delphi_config (1.6.0): add-project y
    remove-project escriben lo que "Add existing project" del IDE. }
  SN_GRUPO_ANADIDO_FMT =
    '[GROUP-001] ADDED %s to the group %s (Include="%s"), like the IDE''s ' +
    '"Add existing project": its <Projects>, its targets %s, :Clean and ' +
    ':Make, and its name in Build, Clean and Make.';
  SN_GRUPO_YA_ESTABA_FMT =
    '[GROUP-002] %s was ALREADY in the group %s: I did not touch ' +
    'anything.';
  SR_GRUPO_TARGET_DUP_FMT =
    '[GROUP-003 DENIED] There is already a target "%s" in the ' +
    'group %s, from ANOTHER project: the IDE names targets after the ' +
    'project and two cannot have the same name. I did not touch anything.';
  SR_GRUPO_SIN_DPROJ_FMT =
    '[GROUP-004 NOT_FOUND] %s does not exist: a project is added to a ' +
    'group by its .dproj (or its .dpr/.dpk, with the .dproj next to it).';
  { Con LO QUE FALTA en cada sitio: el texto nombraba una comprobacion que
    solo era la de uno de los tres (novena revision). }
  SR_GRUPO_FORMA_FMT =
    '[GROUP-005 DENIED] %s does not have the shape of an IDE ' +
    'group (%s): I do not touch it.';
  SF_GRUPO_SIN_SITIO_PROYECTO =
    'neither a <Projects> item nor a </PropertyGroup> to add the project after';
  SF_GRUPO_SIN_FINAL =
    'no <Import nor </Project> to write its build targets before';
  SN_GRUPO_NO_ESTABA_FMT =
    '[GROUP-006] %s is not in the group %s: I did not touch anything.';
  SN_GRUPO_QUITADO_FMT =
    '[GROUP-007] REMOVED %s from the group %s: its <Projects>, its %d ' +
    'targets, its name in Build, Clean and Make and in the ' +
    'DependsOnTargets of the ones that depended on it, and its path in ' +
    'the <Dependencies> of the others (%d). The project is still on disk.';
  SN_GRUPO_SIN_AGREGADO_FMT =
    '  [GROUP-008] NOTE: the group has no %s aggregate in the IDE''s ' +
    'shape (<Target Name="X"><CallTarget Targets="..."/>): I did not add ' +
    'it there.';
  { Los de "la llamada estaba mal" empiezan por error: y no por RECHAZADO:
    el prefijo decide el code (INVALID_PARAM frente a DENIED, que es la
    politica) - MCPServer.ToolsManager. }
  SR_GRUPO_NECESITA_PATH =
    '[GROUP-009 INVALID_PARAM] add-project and remove-project need ' +
    '"path": the project''s .dproj (or its .dpr/.dpk).';
  SR_GRUPO_SOLO_GRUPO_FMT =
    '[GROUP-010 INVALID_PARAM] %s is a GROUP (.groupproj) command and %s ' +
    'is a project: pass the .groupproj in "project" and the project in ' +
    '"path".';
  { fix-references (1.6.0). }
  SN_ARREGLA_FMT =
    '[CFG-068] fix-references of %s: %d re-pointed, %d that do not ' +
    'appear in the workspace and %d with several candidates (I do not ' +
    'guess).';
  SN_ARREGLA_VARIOS_FMT =
    '  [CFG-069] with SEVERAL candidates of the same name (you decide: ' +
    'delphi_config remove-unit/add-unit, or remove-project/add-project ' +
    'in a group): %s';
  SN_ARREGLA_FALLIDAS_FMT =
    '  [CFG-070] found but NOT re-pointed (what the project said): %s';
  SN_ARREGLA_RUTAS_FMT =
    '  [CFG-071] search paths that do not exist (there is no name to ' +
    'look for: remove-searchpath and add-searchpath): %s';
  { La mudanza de delphi_move (1.6.0): las rutas relativas que cruzan el borde. }
  SN_REUBICA_FMT =
    '  [MOVE-005] relative paths that crossed the edge of what was ' +
    'moved, re-pointed: %d units from outside in their projects, %d ' +
    'search or output paths of the .dproj, %d {$I}/{$R}/{$L} directives, ' +
    '%d projects in groups inside and %d references from outside that ' +
    'pointed inside (directives, units, paths and groups, in what this ' +
    'session can write). In: %s.';
  SN_REUBICA_FALLOS_FMT =
    '  [MOVE-006] NOTE, I could not re-point in: %s. Check it with ' +
    'delphi_config command=fix-references.';
  SN_REUBICA_SALTADAS_FMT =
    '  [MOVE-007] NOTE, I did not look inside these folders, which are ' +
    'named like an IDE output (Win32, Debug...) but contain sources: %s. ' +
    'If something there pointed to what was moved, check it with ' +
    'delphi_config command=fix-references.';

  SR_CONFIG_NO_DPROJ_FMT =
    '[CFG-072 NOT_FOUND] %s is the .dpr (the source), and the project''s ' +
    'configuration (framework, platforms, search paths, output) lives in ' +
    'the .dproj. There is no %s next to it. If the project has no ' +
    '.dproj, this server cannot configure it: create one with ' +
    'delphi_create or open it once in the IDE. (add-unit and remove-unit ' +
    'do work on the .dpr.)';

  SR_CREATE_BADNAME_FMT =
    '[CREATE-007 INVALID_PARAM] "%s" is not a valid Pascal identifier. A unit ' +
    'name is an ASCII letter, _ or any non-ASCII character, then also ' +
    'digits, with dots between segments if you want a namespace ' +
    '(MyApp.Data.Customers).';

  SR_CREATE_RESERVED_FMT =
    '[CREATE-008 INVALID_PARAM] "%s" is a Delphi reserved word, so "%s" cannot ' +
    'be named that: as soon as it enters the uses of the .dpr the ' +
    'compiler gives E2029, followed by 15 cascading errors that do not ' +
    'point here. Give it a prefix (UBegin; MyApp.Begin is not valid ' +
    'either: the segment must be clean).';

  SR_CREATE_RTLNAME_FMT =
    '[CREATE-009 DENIED] "%s" is the name of an RTL/VCL unit. A file ' +
    'with that name next to the project HIJACKS the real one, and the ' +
    'errors that come afterwards point anywhere but here. Give it a ' +
    'prefix of your own (U%s) or a namespace of YOUR OWN (MyApp.%s): ' +
    'what is not valid is hanging it from one of Embarcadero''s (System., ' +
    'Vcl., FMX., Data...).';

  SR_CREATE_RTLNS_FMT =
    '[CREATE-010 DENIED] "%s" hangs from "%s", which is an Embarcadero ' +
    'namespace. Creating a unit of yours there hijacks the compiler''s ' +
    'one exactly like using the bare name: as soon as it exists, theirs ' +
    'can no longer be found, and the error you see is that something as ' +
    'basic as Exception has disappeared. Use a namespace of your own ' +
    '(not MyApp.%s, but MyCompany.MyApp.Whatever).';

  SR_CREATE_PROJECT_KIND =
    '[CREATE-011 INVALID_PARAM] I can only make five kinds of project: ' +
    'kind=project-console, kind=project-vcl, kind=project-fmx, ' +
    'kind=project-package (a runtime package, .dpk + .dproj) and ' +
    'kind=project-test (a DUnitX runner with its first fixture, for ' +
    'delphi_test). (Then there are form-vcl, form-fmx, frame-vcl, ' +
    'frame-fmx, datamodule and unit, which go INSIDE a project that ' +
    'already exists.)';

  { Un proyecto de test nace verde y con el camino escrito: como se anaden
    fixtures y como se corre. Hermes tuvo que recibir el esqueleto por nota
    (22-sep-2026); desde el 24-sep lo escribe la tool. }
  SN_CREATE_TEST_NOTE_FMT =
    '[CREATE-012] It is a DUnitX runner (it comes with RAD Studio, ' +
    'nothing to install) with the fixture T%0:s in %1:s.pas and one test ' +
    'that passes. Run it with delphi_test command=run project=<this ' +
    '.dproj> (it needs AllowTests=1 in the workspace; discover ' +
    'recognizes it without that). Each new fixture: kind=unit with a ' +
    '[TestFixture] class and TDUnitX.RegisterTestFixture in its ' +
    'initialization; the units you test come in through the uses of the ' +
    '.dpr (delphi_config add-unit) or through add-searchpath to their ' +
    'folder. It exits with ExitCode 1 if any test fails.';

  { Un paquete propio se TRABAJA, no se instala (David, 2026-09-23): se
    compila a BPL+DCP en su carpeta, sus units entran por la clausula
    contains, y el IDE ni lo registra ni lo carga. }
  SN_CREATE_PACKAGE_NOTE =
    '[CREATE-013] It is a RUNTIME package with no units yet: kind=unit ' +
    '(or delphi_config add-unit) writes the first one, in the contains ' +
    'clause. delphi_build compiles it to <name>.bpl + <name>.dcp in ' +
    'Win64\Debug of this folder; it is not installed or registered in ' +
    'the IDE (this server does not do that). For another project to use ' +
    'it, add its output folder to the search path (delphi_config ' +
    'add-searchpath) or link its units directly.';

  SR_CREATE_NEED_DIR =
    '[CREATE-014 INVALID_PARAM] "dir" is missing: the folder where the project ' +
    'is created. It must be inside the workspace; delphi_workspace tells ' +
    'you which one it is.';

  SR_CREATE_CLASH_FMT =
    '[CREATE-015 DENIED] There is already a %s there (in %s) and the ' +
    'scaffolder never overwrites. I created NOTHING: %s still does not ' +
    'exist. A new project wants its own folder; set "dir" to a subfolder.';

  SN_CREATE_CONSOLE_FORM =
    '[CREATE-016] NOTE: that project is a CONSOLE one (it uses neither ' +
    'Vcl.Forms nor FMX.Forms), so the form goes in and compiles but ' +
    'nobody will ever see it: there is no Application to create it and ' +
    'no message loop to show it. If you really want to turn it into an ' +
    'application with a window, the .dpr has to change (the framework''s ' +
    'uses, Application.Initialize/CreateForm/Run) and the {$APPTYPE ' +
    'CONSOLE} has to go.';

  SR_CREATE_FRAMEWORK_FMT =
    '[CREATE-017 INVALID_PARAM] You ask for a %s but %s is a %s project. Mixing ' +
    'them compiles badly and late: the form would go with its ' +
    'Application.CreateForm into a .dpr that uses the other framework. ' +
    'Use the right kind, or create the form in a project of its type.';

  SR_CREATE_CONTENT_NOUNIT =
    '[CREATE-018 INVALID_PARAM] The "content" you send does not start with ' +
    '"unit <name>;", so it is not a Pascal unit. Send the COMPLETE ' +
    'source (unit / interface / implementation / end.) or send no ' +
    'content and you get the empty skeleton.';

  SR_CREATE_CONTENT_NAME_FMT =
    '[CREATE-019 INVALID_PARAM] The source says "unit %s" but the file would be ' +
    'named %s.pas. Delphi requires them to match. Fix one of the two.';

  SR_CREATE_CONTENT_NOEND =
    '[CREATE-020 INVALID_PARAM] The "content" does not end with "end." - it ' +
    'looks cut off. Send the whole unit; if it is long, use ' +
    'delphi_upload in chunks and then delphi_config command=add-unit to ' +
    'register it.';

  SR_CHANGESET_VIRT_MISSING_FMT =
    '[CHSET-001 NOT_FOUND] %s does not exist, and no earlier operation ' +
    'of this same batch creates it. If a later one is going to create ' +
    'it, reorder the operations: they are applied in the order you stack ' +
    'them.';

  SR_CHANGESET_VIRT_EXISTS_FMT =
    '[CHSET-002 DENIED] %s already exists (create never overwrites). If ' +
    'what you want is to redo it entirely, first stack kind=delete of ' +
    'that same file and then the create: the batch counts what you ' +
    'stack, not only what is on disk.';

  SR_CHANGESET_VIRT_DEST_FMT =
    '[CHSET-003 DENIED] The destination %s already exists (or an earlier ' +
    'operation of this batch creates it). Choose another name or delete ' +
    'that one first.';

  SR_CHANGESET_PADRE_FICHERO_FMT =
    '[CHSET-027 INVALID_PARAM] %s cannot be created: %s is a FILE, not a ' +
    'folder. Choose another path.';

  SR_CHANGESET_UNSTAGE_N_FMT =
    '[CHSET-004 INVALID_PARAM] n=%d is not valid; there are %d stacked ' +
    'operations. Use the number command=preview gives you, or n=0 to ' +
    'remove the last one.';

  SN_CHANGESET_UNSTAGED_FMT =
    '[CHSET-005] Removed operation %d (%s %s). %d still stacked. Nothing ' +
    'was touched on disk: the batch is still alive.';

  SN_CHANGESET_PREVIEW_VIRTUAL =
    '[CHSET-006] That file does not exist yet: an earlier operation of ' +
    'this same batch creates it, so the anchor cannot be checked until ' +
    'the commit. If it fails, the commit undoes the whole batch as ' +
    'always.';

  SR_UPLOAD_OFFSET_INSIDE_FMT =
    '[UPLOAD-001 INVALID_PARAM] offset %d falls INSIDE the file (it has %d ' +
    'bytes), and writing there would wipe out everything after it, with ' +
    'no recoverable copy. To continue a chunked upload, the offset is ' +
    'the current END: use offset=%d. To replace the whole file, offset=0 ' +
    '(that one does leave a copy).';

  SR_UPLOAD_BINARY_DESIGNER =
    '[UPLOAD-002 DENIED] That is a BINARY .dfm/.fmx (TPF0 signature or ' +
    '$FF resource wrapper) and this server does not interpret binary ' +
    'designers: if you upload it, no tool here will be able to read or ' +
    'fix it again, and if it also overwrites a live text designer you ' +
    'lose the readable original. Upload the designer as TEXT (it starts ' +
    'with "object <Name>: <TClass>").';

  SR_UPLOAD_BAD_SHA_FMT =
    '[UPLOAD-003 INVALID_PARAM] "%s" does not have the shape of a sha256 ' +
    '(it is 64 hexadecimal digits). I uploaded nothing.';

  SR_UPLOAD_NO_CHUNK_FMT =
    '[UPLOAD-004 INVALID_PARAM] You do not send "chunkbase64", so there is ' +
    'nothing to upload, and there is already a file of %d bytes there. A ' +
    'half-made call does NOT empty it. If you want to replace it, send ' +
    'its content in base64; if you want to delete it, delphi_delete.';

  SR_UPLOAD_NO_CHUNK_NEW =
    '[UPLOAD-005 INVALID_PARAM] "chunkbase64" is missing: the content in ' +
    'base64. For a text file, empty or with content, delphi_create / ' +
    'delphi_edit are the better tool; delphi_upload is for binaries and ' +
    'for chunks.';

  // Lsp.Base64: los rechazos del decodificador, con el nombre del parametro.
  SR_B64_ALPHABET_FMT =
    '[UPLOAD-006 INVALID_PARAM] %s contains characters that are not ' +
    'base64. I wrote nothing.';

  SR_B64_LEN_FMT =
    '[UPLOAD-007 INVALID_PARAM] %s has %d usable characters and base64 comes in ' +
    'groups of 4: characters are missing or extra, almost always from ' +
    'transcribing a long chunk. I wrote nothing. Send shorter chunks, or ' +
    'pass chunkSha256 with each one so the failure shows in the chunk ' +
    'and not at the end.';

  SR_B64_INVALID_FMT =
    '[UPLOAD-008 INVALID_PARAM] %s is not valid base64 (%s)';

  SR_UPLOAD_CHUNK_SHA_MISMATCH_FMT =
    '[UPLOAD-009 INVALID_PARAM] The sha256 of THIS chunk does not match ' +
    '(received %s, expected %s; %d bytes decoded). I wrote nothing: the ' +
    'file is as it was. Resend the same chunk with the same offset.';

  SR_UPLOAD_SHA_MISMATCH_FMT =
    '[UPLOAD-011 INVALID_PARAM] The sha256 does NOT match: what was ' +
    'assembled differs from the source, so I do NOT leave it published ' +
    'under its name. I set it aside in %s. Resend from offset=0.';

  { Decia "una por dia, la de esta manana" y backup es la copia SELLADA de
    lo que habia justo antes (sexta revision; el texto se quedo atras,
    septima). }
  SN_UPLOAD_REPLACED_FMT =
    '[UPLOAD-010] NOTE: there was already a file there (%d bytes) and ' +
    'this upload REPLACED it entirely. What it said until now is in ' +
    '"backup" (the replaced drawer of the __delphi-patch trash next to ' +
    'the file: one stamped copy per replacement). If you wanted to ' +
    'append at the end and not replace, use offset=<the current size>, ' +
    'not offset=0.';

  SP_DELETE_PURGE =
    'true = DELETE FOR REAL, with no way back - only INSIDE the trash ' +
    '(__delphi-patch), to clean up your own copies when you no longer need ' +
    'them, not to skip the trash: a live file always goes through it first.';

  SR_FILE_PURGE_ONLY_TRASH =
    '[FILE-007 DENIED] purge=true can only be used INSIDE the trash ' +
    '(__delphi-patch). For a live file, delete it normally: it goes to ' +
    'the trash, and if you really want it gone, purge it from there. ' +
    'That two-step is the safety net every other tool depends on.';

  SR_GUARD_OWNER_MARKER =
    '[GUARD-003 DENIED] The ".by" files are the marker of who sent ' +
    'something to the trash. The server writes them and they are not ' +
    'edited: rewriting one is claiming another agent''s work.';
  SR_GUARD_DEAD_TRASH =
    '[GUARD-004 DENIED] __delphi-patch\ is the trash of recoverable ' +
    'copies. It is read and restored from, but not written into: that ' +
    'copy is the LAST good version of a file and overwriting it destroys ' +
    'exactly what the trash exists to keep. The live file is one level ' +
    'up.';
  SR_GUARD_DEAD_IDE =
    '[GUARD-005 DENIED] __history\ and __recovery\ are the IDE''s dead ' +
    'copies. They are not written into; the live file is in the project ' +
    'folder.';

  { Ni papelera ni copia muerta: la carpeta donde el servidor deja LO SUYO.
    Se lee -de ahi te bajas una captura con delphi_fetch- y se puede borrar
    entera en cualquier momento, que es justo por lo que no se escribe codigo
    dentro: lo que pongas ahi no tiene por que seguir estando. }
  SR_GUARD_DEAD_TEMP =
    '[GUARD-006 DENIED] __delphi-temp\ is the server''s temporary folder, ' +
    'not a place to work. What is there is put there by the server and ' +
    'can be wiped entirely at any moment, so a file of yours in there is ' +
    'a file you are going to lose. You can read it (download a capture ' +
    'with delphi_fetch); write your work in the workspace.';

  SR_FILE_PURGE_FOLDER_NOT_YOURS_FMT =
    '[FILE-008 DENIED] Inside that folder there are %d copy(ies) that ' +
    'other agents sent to the trash (%s). A folder is purged whole or ' +
    'not at all: purge your copies one by one, or ask the operator to ' +
    'clean the folder.';

  SR_FILE_PURGE_NOT_YOURS_FMT =
    '[FILE-009 DENIED] That copy was sent to the trash by ANOTHER agent ' +
    '(%s), so it is not yours to purge. Clean up what is yours; what ' +
    'belongs to the others is removed by its owner or the operator. (If ' +
    'this really is yours, connect with the same clientInfo.name you ' +
    'deleted it with.)';

  SR_FILE_PURGE_NOT_ROOT =
    '[FILE-010 DENIED] That is the WHOLE __delphi-patch folder, and ' +
    'inside there are copies belonging to others. Purge what is yours: ' +
    'the day''s subfolder, or the specific copy you want out of the way.';

  SR_FILE_PURGE_FAILED_FMT =
    '[FILE-011 DENIED] I could not delete %s (%s). If something has it ' +
    'open, retry in a moment.';

  { delphi_delete DENTRO de una temporal del servidor: de un temporal no se
    restaura nada, asi que no hay copia (26-sep-2026). }
  SN_FILE_DELETE_TEMP_FMT =
    '[FILE-012] DELETED %s, without a copy: it is a server temporary ' +
    '(__delphi-temp), and nothing is restored from a temporary.';
  SR_FILE_DELETE_TEMP_ROOT_FMT =
    '[FILE-013 DENIED] %s is the server''s WHOLE temporary folder: it ' +
    'belongs to all its agents and empties itself at startup. Delete ' +
    'what is yours inside it (your subfolder, a capture).';

  SN_FILE_PURGED_FMT =
    '[FILE-014] PURGED %s. There is no way back from this: it was a copy ' +
    'in the trash and it is gone.';

  SN_FILE_DELETE_EMPTY_SHELL_FMT =
    '[FILE-037] ALMOST: ALL the content of %s is already out ' +
    '(recoverable copy in %s), and all that is left is the EMPTY folder, ' +
    'which I am not allowed to remove (some process has it as its ' +
    'current directory). I do not say DELETED because the shell is still ' +
    'there, but do not run the delete again: there is nothing left to ' +
    'copy and each attempt only litters the trash. Let the operator ' +
    'remove it, or leave it: it is empty.';

  SN_FILE_DELETE_EMPTY_OK_FMT =
    '[FILE-015] DELETED the empty folder %s. I made no copy: there was ' +
    'nothing inside to copy.';

  SR_FILE_DELETE_STUCK_FMT =
    '[FILE-016 DENIED] %s is empty but I cannot remove it: something has ' +
    'it open (usually it is the current directory of some process). ' +
    'There is nothing inside, so nothing is lost by leaving it; if it is ' +
    'in the way, the operator removes it.';

  SR_FILE_DELETE_PARTIAL_FMT =
    '[FILE-038 DENIED] HALFWAY: the recoverable copy of %s IS made ' +
    '(%s), but the original could NOT be removed from its place: ' +
    'something has it open (a build in progress, the IDE, or a folder ' +
    'that is the current directory of some process). I do not say ' +
    'DELETED because it is not. Retry in a moment; if it stays the same, ' +
    'the operator has to remove it by hand.';

  SR_STYLES_RC_OUTSIDE_FMT =
    '[STYLE-023 DENIED] The manifest entry %s of %s points to a file ' +
    'that is OUTSIDE what this server lets you read. I do not compile ' +
    'it: the resource compiler opens whatever you give it with the ' +
    'server''s permissions and puts the content inside the .res, which ' +
    'can then be downloaded; that way everything from win.ini to the ' +
    'configuration file with the token has been pulled out. The .rc ' +
    'paths must stay inside the workspace, and preferably be relative to ' +
    'the styles folder.';

  SR_STYLES_RC_DEEP =
    '[STYLE-024 DENIED] The manifest''s #include directives nest too deep ' +
    '(more than 8). Flatten the .rc: if that depth is needed, something ' +
    'odd is going on.';

  SR_STYLES_RC_BADPATH_FMT =
    '[STYLE-025 DENIED] I cannot resolve the path %s of the .rc. Use ' +
    'paths relative to the .rc''s own folder.';

  SR_STYLES_RC_UNREADABLE_FMT =
    '[STYLE-026 DENIED] I cannot read the .rc (%s) to check which files ' +
    'it points to, so I do not compile it.';

  // PAS-031 (un nombre de perfil CON punto) retirado el 9-oct-2026:
  // set-profile y remove-profile contestan PAS-015, la regla de la puerta
  // (Lsp.Guard.BadProfileName)

  SN_PASERVER_PROFILE_REMOVED_FMT =
    '[PAS-032] DELETED the connection profile "%s". NOTE: profiles live ' +
    'outside the workspace (where the IDE keeps them), so this has NO ' +
    'trash: there is no way back except creating it again with ' +
    'add-profile.';

  SR_PASERVER_HOST_DENIED_FMT =
    '[PAS-033 DENIED] I do not dial "%s". Dialing is a connection that ' +
    'THIS server opens, so deciding where is not up to you: ONLY the ' +
    'hosts the operator has written in RemoteHosts of the active ' +
    'workspace are valid (right now: %s). Having an IDE profile pointing ' +
    'there is NOT permission: the profile says HOW to connect, the ' +
    'workspace says WHETHER you may.';

  // ProfileHostDenido (Lsp.Discovery) falla CERRADO: los cuatro motivos por los
  // que no puede comprobar el host del perfil, cada uno con el suyo (1.15.1).
  SR_PROFILE_NO_DELPHI =
    '[PAS-052 INTERNAL] I cannot check the profile''s host: no RAD Studio ' +
    'installation was found on this server. Nothing was dialed or deployed.';
  SR_PROFILE_NO_EXISTE_FMT =
    '[PAS-053 DENIED] The connection profile "%s" does not exist on this ' +
    'server, so I cannot check its host against RemoteHosts: nothing was ' +
    'dialed or deployed. delphi_paserver command=profiles lists the ones there are.';
  SR_PROFILE_NO_LEIDO_FMT =
    '[PAS-054 INTERNAL] I could not read the connection profile "%s" to check ' +
    'its host, so nothing was dialed or deployed. Tell the operator.';
  SR_PROFILE_SIN_HOST_FMT =
    '[PAS-055 DENIED] The connection profile "%s" declares no host ' +
    '(Profile_host), so there is nothing to check against RemoteHosts and ' +
    'nothing was dialed or deployed.';

  // Lo que paclient dice en ingles crudo cuando el otro lado no es el suyo
  // (Lsp.BuildRunner.AvisoDePaclient): una maquina puede tener un PAServer por
  // Delphi, cada uno en su puerto (el Zorin de David: 13.1 y 13.2).
  SN_PACLIENT_OTRO_DELPHI_FMT =
    '[PAS-056] The PAServer at that host and port is not the one of this ' +
    'server''s Delphi: its paclient expects version %s. One machine can run ' +
    'one PAServer per Delphi, each on its own port: point the profile to the ' +
    'port of this Delphi''s PAServer (delphi_paserver add-profile with port=), ' +
    'or install that one there (delphi_paserver packages lists this ' +
    'Delphi''s installers).';
  SN_PACLIENT_OTRA_PLATAFORMA_FMT =
    '[PAS-057] The profile says %s and the machine behind it is %s: the ' +
    'profile points to another machine or to another PAServer. delphi_paserver ' +
    'profiles lists them; create one for that platform with add-profile.';

  SR_GIT_REMOTE_OFF_FMT =
    '[GIT-004 DENIED] This server does not talk to "%s". An explicit URL ' +
    'in a git command makes THE SERVER open the connection, so deciding ' +
    'who it opens it with is not up to you: the operator writes the ' +
    'allowed hosts in [Workspace.<name>] GitRemotes of settings.ini. The ' +
    'remotes the operator has already configured in the repository DO ' +
    'work: use the remote''s name (push origin main), not the URL.';

  SR_GIT_REMOTE_HOST_FMT =
    '[GIT-005 DENIED] "%s" is not among the hosts this server allows ' +
    '(%s). If one more is needed, ask for it with delphi_report: the ' +
    'operator adds it.';

  { Una direccion cuyo host no se lee sin adivinar (GitUrlHost, Lsp.Args):
    git, ssh y curl no parten igual la autoridad, asi que se niega en vez de
    elegir (revisor de addc44e, 9-oct-2026). }
  SR_GIT_REMOTE_AMBIGUA_FMT =
    '[GIT-062 DENIED] The address "%s" does not show its host plainly (a ' +
    '%%, \, ?, #, a space, a bracket or a second @ before the host, a @[ ' +
    'anywhere, or no host at all): git, ssh and curl would not all read ' +
    'the same host from it. Write it plainly: scheme://[user@]host[:port]/' +
    'path or user@host:path.';

  SN_GIT_HINT_OVERRIDE =
    '[GIT-006] NOTE about the "hint:" lines above: git writes them, not ' +
    'me, and some recommend exactly what this tool does not allow ' +
    '(--no-ff, rebase, giving the URL on the command line). Here the way ' +
    'out of a diverged merge is to leave it and tell a human, or merge ' +
    'args=--abort if you were left halfway; and for a remote, its NAME, ' +
    'not its URL.';

  SR_GIT_MERGE_ARGS =
    '[GIT-007 DENIED] merge only accepts the NAME of a branch, or ' +
    '"--abort" to get out of a half-done merge. No options: --no-ff (and ' +
    'any other that cancels the --ff-only it is run with) leaves the ' +
    'repository in MERGING with half-resolved conflicts, which is ' +
    'exactly what this command promises cannot happen.';

  { pull es bajar e INTEGRAR, y lo segundo lo hacia como git quisiera: con
    las historias divergidas y sin ninguna opcion dejaba un commit de mezcla
    -lo que merge promete aqui que no puede pasar-, con --rebase reescribia
    la historia y con --squash dejaba el arbol a medias (medido el
    29-sep-2026). Se corre SIEMPRE con --ff-only, como merge, y de las
    opciones admite las de la bajada. }
  SR_GIT_PULL_ARGS_FMT =
    '[GIT-042 DENIED] pull does not take "%s". It integrates by ' +
    'fast-forward and nothing else (it is run with --ff-only, like ' +
    'merge): what would need a merge commit or a rebase is refused, not ' +
    'left half-done. It takes a remote and a branch (args="origin ' +
    'main") and, of the options, those of the download: --tags, ' +
    '--no-tags, --prune, --depth=<n>, --unshallow (and --ff-only, which ' +
    'it has anyway). Nothing was done.';

  { Las opciones de fetch y de push: una lista de las que valen (la de pull
    es la de fetch mas --ff-only, y tiene su texto). }
  SR_GIT_RED_OPCION_FMT =
    '[GIT-043 DENIED] %s does not take "%s". Of the options it takes ' +
    'these and no other: %s. The rest of "args" is the remote and what ' +
    'to bring or send (args="origin main"). Nothing was done.';

  { EL REMOTO es adonde git va a leer o a escribir. Era de la jaula y no lo
    miraba nadie cuando era una CARPETA: la lista de hosts solo entiende
    direcciones de red. Medido el 29-sep-2026 por la tool: con una carpeta
    de fuera de las raices, por su ruta o por el nombre de un remoto, fetch
    traia su historia y push escribia ramas alli. }
  SR_GIT_REMOTO_FUERA_FMT =
    '[GIT-044 DENIED] The remote of this %s reaches the folder "%s", ' +
    'where this session may not %s: it is outside your roots, or it is ' +
    'there only to be read. A remote that is a folder is looked at ' +
    'whole - the folder and the repository that lives there, which may ' +
    'be somewhere else (a linked worktree) - and given by its path or by ' +
    'the name it has in the repository it is the same folder. Nothing ' +
    'was done.';

  { Las formas que se ADMITEN de la direccion de un remoto. Medido el
    29-sep-2026 por la tool (cuarta revision): git decodifica los %xx de un
    file:// y aqui se leian tal cual, y un remoto del repo con su direccion
    en file://C:/... (dos barras) pasaba por direccion de red. }
  SR_GIT_REMOTO_ILEGIBLE_FMT =
    '[GIT-045 DENIED] The remote of this %s, "%s", is not in a form this ' +
    'tool takes (if you gave a name, that is the address the name has in ' +
    'the repository). A remote is the NAME it has in the repository ' +
    '(args="origin"); a network address the operator allows, written ' +
    'with its scheme (https://, http://, ssh://, git://) or as ' +
    'user@host:path; or a FOLDER that is there, inside your roots, by ' +
    'its path - the folder itself, with its whole name - or as ' +
    'file:///<drive>:/<path> with nothing percent-encoded. Nothing was ' +
    'done.';

  { Lo que se escribe en la llamada y no es NI un remoto del repo NI una
    carpeta que este. Lo mas corriente: un repo recien hecho con init, sin
    remotos, y "push origin main". Llegaba a git, que decia que "origin" no
    parecia un repositorio; desde que una carpeta-remoto tiene que ser una
    carpeta que esta, se dice aqui, con los remotos que el repo SI tiene. }
  SR_GIT_REMOTO_NO_ESTA_FMT =
    '[GIT-049 NOT_FOUND] "%s" is not a remote of this repository (its ' +
    'remotes: %s), and it is not a folder that is there either ("%s"). A ' +
    'remote is given by the name it has in the repository, as a network ' +
    'address the operator allows, or as a folder inside your roots - the ' +
    'folder itself, with its whole name. This tool does not add remotes: ' +
    'a clone brings its own, and the operator configures the others. ' +
    'Nothing was done.';

  { Si git no contesta a lo que se le pregunta para JUZGAR el remoto (sus
    remotos, la direccion de uno, su configuracion), el remoto no se usa: un
    fallo de la pregunta acababa en "se puede" (cuarta revision de la 1.7.7,
    leido en el codigo). }
  SR_GIT_REMOTO_SIN_RESPUESTA_FMT =
    '[GIT-047 DENIED] git did not answer what this server asks it before ' +
    'a %s (the remotes of the repository, their addresses, what they are ' +
    'configured to send), and a remote that cannot be looked at is not ' +
    'used. Repeat in a moment; if it goes on, command=status says how ' +
    'the repository is. Nothing was done.';

  { Lo que push envia cuando la llamada no lo dice lo decide la configuracion
    del repo. Medido el 29-sep-2026 (cuarta revision): desde un repo espejo
    (clone --mirror), push a secas borro del remoto una rama. }
  SR_GIT_PUSH_CONFIG_FMT =
    '[GIT-048 DENIED] With no names in the call, what goes to the remote ' +
    '"%s" is what this repository is configured to send (%s), and that ' +
    'overwrites or deletes what is there. push ADDS to the remote ' +
    'through this tool: say what to send by its name (args="%s main"). ' +
    'Nothing was done.';

  { Lo que push ENVIA, detras del remoto: nombres. push anade al remoto; lo
    que ya hay alli no se reescribe ni se borra por esta tool (David,
    29-sep-2026). Medido ese dia, con --force y --delete ya negados por su
    nombre: args="origin +main" reescribia la rama del remoto y
    args="origin :sobra" la borraba. }
  SR_GIT_PUSH_NOMBRE_FMT =
    '[GIT-046 DENIED] push does not take "%s". After the remote come the ' +
    'names of what to send: a branch or a tag (args="origin main"), or ' +
    'local:remote with a name on each side (args="origin ' +
    'HEAD:refs/heads/copy"). A name starts with a letter or a digit and ' +
    'goes on with letters, digits and . _ / - ; what is on the left of ' +
    'local:remote may be a version of the repository too (HEAD~1). ' +
    'push ADDS to the remote: what is already there is ' +
    'never overwritten or deleted through this tool - if the remote has ' +
    'moved on, bring it first (command=pull). Nothing was done.';

  SN_GIT_MERGE_DIVERGED =
    '[GIT-008] MERGE REFUSED BY GIT: the two branches have diverged and ' +
    'this tool only integrates by fast-forward (no merge commit, no ' +
    'half-done conflicts). Nothing was touched. Integrating diverged ' +
    'branches is a job for a person (merge or rebase by hand); if what ' +
    'you want is to catch up, switch to the other branch and carry on ' +
    'from there.';

  SR_GIT_MESSAGE_LINES =
    '[GIT-009 INVALID_PARAM] "message" does not allow line breaks in ' +
    'this command (it goes on the command line). commit and tag DO allow ' +
    'them: there the message is passed through a file (-F) and you can ' +
    'write subject, blank line and body.';

  SR_GIT_SWITCH_NEEDS =
    '[GIT-010 INVALID_PARAM] switch needs "args" with the branch name. To ' +
    'create a new one and jump to it: args=<branch> create=true. ' +
    'Uncommitted changes travel with you; if git complains, save them ' +
    'first with command=stash args=push.';

  SR_GIT_MERGE_NEEDS =
    '[GIT-011 INVALID_PARAM] merge needs "args" with the branch to integrate. ' +
    'It is always done --ff-only: if a merge commit were needed (or ' +
    'there were conflicts), it is refused instead of being left halfway. ' +
    'That is a job for a person, not for an agent guessing.';

  { Dice lo que RECIBIO: contestaba "drop no esta" a un push con rutas que
    nadie habia pedido tirar (26-sep-2026). }
  SR_GIT_STASH_RUTA_FMT =
    '[GIT-012 DENIED] stash push -- "%s": that is not a path of this ' +
    'repository (%s). It takes files or folders INSIDE the repo, ' +
    'relative to "repo" or absolute, with their name as is: no ' +
    'wildcards. Nothing was saved.';

  SR_GIT_STASH_ARGS_FMT =
    '[GIT-013 INVALID_PARAM] stash does not understand args="%s". It ' +
    'accepts: push (saves EVERYTHING, the default); push -- <paths> ' +
    '(saves ONLY those: they go back to how they are in HEAD and what ' +
    'was there before stays in the stash, which is how you discard a ' +
    'file''s changes without losing them; no options, and the label goes ' +
    'in "message"); pop (restores the last one) and list. drop does not ' +
    'exist: it destroys work with no way back.';

  { restore: SIEMPRE --staged. Hermes (28-sep-2026): tras un add no habia forma
    de deshacer el staging por el MCP (ni rm ni reset en la lista) y borro el
    .git para volver a empezar. El arbol de trabajo no se toca nunca: para
    descartar cambios esta stash push -- <rutas>. }
  SR_GIT_RESTORE_ARGS_FMT =
    '[GIT-039 INVALID_PARAM] restore does not understand args="%s". It ' +
    'takes ONLY paths, one or more (. = everything): args="a.txt src". ' +
    'It is always --staged: those paths leave the index (the add is ' +
    'undone) and the working tree is never touched; no options. To ' +
    'discard a file''s changes, stash push -- <paths>. Nothing was done.';

  SR_GIT_RESTORE_RUTA_FMT =
    '[GIT-040 DENIED] restore -- "%s": that is not a path of this ' +
    'repository (%s). It takes files or folders INSIDE the repo, ' +
    'relative to "repo" or absolute, with their name as is: no ' +
    'wildcards. Nothing was done.';

  { git no trabaja sobre la carpeta que se le da: sube desde ella hasta dar
    con el repo, y lee y reescribe ESE arbol entero. Con la raiz del repo por
    encima de las raices de la sesion, status y diff ensenaban lo de fuera y
    stash, switch y commit lo reescribian (medido el 29-sep-2026: una sesion
    con mono\a por unica raiz reescribio mono\b). Las tres carpetas del repo
    -la raiz del arbol, su .git y la comun de un worktree enlazado- pasan por
    la puerta. }
  SR_GIT_REPO_FUERA_FMT =
    '[GIT-041 DENIED] "%s" belongs to a git repository that lives at ' +
    '"%s", outside your workspace: git would read and rewrite that ' +
    'whole tree, not just the folder you name. delphi_git works on a ' +
    'repository whose root and whose .git folder are inside your roots ' +
    '(delphi_workspace lists them): command=init makes one in a folder ' +
    'of yours, and command=clone brings one. Nothing was done.';

  // ---- delphi_git worktree (1.4.0) ----

  SR_GIT_WORKTREE_ARGS =
    '[GIT-014 INVALID_PARAM] worktree accepts args=list (the working copies of ' +
    'this repo), args=add with the PARAMETERS path (a NEW folder inside your ' +
    'roots) and ref (a tag, branch or commit), or args=remove with the ' +
    'parameter path (one that list shows). path and ref are parameters of ' +
    'the call, never inside args.';

  SR_GIT_MENSAJE_EN_ARGS =
    '[GIT-059 INVALID_PARAM] The message of a commit or a tag goes in the ' +
    'parameter "message", not in args (-m, --message): it reaches git byte ' +
    'for byte from there. args keeps the rest (the tag name, its options). ' +
    'Nothing was done.';

  SR_GIT_WORKTREE_PATH =
    '[GIT-015 INVALID_PARAM] worktree add/remove need "path": the folder of the ' +
    'working copy (add: a NEW folder inside your roots, like the ' +
    'destination of a clone).';

  SR_GIT_WORKTREE_EXISTS_FMT =
    '[GIT-016 DENIED] %s already exists. A worktree goes in a NEW ' +
    'folder: choose another name, or remove the existing one first.';

  SR_GIT_WORKTREE_REF =
    '[GIT-017 DENIED] "ref" must be a tag, a branch or a commit ' +
    '(letters, digits and . _ / ~ ^ -, not starting with a dash): for ' +
    'example v1.3.2, main, HEAD~3 or a hash.';

  SR_GIT_WORKTREE_INSIDE_FMT =
    '[GIT-018 DENIED] The worktree cannot go inside the repository ' +
    'itself (%s): the main tree would see it as an untracked folder and ' +
    'an "add -A" would take it along. Put it outside, next to it.';

  SR_GIT_WORKTREE_NOT_LISTED_FMT =
    '[GIT-019 NOT_FOUND] %s is not a worktree of this repository ' +
    '(command=worktree args=list shows the ones there are). remove only ' +
    'removes those, and never the main copy.';

  SR_GIT_WORKTREE_LINK_FMT =
    '[GIT-020 DENIED] This worktree is not removed because it contains a ' +
    'link (%s): git would go through it and delete what is behind it, ' +
    'which may not be yours. Remove the link first and repeat.';

  SN_GIT_WORKTREE_ADDED_FMT =
    '[GIT-021] Worktree ready at %s, with that version checked out on ' +
    'its own (detached): build and test there (delphi_build, ' +
    'delphi_test) to compare. It is yours to clean up: remove it with ' +
    'command=worktree args=remove and the same path when you are done; ' +
    'args=list shows it while it remains.';

  // ---- delphi_changeset ----

  SD_CHANGESET =
    'MULTI-FILE TRANSACTIONS: when one change touches several files, the ' +
    'whole batch lands or none of it. Flow: begin (gives an id) -> stage ' +
    'one operation per call (kind=edit|create|delete|move; nothing touches ' +
    'disk yet) -> preview (resolves every edit anchor, rehearses each edit ' +
    'and create with the engine - encoding, read-only attribute, binary ' +
    'content, the write gate - and fingerprints every file the batch ' +
    'touches) -> commit (fingerprints re-checked: a file changed since ' +
    'preview refuses the WHOLE batch; byte snapshots taken, operations ' +
    'applied in order; any failure restores every file byte-exact and says ' +
    'which operation failed). rollback discards a staged batch; status ' +
    'lists the open ones. Edits follow delphi_edit: old = ONE full line, ' +
    'unique in the file (atline pins a duplicate) - or fragment + atline + ' +
    'new for a LONG line, resolved when you stage it. Every anchor ' +
    'resolves against the file as it is BEFORE the changeset: an edit ' +
    'cannot anchor on a line an earlier edit of it writes (several edits ' +
    'of one file: delphi_edit edits=). It expires after 30 minutes unused. ' +
    'For renames, refactors and any change where a half-applied batch ' +
    'would break the project; for one file, delphi_edit is simpler.';

  SP_CHANGESET_COMMAND =
    'begin (new changeset -> id) | stage (add ONE operation) | unstage ' +
    '(take operation "n" back out; n=0 = the last one) | preview (resolve ' +
    'anchors, rehearse, fingerprint; required before commit) | commit (all ' +
    'or nothing) | rollback (discard) | status (the open ones)';

  SP_CHANGESET_N =
    'unstage: number of the operation to remove, the one preview shows ' +
    '(0 or empty = the last one staged)';

  SP_CHANGESET_ID =
    'The changeset id returned by begin (every command except begin and status)';

  SP_CHANGESET_KIND =
    'stage: edit (replace ONE line by anchor) | create (new file, never ' +
    'overwrites) | delete (the WHOLE FILE; the snapshot is the way back) | ' +
    'delete-line (remove ONE line by atline: a BLANK one, which has no ' +
    'usable anchor, or with old the line you name) | move (rename/move; the ' +
    'destination must not exist)';

  SP_CHANGESET_PATH =
    'stage: the file the operation touches (inside the workspace roots)';

  SP_CHANGESET_DEST =
    'stage kind=move: the destination path';

  SP_CHANGESET_OLD =
    'stage kind=edit: the anchor - ONE full line copied verbatim from ' +
    'delphi_read, unique in the file (or fragment + atline instead). ' +
    'kind=delete-line: the line you expect at atline, compared like an ' +
    'anchor (the preview refuses when it is not that one); without it, ' +
    'that line must be blank (EDIT-123), as in delphi_edit.';

  SP_CHANGESET_NEW =
    'stage kind=edit: the replacement text (may span several lines)' +
    SP_NEW_SALTO_FINAL;

  SP_CHANGESET_CONTENT =
    'stage kind=create: the whole content of the new file';

  SP_CHANGESET_ATLINE =
    'stage kind=edit optional: the 1-based line that pins the anchor when ' +
    'the same line appears more than once. REQUIRED for kind=delete-line. ' +
    'Rebased automatically against what earlier operations of the ' +
    'changeset did to that file.';

  SR_CHANGESET_CMD =
    '[CHSET-007 INVALID_PARAM] Command must be begin | stage | unstage | ' +
    'preview | commit | rollback | status';

  SR_CHANGESET_NEED_ID =
    '[CHSET-028 INVALID_PARAM] Missing "id": the changeset ' +
    '(command=begin opens one and gives its id; command=status lists the ' +
    'open ones).';

  SR_CHANGESET_TOO_MANY_FMT =
    '[CHSET-008 DENIED] There are already %d open changesets. Close one ' +
    '(commit or rollback) or wait for them to expire (%d min unused).';

  SR_CHANGESET_UNKNOWN_FMT =
    '[CHSET-009 NOT_FOUND] That changeset does not exist (or it expired ' +
    'after %d min unused). command=status lists the open ones; ' +
    'command=begin opens a new one.';

  SR_CHANGESET_KIND =
    '[CHSET-010 INVALID_PARAM] kind must be edit | create | delete | ' +
    'delete-line | move.';

  SR_CHANGESET_NEED_PATH =
    '[CHSET-011 INVALID_PARAM] stage needs "path" (the file the operation ' +
    'touches).';

  SR_CHANGESET_NEED_DEST =
    '[CHSET-012 INVALID_PARAM] kind=move needs "dest" (the destination).';

  SR_CHANGESET_EDIT_NEEDS =
    '[CHSET-013 INVALID_PARAM] kind=edit needs "old" (ONE complete line copied ' +
    'from delphi_read) and optionally "new" (the replacement) and ' +
    '"atline".';

  SR_CHANGESET_DELLINE_NEEDS =
    '[CHSET-014 INVALID_PARAM] kind=delete-line needs "atline" (the line ' +
    'number, 1-based) because a BLANK line has no usable anchor. "old" ' +
    'is optional and, if you give it, it must match that line.';

  SR_CHANGESET_EMPTY =
    '[CHSET-015 DENIED] The changeset has no operations. stage adds one ' +
    'per call.';

  SR_CHANGESET_NOT_PREVIEWED =
    '[CHSET-016 DENIED] commit requires a previous CLEAN preview ' +
    '(unresolved=0), taken after the last operation you staged or ' +
    'removed (stage or unstage). Call command=preview and check the ' +
    'result.';

  SR_CHANGESET_FILE_CHANGED_FMT =
    '[CHSET-017 DENIED] FILE_CHANGED - these files changed after the ' +
    'preview: %s. Nothing was touched. Repeat preview (the fingerprints ' +
    'are recomputed) and commit again.';

  SR_CHANGESET_ROLLED_BACK_FMT =
    '[CHSET-026 DENIED] ROLLBACK COMPLETE: operation %d of %d failed and ' +
    'ALL the files are back, byte for byte, to how they were before the ' +
    'commit. Cause: %s -- The changeset stays closed; fix it and build ' +
    'another one.';

  SR_CHANGESET_PROJECT_FILE_FMT =
    '[CHSET-018 DENIED] %s is a project file and the IDE maintains it; ' +
    'the commit would have refused it anyway, and it would have thrown ' +
    'away your whole batch. To touch the project use delphi_config ' +
    '(add-unit, remove-unit, add-platform, add-searchpath, set-output).';

  SN_CHANGESET_STATUS_NOTE =
    '[CHSET-019] The ids are shown cut short on purpose: changesets can ' +
    'be seen but not touched without the full id, which only whoever ' +
    'opened it has. If you lost yours, open another one; the old one ' +
    'expires on its own after half an hour.';

  SN_CHANGESET_BEGUN_FMT =
    '[CHSET-020] CHANGESET %s opened. stage adds operations (one per ' +
    'call), preview resolves them, commit applies all or nothing.';

  SN_CHANGESET_STAGED_FMT =
    '[CHSET-021] STAGED %s of %s (operation %d of the changeset). ' +
    'Nothing touched yet. command=preview is MANDATORY before the ' +
    'commit, and it has to come AFTER the last operation you stage: if ' +
    'you stage anything else after the preview, preview again. If you ' +
    'get one wrong, command=unstage n=<number> removes it without ' +
    'throwing away the batch.';

  SN_CHANGESET_DISCARDED =
    '[CHSET-022] Changeset discarded. No file had been touched.';

  SN_CHANGESET_PREVIEW_OK =
    '[CHSET-023] Clean preview: every anchor resolves. commit applies ' +
    'all or nothing; if a file changes before the commit, the whole ' +
    'commit is refused.';

  SN_CHANGESET_PREVIEW_BAD =
    '[CHSET-024] There are unresolved operations (anchor NOT FOUND or ' +
    'AMBIGUOUS). Remove the failing one with command=unstage n=<the ' +
    'number you see above> and stage it again correctly (with atline if ' +
    'the anchor appears more than once): there is NO need to throw away ' +
    'the whole batch. commit stays blocked until a clean preview.';

  { Un parametro que no es de ese kind: se ignoraba en silencio (kind=create
    con old/new, kind=edit con content; sexta revision). }
  SR_CHANGESET_NO_ES_DE_KIND_FMT =
    '[CHSET-030 INVALID_PARAM] "%s" does not go with kind=%s (it would ' +
    'be ignored). Nothing was staged: kind=%s takes %s.';

  { ...y un parametro que no es del COMANDO: commit / preview con kind,
    path, old o n se ignoraban (octava revision). }
  SR_CHANGESET_NO_VA_CON_COMANDO_FMT =
    '[CHSET-031 INVALID_PARAM] "%s" does not go with command=%s (it would ' +
    'be ignored). Nothing was done: %s takes %s.';

  { Un commit que deja todo como estaba: decia COMMIT COMPLETE, "this is what
    changed" y las copias de siempre (sexta revision). Sin prometer "no
    backup": un create+delete del mismo fichero deja la copia del delete
    (septima revision). }
  SN_CHANGESET_SIN_CAMBIOS_FMT =
    '[CHSET-029] UNCHANGED: the %d operations leave every file exactly as ' +
    'it was, so nothing changed. The changeset is closed.';

  // los avisos del motor que dieron los pasos (revisor de la noche, M-6)
  SN_CHANGESET_AVISOS_FMT =
    '[CHSET-032] The engine warned while writing (the changes ARE written; ' +
    'read each one before going on):'#10'%s';

  SN_CHANGESET_COMMITTED_FMT =
    '[CHSET-025] COMMIT COMPLETE: %d operations applied to %d files. ' +
    'This is what changed:'#10 +
    '%s'#10 +
    'The per-file backups in __delphi-patch still exist as always.';

  // ---- delphi_components ----

  SD_COMPONENTS =
    'What this server''s RAD Studio has INSTALLED to program with: every ' +
    'component/design package REGISTERED in the IDE (Known Packages - what ' +
    'the IDE loads into its palette), whatever the channel (GetIt, a ' +
    'vendor installer, manual). Each line: the package description and its ' +
    '.bpl; disabled ones are marked, IDE plumbing excluded. Read-only: ' +
    'there is no install command; if a library you need is missing, say so ' +
    'with delphi_report. The base RTL units are always there and never ' +
    'appear here.';

  SP_COMPONENTS_FILTER =
    'Optional: only entries whose description or file name contains this ' +
    'text (case-insensitive), e.g. "FMX", "TMS", "JEDI".';

  SP_COMPONENTS_PLATFORM =
    'Optional: a platform ' +
    '(Win32|Win64|Linux64|Android64|OSX64|iOSDevice64...) to see instead ' +
    'the IDE''s Library Search Path FOR IT, expanded, plus the component ' +
    'roots other platforms register and this one does not - the list to ' +
    'walk when a build on a new platform fails with F2613 (then ' +
    'delphi_config add-searchpath to the Source folder).';

  SR_COMPONENTS_PLATFORM_FMT =
    '[COMP-008 INVALID_PARAM] Platform "%s" not recognized. Valid: %s.';

  SN_COMPONENTS_PLATFORM_HEAD_FMT =
    '[COMP-002] IDE Library Search Path for %s (RAD Studio %s): %d ' +
    'registered folders';

  SN_COMPONENTS_PLATFORM_COMPLETE_FMT =
    '[COMP-003] Every component registered on other platforms is also ' +
    'registered on %s.';

  SN_COMPONENTS_PLATFORM_MISSING_FMT =
    '[COMP-009] %d components registered on other platforms and NOT on ' +
    '%s (candidates when a build fails with F2613 "Unit X not found"):';

  SN_COMPONENTS_PLATFORM_HINT =
    '[COMP-004] A component without Lib\<platform> compiles from source: ' +
    'delphi_config command=add-searchpath platform=<platform> ' +
    'path=<root>\Source (the folder that holds the .pas files; look at ' +
    'it with delphi_list). If it only ships .dcu/.so for other ' +
    'platforms, it is no use for this one: delphi_report.';

  SR_COMPONENTS_MISSING =
    '[COMP-010 INTERNAL] No RAD Studio installation was found on the ' +
    'server - without an IDE there are no packages to list.';

  SN_COMPONENTS_NONE_FMT =
    '[COMP-005] No registered package contains "%s". Full list: call ' +
    'without filter.';

  SN_COMPONENTS_NOTE =
    '[COMP-006] These design packages are registered in the SERVER''s RAD ' +
    'Studio: their components and units are available to projects built ' +
    'here. Base RTL/VCL/FMX are always present and not listed. No ' +
    'install command exists by design - report a missing library with ' +
    'delphi_report.';

  SN_BUILD_ANDROID_NEW =
    '[BUILD-039] No .deployproj existed, so the standard Android ' +
    'deployment manifest was generated next to the project (generated ' +
    'AndroidManifest + styles/strings/colors, default icons and splash ' +
    'artwork, the compiled library), plus an ' +
    'AndroidManifest.template.xml seed and fallback version properties ' +
    'in the .dproj (package com.embarcadero.<project>, minSdk 23) when ' +
    'the project had none. Files the IDE Deployment Manager already ' +
    'wrote are never overwritten.';

  SN_BUILD_APK_NOTE =
    '[BUILD-040] This is the built .apk (debug-signed, sideloadable). ' +
    'msbuild does not install Android apps (DeviceId only auto-installs ' +
    'on iOS): put it on a device hanging off this server with delphi_adb ' +
    'command=install apk=<path> device=<serial>, open it with ' +
    'command=run app=<package>, and watch it with command=logcat.';

  // ---------------------------------------------------------------------
  // delphi_report (feedback channel - works at EVERY access level)
  // ---------------------------------------------------------------------
  SD_REPORT =
    'Report a problem, limitation or suggestion about THIS MCP server to ' +
    'its maintainers - whenever a tool refuses something you believe ' +
    'legitimate, an answer looks wrong, a message is confusing, or you had ' +
    'to work around a missing capability: that feedback is what fixes the ' +
    'server. Each report is its own timestamped markdown file (with the ' +
    'server version and date) in a reports folder next to the server; a ' +
    'stable "agent" id gives your reports their own subfolder. Available ' +
    'at EVERY access level, read-only included. Be concrete: what you ' +
    'tried, what happened, what you expected.';

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
    'go to a folder of that name, apart from other agents. Keep it STABLE. ' +
    'Letters, digits and dashes; anything else is normalized away.';

  SR_REPORT_EMPTY =
    '[REPORT-002 INVALID_PARAM] delphi_report needs "message" with the ' +
    'description of the problem. Say what you tried, what happened and ' +
    'what you expected.';

  // delphi_report is the ONE write a read-only (even anonymous) credential may
  // perform, so it is also the one place such a client could grow the server's
  // disk. A report is prose written by an agent: a generous cap still fits any
  // honest report - the field audit's longest was 45 KB - while turning "fill
  // the disk in one call" into something the operator would notice.
  SR_REPORT_TOO_BIG_FMT =
    '[REPORT-003 INVALID_PARAM] The report takes %d KB and the limit is %d KB. ' +
    'Tell the essentials (what you tried, what happened, what you ' +
    'expected) and split the rest into several reports: they add up, ' +
    'they do not overwrite each other.';

  // 500 informes del mismo tipo, titulo y segundo: no pasa en la vida real,
  // pero un bucle de nombres sin techo tampoco se deja abierto.
  SR_REPORT_NO_NAME =
    '[REPORT-004 INVALID_PARAM] No free name for the report was found in the ' +
    'reports folder. Change the "title" and retry.';

  SN_REPORT_OK_FMT =
    '[REPORT-005] THANKS - report saved as %s (v%s): %d characters of ' +
    'message, ending in "%s" - if that is not how yours ends, it was cut on ' +
    'the way: send the rest in another report.'#10 +
    'We will read it carefully together with the others. If you find ' +
    'more details, send another report: they add up, they do not ' +
    'overwrite each other.';

  // Mensajes que estaban en linea en DelphiLspMcp.dpr (paso 3c, 27-sep-2026)
  SL_SYS_READ_ONLY_MODE_READONLY =
    'Read-only mode (--readonly): mutating tools disabled.';

  SL_SYS_READY_CTRL_STOP =
    'Ready. Ctrl+C to stop.';

  // Mensajes que estaban en linea en Lsp.BuildRunner.pas (paso 3c, 27-sep-2026)
  SL_BUILD_DELPHI_BUILD_REFUSED_REDEFINES_FMT =
    'delphi_build: REFUSED "%s" - redefines reserved IDE property %s';

  // Mensajes que estaban en linea en Lsp.Guard.pas (paso 3c, 27-sep-2026)
  SN_GUARD_WORKSPACE_JAIL_INVALID_ROOTS =
    '[GUARD-007] Workspace jail: INVALID roots (fail-closed) - every ' +
    'disk-touching tool is refused. Check DELPHI_MCP_ROOTS (local ' +
    'launch).';

  SN_GUARD_WORKSPACE_JAIL_CERRADA_FMT =
    '[GUARD-031] Workspace jail: CLOSED (fail-closed) - every ' +
    'disk-touching tool is refused in the local mode: %s.';

  SN_GUARD_WORKSPACE_JAIL_NONE_MODO =
    '[GUARD-008] Workspace jail: NONE - trusted LOCAL mode (it only ' +
    'exists in a stdio process launched by the operator; every HTTP ' +
    'client comes in with a workspace token or gets 401).';

  { Dos formas que caian en GUARD-009 con un motivo que no era el suyo
    ("alternate data stream"; sexta revision). }
  SR_GUARD_PREFIJO_DISPOSITIVO_FMT =
    '[GUARD-022 INVALID_PARAM] "%s" uses a device or long-path prefix ' +
    '(\\?\ or \\.\): give the plain path.';
  SR_GUARD_UNIDAD_SIN_BARRA_FMT =
    '[GUARD-023 INVALID_PARAM] "%s": a unit needs a \ right after the ' +
    'colon (%s\...).';

  { Un comodin en una ruta: acababa en INTERNAL (upload SYS-006, textedit
    SYS-009, move MOVE-012 dejando copia y carpeta; septima revision). }
  SR_GUARD_COMODIN_FMT =
    '[GUARD-024 INVALID_PARAM] "%s" has a wildcard (* or ?): a path names ' +
    'ONE file or folder. To match several, use the mask parameter of the ' +
    'tool (pattern) where it has one.';

  { Un FICHERO con separador final (x.txt\): se leia como el fichero y fallaba
    dentro de Windows (INTERNAL), o se CREABA una carpeta con su nombre
    (septima revision). }
  SR_GUARD_BARRA_FINAL_FMT =
    '[GUARD-025 INVALID_PARAM] "%s" ends in a separator (\ or /), which ' +
    'names a FOLDER, and it is a FILE (or a file goes there): a file is ' +
    'named without it. Drop the separator at the end.';

  { Un nombre de mas de 255 caracteres: Windows no lo admite, y salia
    SYS-009 INTERNAL al escribir (octava revision). }
  SR_GUARD_NOMBRE_LARGO_FMT =
    '[GUARD-026 INVALID_PARAM] A name in the path has %d characters ' +
    '("%s..."), and Windows allows at most 255 in one name. Use a ' +
    'shorter name.';

  SR_GUARD_CONTROL_EN_RUTA_FMT =
    '[GUARD-032 INVALID_PARAM] The path contains control character %d ' +
    '(U+0000..U+001F). Use a path without control characters.';

  SR_GUARD_RUTA_CONTIENE_FUERA_UNIDAD_FMT =
    '[GUARD-009 INVALID_PARAM] The path "%s" contains ":" outside the drive ' +
    '(alternate data stream). Use a normal file name.';

  SR_GUARD_NOMBRE_EMPIEZA_TERMINA_PUNTO_FMT =
    '[GUARD-010 INVALID_PARAM] The name "%s" starts or ends with a space, ' +
    'or ends with a dot. Windows drops a trailing dot or space when it ' +
    'opens the file, so it would be a different name, and a leading ' +
    'space is almost always a slip.%s Ask for the exact name.';
  { La sugerencia de GUARD-010, solo si queda un nombre: "..." sugeria
    'Did you mean ""?' (octava revision). }
  SF_GUARD_QUIZAS_FMT =
    ' Did you mean "%s"?';

  { Un nombre reservado de Windows en la ruta (decima revision). }
  SR_GUARD_NOMBRE_RESERVADO_FMT =
    '[GUARD-027 INVALID_PARAM] "%s" is a name Windows reserves for a device ' +
    '(CON, PRN, AUX, NUL, COM1-9, LPT1-9), with or without an extension: ' +
    'in %s. Choose another name.';

  // Mensajes que estaban en linea en Lsp.Patch.pas (paso 3c, 27-sep-2026)
  SR_EDIT_EXTENSION_SOPORTADA_ESTA_TOOL_FMT =
    '[EDIT-032 INVALID_PARAM] Extension "%s" is not supported. This tool ' +
    'is only for Delphi files; for non-Delphi text (.md .py .html .js ' +
    '.ini ...) use delphi_textedit.';

  SR_EDIT_HISTORY_RECOVERY_SON_COPIAS =
    '[EDIT-033 DENIED] __history\ and __recovery\ are dead copies kept ' +
    'by the IDE. The live file is in the project folder.';

  SR_EDIT_CREATEUNIT_SOLO_CREA_UNITS =
    '[EDIT-034 INVALID_PARAM] createunit only creates units (.pas).';

  SR_EDIT_EXISTE_CREATEUNIT_JAMAS_SOBREESCRIBE_FMT =
    '[EDIT-035 DENIED] %s ALREADY EXISTS. createunit never overwrites.';

  SR_EDIT_IDENTIFICADOR_PASCAL_VALIDO_NOMBRE_FMT =
    '[EDIT-036 INVALID_PARAM] ''%s'' is not a valid Pascal identifier for a unit ' +
    'name.';

  SR_EDIT_BINARIO_FIRMA_TPF0_ENVOLTORIO_FMT =
    '[EDIT-037 DENIED] %s is a BINARY %s (TPF0 signature or $FF resource ' +
    'wrapper). It is not text and is not edited this way. Convert it to ' +
    'text with delphi_designer command=to-text (backup copy first, the ' +
    'same conversion the IDE does) and edit; delphi_read and ' +
    'delphi_designer already READ it on the fly without converting it.';

  { La regla de ida y vuelta (David, 9-oct-2026), en los escritores
    (Lsp.Patch.ReescrituraDenegada: los dos de Lsp.Patch y el del vault): los
    bytes del fichero no vuelven iguales al leerlos y escribirlos en su
    codificacion. Era "BOM de UTF-8 con el cuerpo roto", y solo en la entrada
    de delphi_edit. %s = el fichero, %s = su codificacion. }
  SR_EDIT_BYTES_NO_VUELVEN_FMT =
    '[EDIT-038 DENIED] %s is read as %s, but some of its bytes do not fit ' +
    'that encoding (a mixed or damaged file): writing it back would change ' +
    'bytes nobody touched, so it is left untouched. Reading it shows them ' +
    'as U+FFFD and names the first line (READ-007); fix the file in its ' +
    'editor (the IDE for a source), or restore a good copy.';

  SR_EDIT_HAY_COPIA_SOLO_PUEDO_FMT =
    '[EDIT-039 NOT_FOUND] There is no copy of %s in %s\. I can only restore ' +
    'what I copied myself.';

  SR_EDIT_INSERT_SOLO_FUENTES_PASCAL =
    '[EDIT-040 INVALID_PARAM] insert is only for Pascal sources, not for ' +
    'designer files.';

  SR_EDIT_INSERT_DEBE_SER_RUTINA =
    '[EDIT-041 INVALID_PARAM] insert must be "rutina-global" or "metodo". For ' +
    'statements inside a body use old/new (anchor on a line of the ' +
    'method).';

  SR_EDIT_MODO_INSERT_NECESITA_CODE =
    '[EDIT-042 INVALID_PARAM] insert mode needs "code" with the COMPLETE block ' +
    '(signature + begin..end;).';

  SR_EDIT_BLOQUE_TRAE_END_SOLO =
    '[EDIT-043 INVALID_PARAM] The block contains an ''end.''. There is only one ' +
    'end. and it belongs to the file: remove it from the block.';

  SR_EDIT_BLOQUE_TERMINA_END_SIN =
    '[EDIT-044 INVALID_PARAM] The block ends in ''end'' WITHOUT a semicolon ' +
    '(E2029). Add the '';'' to the final end.';

  SR_EDIT_ULTIMA_LINEA_BLOQUE_RUTINA_FMT =
    '[EDIT-045 INVALID_PARAM] The last line of the block is |%s| and a COMPLETE ' +
    'routine ends in ''end;''.';

  SR_EDIT_FIRMA_VIENE_CUALIFICADA_CLASE =
    '[EDIT-046 INVALID_PARAM] The signature comes QUALIFIED with the class. ' +
    'Pass it UNQUALIFIED; with insert:"metodo" the tool adds the prefix.';

  SR_EDIT_INSERT_METODO_APLICA_DPR =
    '[EDIT-047 INVALID_PARAM] insert:"metodo" does not apply to a .dpr (classes ' +
    'go in units). Create the unit with createunit and insert there.';

  SR_EDIT_ENCUENTRO_FINAL_CABECERA_USES =
    '[EDIT-048 DENIED] The end of the .dpr header/uses was not found, so ' +
    'there is no place to put the routine.';

  SR_EDIT_ENCUENTRO_FRONTERA_FINAL_UNIT =
    '[EDIT-049 DENIED] The boundary at the end of the unit was not found ' +
    '(neither a single ''initialization'' nor a single ''end.'').';

  SR_EDIT_INSERT_METODO_NECESITA_INCLASS =
    '[EDIT-050 INVALID_PARAM] insert:"metodo" needs "inclass" with the exact ' +
    'name of the class.';

  SR_EDIT_ENCUENTRO_CLASS_FMT =
    '[EDIT-051 NOT_FOUND] ''%s = class'' was not found in %s.';

  SR_EDIT_ENCUENTRO_END_CIERRE_CLASE_FMT =
    '[EDIT-052 DENIED] The closing ''end;'' of class %s was not found.';

  { La clase pedida no tiene cuerpo ('EMio = class(Exception);'): no hay
    donde escribir la declaracion. Se escribia dentro de un metodo de la
    clase siguiente, y la tool decia "las dos mitades" (medido el
    4-oct-2026, E2070). }
  SR_EDIT_CLASE_SIN_CUERPO_FMT =
    '[EDIT-119 DENIED] Class %s is declared WITHOUT a body on line %d (%s): ' +
    'there is no class block to put the method in. Give it a body first ' +
    '(the declaration line without its '';'', then the members and ' +
    '''end;'') and insert again. Nothing was written.';

  { La clase pedida abre y cierra en UNA linea ('TX = class(TObject) end;'):
    no hay linea dentro donde escribir. Leida por lineas, su 'end' era el de
    la clase siguiente (censo del 4-oct-2026). }
  SR_EDIT_CLASE_EN_UNA_LINEA_FMT =
    '[EDIT-120 DENIED] Class %s opens and closes on line %d (%s): there is ' +
    'no line inside it to put the method on. Put its ''end;'' on a line of ' +
    'its own first and insert again. Nothing was written.';

  SR_EDIT_EXISTE_ENTERO_DECLARACION_LINEA_FMT =
    '[EDIT-053 DENIED] %s.%s already exists IN FULL (declaration at line ' +
    '%d, implementation at line %d). insert:"metodo" does not duplicate: ' +
    'to change its body use old/new anchored on a line of the method; if ' +
    'you wanted an OVERLOAD, add its two halves with old/new.';

  SR_EDIT_EXISTE_IMPLEMENTACION_LINEA_PERO_FMT =
    '[EDIT-054 DENIED] The implementation %s.%s exists (line %d) but the ' +
    'class does not declare it - inconsistent file. Check it and add the ' +
    'declaration with old/new.';

  SR_EDIT_CLASE_TIENE_SECCION_OMITE_FMT =
    '[EDIT-055 INVALID_PARAM] Class %s has no ''%s'' section. Omit visibility or ' +
    'use one that exists.';

  SR_EDIT_DELETE_TRUE_NECESITA_OLD =
    '[EDIT-056 INVALID_PARAM] delete:true needs "old" with the exact line to ' +
    'delete (copied from delphi_read) - or, for a BLANK line, which has no ' +
    'text to copy, "atline" with its number and no "old".';

  // borrar una linea EN BLANCO (P3-L9): el ancla es la posicion y la
  // condicion de que ESA linea este en blanco (Lsp.Patch.LineaEnBlancoDenegada)
  SR_EDIT_LINEA_NO_EN_BLANCO_FMT =
    '[EDIT-123 INVALID_PARAM] delete:true without "old" removes the BLANK ' +
    'line that atline names, and line %d of %s is not blank:'#10'  %s'#10 +
    'Nothing was written. To delete a line with text, pass it in "old".';

  // un rango sin old (revisor de la noche, M-3): borraba de una linea en blanco
  // hasta toline lo que hubiera, sin un ancla de texto
  SR_EDIT_RANGO_SIN_OLD =
    '[EDIT-125 INVALID_PARAM] toline needs "old": its first line, copied ' +
    'from delphi_read. Without old, delete removes ONE blank line (atline); ' +
    'a range is never anchored on a number alone. Nothing was written.';

  SR_PATCH_OCURRENCIA_SIN_TEXTO_FMT =
    '[EDIT-126 INVALID_PARAM] Entry %d: "occurrence" counts the TEXT of ' +
    'an anchor, and it has no "old". A blank line has no text to count: ' +
    'delete it with its number in "atline". Nothing was written.';

  SR_EDIT_LINEA_EN_BLANCO_NO_EXISTE_FMT =
    '[EDIT-124 INVALID_PARAM] delete:true without "old" removes the BLANK ' +
    'line that atline names, and %s has %d lines: there is no line %d. ' +
    'Nothing was written.';

  SR_EDIT_DELETE_TRUE_LLEVA_NEW =
    '[EDIT-057 INVALID_PARAM] delete:true takes no "new": it removes the whole ' +
    'anchor line. To replace it use old+new without delete.';

  SR_EDIT_FALTAN_PARAMETROS_MODOS_OLD =
    '[EDIT-058 INVALID_PARAM] Missing parameters. Modes: old+new (edit) ' +
    '| edits (several at once) | fragment+atline+new | delete+old | ' +
    'insert+code (insert) | createunit | restore | adduses | removeuses. ' +
    'To read use delphi_read.';

  SR_EDIT_HAS_PASADO_OLD_PERO =
    '[EDIT-059 INVALID_PARAM] You passed "old" but not "new".';

  SR_EDIT_ANCLA_ESTA_VACIA_SOLO =
    '[EDIT-060 INVALID_PARAM] The anchor is empty or only spaces.';

  SR_EDIT_TU_ANCLA_LLEVA_CARACTER =
    '[EDIT-061 INVALID_PARAM] Your anchor contains the corruption character ' +
    'U+FFFD. You read the file with a generic tool that destroyed the ' +
    'accented characters. Read it again with delphi_read and copy the ' +
    'anchor from there.';

  SR_EDIT_LINEA_ESTA_ESE_ANCLA_FMT =
    '[EDIT-062 INVALID_PARAM] That anchor is not on line %d. Actual ' +
    'occurrences: %s. Read again with delphi_read.';

  // Mensajes que estaban en linea en Lsp.Scaffold.pas (paso 3c, 27-sep-2026)
  SR_CREATE_KIND_DEBE_SER_FORM =
    '[CREATE-021 INVALID_PARAM] kind must be form-vcl | form-fmx | frame-vcl | ' +
    'frame-fmx | datamodule.';

  // Mensajes que estaban en linea en Lsp.Service.pas (paso 3c, 27-sep-2026)
  SL_SYS_STARTING_WINDOWS_SERVICE_FMT =
    '%s v%s starting as a Windows Service';

  SL_SYS_LISTENING_FMT =
    'Listening on %s:%d%s';

  // Mensajes que estaban en linea en Lsp.TextEdit.pas (paso 3c, 27-sep-2026)
  SR_TEXT_FICHERO_DELPHI_FUENTES_DESIGNERS_FMT =
    '[TEXT-001 INVALID_PARAM] "%s" is a Delphi file. For sources and ' +
    'designers use delphi_edit; project files (.dproj) are maintained by ' +
    'the IDE / delphi_create.';

  SR_TEXT_ATLINE_NINGUNA_OCURRENCIAS_FMT =
    '[TEXT-002 INVALID_PARAM] atline=%d is none of the occurrences (%s).';

  SR_TEXT_DELETE_TRUE_NECESITA_OLD =
    '[TEXT-003 INVALID_PARAM] delete=true needs "old": the line to remove - ' +
    'or, for a BLANK line, "atline" with its number and no "old".';

  SR_TEXT_FALTA_ANCLA_OLD_ESTA =
    '[TEXT-004 INVALID_PARAM] The anchor (old) is missing. This tool does not ' +
    'rewrite whole files: one existing line + its replacement, or ' +
    'create=true for new files.';

  // Mensajes que estaban en linea en Mcp.Tools.Config.pas (paso 3c, 27-sep-2026)
  SN_CFG_BUILD_DELPHI_BUILD_PROJECT =
    '[CFG-073] To build: delphi_build {project, platform, config}. ' +
    'needsSDKForBuild=true: pull the SDK once with delphi_paserver ' +
    'get-sdk and build locally - no profile involved. ' +
    'needsProfileForDeploy=true: a PAServer profile is needed only for ' +
    'target=Deploy.';

  SR_CFG_ADD_PLATFORM_NECESITA_PLATFORM =
    '[CFG-074 INVALID_PARAM] Add-platform needs "platform" (Win64, ' +
    'Linux64, OSX64...)';

  SR_CFG_PUEDO_LEER_FRAMEWORK_DPROJ =
    '[CFG-075 INVALID_PARAM] The framework cannot be read from the ' +
    '.dproj; check the path.';

  SN_CFG_PLATAFORMA_ESTA_HABILITADA_PROYECTO_FMT =
    '[CFG-076] Platform %s is already enabled in the project. Build with ' +
    'delphi_build {platform:"%s"}.';

  SN_CFG_HABILITADA_PLATAFORMA_ESTABA_DECLARAD_FMT =
    '[CFG-077] ENABLED platform %s (it was declared, disabled). The IDE ' +
    'will fill it in when it opens the project; MSBuild already builds ' +
    'it. If it needs PAServer, set up the profile with delphi_paserver.';

  SR_CFG_PLATAFORMA_DELPHI_VALIDA_FMT =
    '[CFG-078 INVALID_PARAM] "%s" is not a valid Delphi platform.';

  SN_CFG_PLATAFORMA_ESTA_DECLARADA_PROYECTO_FMT =
    '[CFG-079] Platform %s is not declared in the project.';

  SN_CFG_DESHABILITADA_PLATAFORMA_QUEDA_DECLAR_FMT =
    '[CFG-080] DISABLED platform %s (it stays declared but inactive; ' +
    'add-platform re-enables it). Backup copy in __delphi-patch.';

  SN_CFG_SALIDA_BINARIOS_FIJADA_AHORA_FMT =
    '[CFG-081] Binary output set to "%s". Now:%s  DCC_ExeOutput = %s ' +
    '(before: %s)%s  DCC_DcuOutput = %s (before: %s)%sBackup copy in ' +
    '__delphi-patch. Verify with delphi_build; the IDE honors it when it ' +
    'opens the project.';

  SR_CFG_PLATAFORMA_DELPHI_VALIDA_VALIDAS_FMT =
    '[CFG-082 INVALID_PARAM] "%s" is not a valid Delphi platform. Valid: ' +
    '%s (or empty = all).';

  SR_CFG_DELPHI_CONFIG_NECESITA_PROJECT =
    '[CFG-083 INVALID_PARAM] delphi_config needs "project" (path of the ' +
    '.dproj)';

  SR_CFG_COMMAND_DEBE_SER_VIEW =
    '[CFG-084 INVALID_PARAM] command must be view | add-platform | ' +
    'remove-platform | set-output | set-version | set-sdk | set-profile ' +
    '| add-searchpath | remove-searchpath | add-deployfile | ' +
    'remove-deployfile | add-unit | remove-unit | add-requires | ' +
    'fix-references | add-project | remove-project (these last two, on a ' +
    '.groupproj)';

  // Mensajes que estaban en linea en Mcp.Tools.DelphiLsp.pas (paso 3c, 27-sep-2026)
  SR_LSP_MODE_DEBE_SER_SUMMARY =
    '[LSP-019 INVALID_PARAM] Mode must be "summary", "full" or empty ' +
    '(automatic).';

  SR_LSP_KIND_DEBE_SER_DEFINITION =
    '[LSP-020 INVALID_PARAM] kind must be definition | declaration | ' +
    'implementation.';

  // Mensajes que estaban en linea en Mcp.Tools.FileOps.pas (paso 3c, 27-sep-2026)
  SR_FILE_DELPHI_MOVE_NECESITA_DEST =
    '[FILE-017 INVALID_PARAM] delphi_move needs "dest" (destination path).';

  // Mensajes que estaban en linea en Mcp.Tools.PAServer.pas (paso 3c, 27-sep-2026)
  SN_PAS_WINDOWS_FETCH_RUN_SETUP =
    '[PAS-034] Windows: fetch and run the setup, then start PAServer.';

  SN_PAS_DOWNLOAD_PACKAGE_DELPHI_FETCH =
    '[PAS-035] Download a package with delphi_fetch (it returns a ' +
    'whole-file sha256 to verify), copy it to the target machine and run ' +
    'it there. The Platform Assistant then listens on port 64211 for ' +
    'this server to connect.';

  SN_PAS_WINDOWS_PLATFORMS_BUILD_NATIVELY =
    '[PAS-036] Windows platforms build natively here. The rest need ' +
    'PAServer on the target: get the installer with command=packages, ' +
    'run it there, then a profile/SDK links this server to it.';

  SN_PAS_ASIENTO_IDE_LEE_LISTA =
    '[PAS-037] The IDE seat is what the IDE reads for ITS list; the ' +
    '.profile is what paclient, MSBuild and this server use. The IDE ' +
    'loads that list AT STARTUP, so close it and open it again to see ' +
    'them.';

  // Mensajes que estaban en linea en Mcp.Tools.Styles.pas (paso 3c, 27-sep-2026)
  SR_STYLE_HAY_NINGUN_ESTILO_COMMAND_FMT =
    '[STYLE-027 NOT_FOUND] There is no style ''%s'' in %s (command=view lists ' +
    'them).';

  // Mensajes que estaban en linea en Mcp.Tools.Vault.pas (paso 3c, 27-sep-2026)
  SR_VAULT_FALTA_PATH_RUTA_RELATIVA =
    '[VAULT-010 INVALID_PARAM] Missing "path" (relative path inside the ' +
    'vault)';

  SR_VAULT_NOTA_MD_VAULT_SOLO_FMT =
    '[VAULT-011 INVALID_PARAM] "%s" is not a .md note. The vault only serves ' +
    'Markdown notes.';

  SR_VAULT_ESTA_CARPETA_EXCLUIDA_BACKUPS_FMT =
    '[VAULT-012 DENIED] "%s" is excluded from the vault (a .bak copy, or ' +
    'inside %s): it is not vault knowledge.';

  SN_VAULT_RESULTADOS_FMT =
    '[VAULT-040] %d result(s)%s:';

  SN_VAULT_SIN_RESULTADOS_RECUERDA_INDICE_FMT =
    '[VAULT-013] No results for "%s" (%s). Remember: the index ' +
    '(vault_read without path) says which notes exist and what they are ' +
    'for.%s';

  SR_VAULT_NOTA_EXISTE_VAULT_LOCALIZALA_FMT =
    '[VAULT-014 NOT_FOUND] The note "%s" does not exist in the vault. ' +
    'Find it with vault_search target=files.';

  SR_VAULT_NOTA_EXISTE_VAULT_APPEND_FMT =
    '[VAULT-015 NOT_FOUND] The note "%s" does not exist. vault_append ' +
    'only appends to existing notes; for a new note use vault_create.';

  SR_VAULT_ANCHOR_APARECE_NOTA_LEE =
    '[VAULT-016 NOT_FOUND] The anchor does not appear in the note. ' +
    'Read the note with vault_read and copy an EXACT fragment of it.';

  SR_VAULT_ANCHOR_APARECE_VARIAS_VECES =
    '[VAULT-017 INVALID_PARAM] The anchor appears SEVERAL times; use a ' +
    'longer fragment that is unique in the note.';

  SK_VAULT_ANADIDO_COPIA_PREVIA_FMT =
    '[VAULT-018] ADDED to %s (%s). Backup copy in %s.';

  SR_VAULT_FALTA_CONTENT_NOTA_NUEVA =
    '[VAULT-019 INVALID_PARAM] Missing "content" (the new note cannot be ' +
    'empty)';

  SR_VAULT_NOTA_EXISTE_VAULT_CREATE_FMT =
    '[VAULT-020 DENIED] The note "%s" ALREADY exists. vault_create never ' +
    'overwrites: use vault_append to add, or vault_patch to fix a ' +
    'fragment.';

  SK_VAULT_CREADA_NOTA_RECUERDA_ENLAZARLA_FMT =
    '[VAULT-021] CREATED note %s. Remember to link it from the matching ' +
    'index with [[wikilinks]] (vault_append on that index).';

  SR_VAULT_NOTA_EXISTE_FMT =
    '[VAULT-022 NOT_FOUND] The note "%s" does not exist.';

  SR_VAULT_OLD_TEXT_APARECE_NOTA =
    '[VAULT-023 NOT_FOUND] "old_text" does not appear in the note. ' +
    'Read the note with vault_read and copy the EXACT fragment (the line ' +
    'numbers are NOT part of the text).';

  SR_VAULT_OLD_TEXT_APARECE_VARIAS =
    '[VAULT-024 INVALID_PARAM] "old_text" appears SEVERAL times in the ' +
    'note; widen the fragment until it is unique.';

  SN_VAULT_MODIFICADA_SUSTITUCION_COPIA_PREVIA_FMT =
    '[VAULT-025] MODIFIED %s (1 replacement). Backup copy in %s.';

  // Mensajes que estaban en linea en Mcp.Tools.Workspace.pas (paso 3c, 27-sep-2026)
  SR_WS_PATTERN_DEBE_SER_MASCARA =
    '[WS-005 INVALID_PARAM] pattern must be ONE simple mask (*.style, *.ini, ' +
    'Galatea*.rc).';

  SR_WS_PATTERN_ADMITE_LLAVES_EXPANSION =
    '[WS-006 INVALID_PARAM] pattern does not accept braces {a,b} (shell ' +
    'expansion). Use ONE mask (*.pas) or several separated by ";" ' +
    '(*.pas;*.dfm).';

  SR_GIT_ADD_NEEDS_ARGS_PATHS =
    '[GIT-022 INVALID_PARAM] Add needs args (paths, or -A for everything)';

  SR_GIT_CLONE_NEEDS_REPOSITORY_URL =
    '[GIT-023 INVALID_PARAM] Clone needs the repository URL in the ' +
    '"message" parameter (the destination directory is "repo")';

  SR_GIT_CONFIG_ONLY_ACCEPTS_USER =
    '[GIT-024 INVALID_PARAM] Config only accepts user.name or user.email ' +
    'in args (the value goes in the "message" parameter)';

  SR_WS_RUTA_ARTEFACTOS_IDE_HISTORY =
    '[WS-007 DENIED] Path of IDE artifacts (__history, ' +
    '__recovery, Win32, dcu...): nothing is uploaded there.';

  // Mensajes que estaban en linea en UTrayMain.pas (paso 3c, 27-sep-2026)
  SL_SYS_MCP_SERVER_LISTENING_FMT =
    'MCP server listening on %s (%s v%s)';

  SL_SYS_TRAY_ICON_SERVER_RUNNING =
    'Tray icon = server running. Double-click it for this log.';

  // Mensajes que estaban en linea en Mcp.Tools.Vault.pas (paso 3c a mano, 27-sep-2026)
  SR_VAULT_NO_PUDO_LEER_NOTA_FMT =
    '[VAULT-026 INTERNAL] Could not read the note (%s)';

  SR_VAULT_FALTA_PATTERN =
    '[VAULT-027 INVALID_PARAM] Missing "pattern"';

  SR_VAULT_SUBCARPETA_NO_EXISTE_FMT =
    '[VAULT-028 NOT_FOUND] The subfolder "%s" does not exist in the vault';

  SR_VAULT_PATTERN_REGEX_INVALIDA_FMT =
    '[VAULT-029 INVALID_PARAM] "pattern" is not a valid regular ' +
    'expression (%s)';

  SR_VAULT_PATTERN_MASCARA_INVALIDA_FMT =
    '[VAULT-042 INVALID_PARAM] "pattern" is not a valid file mask (%s): ' +
    '* and ? are wildcards, [abc] a set of characters.';

  SR_VAULT_FALTA_CONTENT_APPEND =
    '[VAULT-030 INVALID_PARAM] Missing "content"';

  SR_VAULT_FALTA_OLD_TEXT =
    '[VAULT-031 INVALID_PARAM] Missing "old_text"';

  // Mensajes que estaban en linea en Mcp.Vault.Session.pas (paso 3c a mano, 27-sep-2026)
  SN_VAULT_BOOT_NO_PUDO_LEER_FMT =
    '[VAULT-032] (could not read: %s)';

  SN_VAULT_BOOT_NO_TIENE_FMT =
    '[VAULT-033] (this vault has no %s)';

  SN_VAULT_CONTINUA_READ_SIN_PATH =
    '[VAULT-034] (...) Continue with vault_read without path.';

  // Mensajes que estaban en linea en Mcp.Tools.Messages.pas (paso 3c a mano, 27-sep-2026)
  SR_MSGS_COMMAND_READ_CHECK =
    '[MSGS-005 INVALID_PARAM] Command must be read | check';

  // Mensajes que estaban en linea en Mcp.Tools.Report.pas (paso 3c a mano, 27-sep-2026)
  SL_REPORT_DELPHI_REPORT_FROM_FMT =
    'delphi_report: %s (%s) from "%s"';

  // Mensajes que estaban en linea en Mcp.Tools.Workspace.pas (paso 3c a mano, 27-sep-2026)
  SR_WS_DIR_NOT_FOUND_FMT =
    '[WS-008 NOT_FOUND] Directory not found: %s';

  { Una raiz o referencia a la que el servidor no llega AHORA (informe de
    Hermes, 5-oct-2026: una referencia en una letra sin montar salia listada
    como si estuviera, y cada tool contestaba "Directory not found" sin decir
    que no era un error de nombre ni de quien era el arreglo). La negativa la
    da la puerta de cada llamada cuando la LETRA no esta conectada; la lista,
    delphi_workspace. }
  SR_WS_RAIZ_NO_DISPONIBLE_FMT =
    '[WS-022 DENIED] %s is a root of this workspace, but the server ' +
    'cannot reach it right now: %s. It is not a typo and no tool can fix ' +
    'it - it is the operator''s (connect that drive on the server, bring ' +
    'the share back). Until then, work in the roots that are there: %s.';
  { Con su barra: "Z:\" es la forma que el enmascarador de salida convierte
    en srvz:\; la letra suelta delante de un espacio la deja, a proposito
    ("opcion C: haz esto"), y salia la letra REAL (medido con la bateria). }
  SF_WS_LETRA_NO_CONECTADA_FMT =
    'drive %s:\ is not connected on the server';
  SF_WS_CARPETA_RAIZ_NO_EXISTE =
    'its folder does not exist';
  SF_WS_NINGUNA_RAIZ_DISPONIBLE =
    'none - ask the operator';
  SN_WS_RAICES_NO_DISPONIBLES =
    '[WS-023] These roots are declared, but the server cannot reach them ' +
    'right now (the reason is next to each): calls on them fail, and it ' +
    'is not a typo - only the operator can bring them back. Work in the ' +
    'other roots; this list shows them until they are back.';

  SR_WS_EMPTY_QUERY =
    '[WS-009 INVALID_PARAM] Empty query';

  SN_WS_SIZE_DATE_UNAVAILABLE =
    '[WS-010] size/date unavailable (path too long?)';

  SR_GIT_MISSING_REPO =
    '[GIT-025 INVALID_PARAM] Missing repo';

  SR_GIT_DIR_NOT_FOUND_FMT =
    '[GIT-026 NOT_FOUND] Directory not found: %s';

  SR_GIT_SHELL_METACHARS_ARGS =
    '[GIT-027 INVALID_PARAM] Shell metacharacters are not allowed in args';

  SR_GIT_COMMIT_NEEDS_MESSAGE =
    '[GIT-028 INVALID_PARAM] Commit needs the "message" parameter';

  SR_GIT_CLONE_URLS_ACCEPTED =
    '[GIT-029 INVALID_PARAM] Only https/http/git/ssh URLs are accepted ' +
    'for clone';

  SR_GIT_SHELL_METACHARS_URL =
    '[GIT-030 INVALID_PARAM] Shell metacharacters are not allowed in the ' +
    'URL';

  SR_GIT_URL_NOT_ALLOWED =
    '[GIT-031 INVALID_PARAM] That URL is not allowed';

  SR_GIT_YA_ES_REPOSITORIO_FMT =
    '[GIT-032 DENIED] "%s" is already a git repository. Use pull ' +
    'to update it, or clone into another folder.';

  SR_GIT_CONFIG_NEEDS_VALUE =
    '[GIT-033 INVALID_PARAM] Config needs the value in the "message" ' +
    'parameter';

  { Un parametro que no es del comando: commit con path hacia un commit de
    TODO el indice, no de ese fichero (octava revision). }
  SR_GIT_NO_VA_CON_COMANDO_FMT =
    '[GIT-038 INVALID_PARAM] "%s" does not go with command=%s (it would ' +
    'be ignored). Nothing was done: %s takes %s (and args).';

  SR_GIT_UNKNOWN_COMMAND_FMT =
    '[GIT-034 INVALID_PARAM] Unknown command "%s". Allowed: status | ' +
    'diff | log | show | branch | switch | merge | stash | add | commit ' +
    '| init | push | tag | config | clone | pull | fetch | ls-remote | worktree | restore';

  SR_GIT_EXIT_FMT =
    '[GIT-036 DENIED] exit=%d - git ended with an error; its own answer ' +
    'follows and says why. A command that fails can still have changed ' +
    'the working tree (a merge or a stash pop with conflicts): look at ' +
    'git status before repeating it.'#10 +
    '%s';

  { Un servidor SIN git: CreateProcess no encuentra git.exe y la llamada
    acababa en SYS-006 "CreateProcess failed (2)", que no dice ni que falta
    ni de quien es el arreglo (medido el 30-sep-2026 en una maquina sin git
    instalado: init y status). INTERNAL: al servidor le falta una pieza.
    NO dice que la llamada este bien: sale en la primera pregunta a git,
    antes de las reglas de cada comando (un commit sin mensaje lo recibe
    igual). Ni que baste reiniciar: solo que un proceso no ve un PATH
    posterior a su arranque (revision de la 1.8.1). }
  SR_GIT_NO_HAY_GIT_FMT =
    '[GIT-050 INTERNAL] This server has no git: Windows did not find ' +
    'git.exe when the server tried to launch it (error %d), so no ' +
    'delphi_git command can run here. It does not depend on your call, ' +
    'and repeating it will not help: git has to be installed on the ' +
    'server machine, in the PATH the server process starts with (a ' +
    'running process keeps the PATH it was started with). Everything ' +
    'that is not delphi_git works as usual.';

  { El repo no puede activar programas ni esconderlos en includes locales. }
  SR_GIT_CONFIG_PROGRAMA_FMT =
    '[GIT-051 DENIED] Repository configuration key "%s" ' +
    'is not admitted by this server. The requested operation was not completed. ' +
    'Remove this local setting before using delphi_git; its value is never shown.';

  SR_GUARD_GIT_METADATA_FMT =
    '[GUARD-033 DENIED] "%s" is Git metadata (.git), or contains it. ' +
    'Only delphi_git may access repository metadata; file tools cannot read, ' +
    'write or copy it, including through links. A whole repository folder ' +
    'may move or go to recoverable trash inside the workspace, provided its ' +
    'metadata links stay inside the allowed locations.';

  { LA PUERTA DE LEER/ESCRIBIR (Lsp.Patch, decisions/puertas-diseno-2026-10-09):
    el fichero no esta en ninguno de los lugares que esa operacion puede tocar.
    %s = el fichero, %s = los lugares (SF_LUGAR_*, separados por comas). }
  SR_GUARD_FUERA_DE_LUGARES_FMT =
    '[GUARD-034 DENIED] %s is outside the places the server may use for ' +
    'this (%s). It is judged where it really lies: a junction or symbolic ' +
    'link on the way - or, to write or delete, the file itself being one - ' +
    'takes it outside. Nothing was read or written.';
  SR_BORRA_JAULA_FMT =
    '[GUARD-035 DENIED] %s is a file of the workspace: there a file goes ' +
    'to its trash (delphi_delete), never through the delete of the server''s ' +
    'own places. Nothing was deleted.';
  SF_LUGAR_IDE =
    'the IDE''s own folders: its installation, its BDS data folder, its SDK ' +
    'folder and the sysroot of every SDK it has registered';
  SF_LUGAR_IDE_ESCRIBIR =
    'the IDE''s data folder, its SDK folder and the sysroots its SDK Manager ' +
    'registers (never its installation)';
  SF_LUGAR_CASA =
    'the server''s own folders: its cache, the agents'' mailboxes and the reports';
  SF_LUGAR_TEMPORAL =
    'the server''s temporary folder';
  SF_LUGAR_VAULT =
    'the vault';
  SF_LUGAR_BIBLIOTECA =
    'the IDE''s library: its installation, its GetIt catalogs and its ' +
    'Library Search Path (read only)';

  { El endpoint LFS no es una clave local que el agente tenga que quitar. }
  SR_GIT_LFS_ENDPOINT_FMT =
    '[GIT-061 DENIED] The LFS endpoint for remote "%s" is not allowed. ' +
    'Network endpoints are decided by the operator''s GitRemotes; directory ' +
    'endpoints must stay in the allowed workspace locations. The endpoint ' +
    'value is never shown.';

  SR_GIT_CONFIG_NO_VERIFICABLE =
    '[GIT-052 DENIED] The local repository configuration could not be ' +
    'verified. The requested operation was not completed. Repair the repository ' +
    'configuration before repeating the call.';

  SL_GIT_NETWORK_FMT =
    'delphi_git: NETWORK %s repo=%s %s';

  SN_GIT_PISTA_CONFIGURA_IDENTIDAD =
    '[GIT-035] Hint: set the repo identity and repeat: delphi_git ' +
    'command=config args=user.name message=<name> and then ' +
    'command=config args=user.email message=<email>.';
  { git que no se fia del dueno de la carpeta ("detected dubious ownership",
    tipico de un recurso de red o un NAS): su propio consejo es un git config
    --global que ninguna tool puede ejecutar, y el agente se quedaba ahi
    (Hermes, 5-oct-2026, en el NAS de la VM). }
  SN_GIT_PISTA_PROPIEDAD_DUDOSA =
    '[GIT-057] git refuses this repository because its folder belongs to ' +
    'another account than the one this server runs as (usual on a network ' +
    'share or a NAS). The fix is the OPERATOR''s, on the server: the ' +
    'safe.directory line git printed above, in the GLOBAL git config of ' +
    'the server''s account. No tool writes that setting - it lives outside ' +
    'the workspace, and command=config only sets user.name/user.email of ' +
    'the repo - so ask the operator (delphi_report) and work in another ' +
    'repository meanwhile.';

  SN_WS_READONLY_TERRITORY =
    '[WS-011] Read-only territory: RTL/VCL/FMX sources, installed ' +
    'components and SDKs. Reading tools may enter it; writing tools ' +
    'never can.';

  SR_WS_NO_ROOT_GIVEN =
    '[WS-012 INVALID_PARAM] No root given and no workspace roots ' +
    'configured. Pass "root", or configure [Workspace.<name>] Roots in ' +
    'settings.ini next to the server exe (or the DELPHI_MCP_ROOTS ' +
    'environment variable).';

  SR_WS_NO_EXISTE_FMT =
    '[WS-013 NOT_FOUND] %s does not exist';

  SR_WS_OFFSET_NEGATIVO =
    '[WS-014 INVALID_PARAM] Negative offset';

  SR_WS_OFFSET_MAS_ALLA_FINAL_FMT =
    '[WS-015 INVALID_PARAM] offset beyond the end (size=%d)';

  SR_WS_FALLO_COPIA_SEGURIDAD_FMT =
    '[WS-016 DENIED] The copy of the previous content could not be taken, ' +
    'so NOTHING was written (the file is as it was): %s';

  SR_WS_OFFSET_FICHERO_NO_EXISTE =
    '[WS-017 INVALID_PARAM] offset>0 but the file does not exist yet; start ' +
    'with offset=0';

  SR_WS_OFFSET_ENVIA_EN_ORDEN_FMT =
    '[WS-018 INVALID_PARAM] offset %d beyond the current end (size=%d); ' +
    'send the chunks IN ORDER';

  SN_WS_LINUX_EXECUTABLES_FMT =
    '[WS-019] %d Linux executable(s) inside. A zip made on Windows keeps ' +
    'no Unix permissions, so after unzipping on the target they are NOT ' +
    'executable: run chmod +x <file> once (a Deploy through PAServer ' +
    'does not have this problem).';

  SN_WS_DOWNLOAD_WITH_FETCH =
    '[WS-020] download it with delphi_fetch, sha256-verified: a zip over ' +
    '1 MB answers with a download link (one curl) and no inline base64, ' +
    'a smaller one comes inline - do NOT set maxbytes';

  // Mensajes que estaban en linea en Mcp.Tools.DelphiLsp.pas (paso 3c a mano, 27-sep-2026)
  SN_LSP_NO_SETTINGS_WARNING =
    ' [LSP-021] [warning: no .delphilsp.json project settings found for ' +
    'this file - semantic answers may be null. Generate one in the IDE ' +
    '(Code Insight > Generate LSP config + Reload LSP Server).]';

  { Lo que el proyecto le haria ver al motor FUERA de lo que la sesion puede
    leer (David, 9-oct-2026: "recortar y negar", coherente con LSP-014): las
    carpetas de su search path salen de los ajustes del motor (LSP-037, la
    nota), una definicion que aun cae fuera se niega (LSP-038) y completion y
    signature, que contestan nombres sin decir de donde, se niegan si el .dpr
    nombra units de fuera (LSP-039). Medido el 9-oct: completion daba el VALOR
    de una constante de fuera, hover su firma y su ruta. }
  SN_LSP_RECORTE_FMT =
    ' [LSP-037] %d folder(s) of this project''s search path are outside ' +
    'what this session may read: the engine does not see them, so their ' +
    'units read here as not found (diagnostics) and their symbols get no ' +
    'answer. delphi_build compiles the project as it is. To work with those ' +
    'units, bring them into the workspace or ask the operator for that root.';
  SR_LSP_DEF_FUERA_FMT =
    '[LSP-038 DENIED] "%s" resolves to a definition OUTSIDE this workspace ' +
    '(a unit this session may not read), so I do not show where it is nor ' +
    'what it declares - the same rule as delphi_references (LSP-014). Two ' +
    'things cause it: a unit the project''s .dpr names with a path outside ' +
    'the roots (bring that unit into the workspace or take it out of the ' +
    'project), or an UNCONFIGURED unit (no .delphilsp.json or .dproj nearby), ' +
    'which the engine resolves against another unit with the same name that ' +
    'it indexed before (work on its project, with its .dproj next to it).';
  SR_LSP_NOMBRES_FUERA_FMT =
    '[LSP-039 DENIED] This project''s .dpr names units OUTSIDE this workspace ' +
    '(%s). %s answers names without saying where they come from, so it could ' +
    'list what those units declare, and I do not answer it for this project - ' +
    'the same rule as delphi_references (LSP-014). Bring those units into the ' +
    'workspace or take them out of the project.';

  SR_LSP_ERROR_FMT =
    '[LSP-022 INTERNAL] LSP error: %s';

  { El motor revento (-32603) con un fichero SIN proyecto al lado: medido el
    8-oct-2026, DelphiLSP fuera de un proyecto no resuelve TArray<string> y
    cae con dos sobrecargas de igual aridad que solo difieren en eso; junto
    a su .dproj contesta. Se dice; reintentar es cosa del agente. }
  SN_LSP_HINT_SIN_PROYECTO =
    ' [LSP-036] [hint: the engine failed on this file OUTSIDE a project; ' +
    'next to its .dproj it usually answers]';

  SN_LSP_HINT_INSIDE_CALL =
    ' [LSP-023] [hint: the position must be INSIDE the call parentheses, ' +
    'right after ( or ,]';

  SN_LSP_HINT_HOVER_USAGES =
    ' [LSP-024] [hint: hover only answers on usages, not on declarations]';

  // Mensajes que estaban en linea en Mcp.Tools.Designer.pas (paso 3c a mano, 27-sep-2026)
  // Mensajes que estaban en linea en Mcp.Tools.Styles.pas (paso 3c a mano, 27-sep-2026)
  SR_STYLE_BRCC_NO_ENCONTRADO_FMT =
    '[STYLE-028 INTERNAL] brcc32.exe (the resource compiler of RAD ' +
    'Studio) is not in %s: the installation on this server is ' +
    'incomplete. Tell the operator with delphi_report.';

  SR_STYLES_BUILD_CONVERT_FMT =
    '[STYLE-039 DENIED] %d of %d styles did not convert ' +
    '(converted[].error says why): the .rc was not compiled, so nothing ' +
    'new is embedded until they do.';

  SR_STYLES_BUILD_RC_FMT =
    '[STYLE-040 DENIED] %s did not compile, so there is no new .res to ' +
    'embed. brcc32 said:'#10 +
    '%s';

  SR_STYLE_COMMAND_DEBE_SER =
    '[STYLE-029 INVALID_PARAM] Command must be view | get | set | clone ' +
    '| delete | lint | build';

  // Mensajes que estaban en linea en Mcp.Tools.Config.pas (paso 3c a mano, 27-sep-2026)
  SR_CFG_SECTION_DEBE_SER_SUMMARY =
    '[CFG-085 INVALID_PARAM] Section must be summary | platforms | ' +
    'searchpaths | deploy | units | all';

  SK_CFG_ANADIDA_PLATAFORMA_DPROJ_FMT =
    '[CFG-086] ADDED platform %s to the .dproj (<Platforms> block). The ' +
    'IDE will fill in its PropertyGroups when it opens the project; for ' +
    'a simple project MSBuild already builds it. Verify with ' +
    'delphi_build {platform:"%s"}. If it needs PAServer, set up the ' +
    'profile with delphi_paserver.';

  SR_CFG_NO_ENCUENTRO_PROPERTYGROUP_BASE =
    '[CFG-087 DENIED] The base PropertyGroup ("$(Base)") of the ' +
    '.dproj was not found; open the project once in the IDE and retry.';

  SR_CFG_NO_ENCUENTRO_PROPERTYGROUP_FMT =
    '[CFG-088 DENIED] The PropertyGroup %s of the .dproj was not ' +
    'found.';

  SR_CFG_NO_PUDE_GENERAR_MANIFIESTO_FMT =
    '[CFG-089 INTERNAL] Could not generate the deployment manifest: ' +
    '%s';

  SR_CFG_NO_EXISTE_NO_PUDO_GENERAR_FMT =
    '[CFG-090 NOT_FOUND] %s does not exist and could not be generated.';

  SR_CFG_NO_ENCUENTRO_PROPERTYGROUP_DE_FMT =
    '[CFG-091 DENIED] The PropertyGroup of %s was not found in ' +
    'the .dproj';

  SR_CFG_QUEDO_INCONSISTENTE_PLATFORMSDK =
    '[CFG-092 INTERNAL] The .dproj was left inconsistent when ' +
    'removing the previous PlatformSDK';

  SR_CFG_QUEDO_INCONSISTENTE_PROFILE =
    '[CFG-093 INTERNAL] The .dproj was left inconsistent when ' +
    'removing the previous Profile';

  SR_CFG_NO_EXISTE_PROYECTO_FMT =
    '[CFG-094 NOT_FOUND] The project %s does not exist';

  // Mensajes que estaban en linea en Mcp.Tools.PAServer.pas (paso 3c a mano, 27-sep-2026)
  SN_PAS_LINUX_FETCH_TAR_FMT =
    '[PAS-038] Linux: fetch, then `tar xzf %s && cd PAServer-*` and run ' +
    'it KEEPING STDIN OPEN if headless: `sh -c ''sleep infinity | ' +
    './paserver -port=64211 -password=<pwd>''` (listens on 64211). ' +
    'Warnings: `./paserver &` with stdin at EOF spins its prompt at ' +
    '100%% CPU (keep the sleep pipe); and -passfile with a plain-text ' +
    'password was rejected on login in the field - pass -password inline ' +
    'instead, and keep the process supervised.';

  SN_PAS_PROFILES_EN_DISCO =
    '[PAS-039] profiles = the .profile files on disk (what paclient, ' +
    'MSBuild and the tools of this server use). ideRegistrySeats = the ' +
    'RemoteProfiles keys in the registry, where the IDE gets ITS list ' +
    'from. If a name is in one and not in the other, that explains what ' +
    'the IDE shows or fails to show.';

  SN_PAS_NO_CONNECTION_PROFILES_SDKS =
    '[PAS-040] No connection profiles or SDKs yet. They are created ' +
    'against a running PAServer on the target machine.';

  SR_PAS_PACLIENT_EXIT_FMT =
    '[PAS-041 INTERNAL] Paclient exit %d: %s';

  SR_PAS_NO_PUDE_BORRAR_PERFIL_FMT =
    '[PAS-042 INTERNAL] Could not delete the profile: %s';

  SN_PAS_TAMBIEN_CARPETA_VACIA_SDKS =
    ' [PAS-043] Also its empty folder in SDKs.';

  { Lo que el servidor borra o pisa del IDE se copia antes en su cache (la
    puerta de escribir, Lsp.Patch; David, 9-oct-2026). %s = la copia. }
  SN_PAS_COPIA_DEL_IDE_FMT =
    ' [PAS-058] A copy of it was kept first at %s: the server itself never ' +
    'deletes or overwrites a file of the IDE without one (what paclient ' +
    'brings into a sysroot is paclient''s).';

  SN_PAS_TOTALFILES_TOTALBYTES_COUNT =
    '[PAS-044] totalFiles/totalBytes count what was copied in THIS run. ' +
    'The pull is incremental: over a sysroot already on disk it brings ' +
    'only what changed on the target, so a small number - or zero, ' +
    '"already up to date" - is the normal answer of a re-run, not an ' +
    'empty SDK.';

  SR_PAS_NO_PUDE_BORRAR_FMT =
    '[PAS-045 INTERNAL] Could not delete %s: %s';

  // Mensajes que estaban en linea en Mcp.Tools.Adb.pas (paso 3c a mano, 27-sep-2026)
  SN_ADB_LOGCAT_VACIO_CONTENGAN_FMT =
    '[ADB-022] (logcat empty: no lines containing "%s")';

  SN_ADB_LOGCAT_VACIO_SIN_LINEAS =
    '[ADB-025] (logcat empty: no lines)';

  SR_ADB_NO_EXISTE_APK_FMT =
    '[ADB-023 NOT_FOUND] The .apk does not exist: %s';

  SK_ADB_TAP_EN_FMT =
    '[ADB-024] TAP at (%d,%d) %s';

  // Mensajes que estaban en linea en Mcp.Tools.Desktop.pas (paso 3c a mano, 27-sep-2026)
  SN_DESK_COLOCAR_CAPTURA_BAJADA_FMT =
    '[DESK-019] could not place the downloaded capture: %s';

  SN_DESK_MIDE_PIXEL_SOBRE_IMAGEN =
    '[DESK-020] measure the pixel ON this image and pass it to ' +
    'command=tap; fetch it with download or delphi_fetch. Once it is ' +
    'fetched WHOLE it is deleted from the server: if you need it again, ' +
    'ask for another capture (one requested with out= is not deleted)';

  // Mensajes que estaban en linea en Lsp.Imagen.pas (paso 3c a mano, 27-sep-2026)
  SN_CAPT_RECORTE_FUERA_CAPTURA_FMT =
    '[CAPT-007] the crop falls outside the capture (%dx%d)';

  SN_CAPT_NO_PUDE_RECORTAR_FMT =
    '[CAPT-008] could not crop the capture: %s';

  SN_CAPT_NO_PUDE_ESCALAR_FMT =
    '[CAPT-009] could not scale the capture: %s';

  // Mensajes que estaban en linea en Lsp.Guard.pas (paso 3c a mano, 27-sep-2026)
  SL_GUARD_MISMO_VALOR_TOKEN_FMT =
    SL_MARCA_AVISO +
    ': [Workspace.%s] has the SAME value in Token= and ReadOnlyToken=: ' +
    'there is no telling whether whoever comes in may write. CLOSED ' +
    '(fail closed) until they differ.';

  SL_GUARD_COMPARTEN_UN_TOKEN_FMT =
    SL_MARCA_AVISO +
    ': [Workspace.%s] and [Workspace.%s] share a token (copy-paste): ' +
    'with the same secret there is no telling which jail it opens. BOTH ' +
    'stay CLOSED (fail closed) until each one has its own.';

  SL_GUARD_SECCION_DOS_VECES_CERRADO_FMT =
    SL_MARCA_AVISO +
    ': section [%s] appears TWICE in settings.ini and the ini only reads ' +
    'the first one. That workspace stays CLOSED (fail closed) until ' +
    'there is only one.';

  SL_GUARD_SECCION_DOS_VECES_FUSIONALAS_FMT =
    SL_MARCA_AVISO +
    ': section [%s] appears TWICE in settings.ini and the ini only reads ' +
    'the first one: merge them.';

  SL_GUARD_REPITE_CLAVE_CERRADO_FMT =
    SL_MARCA_AVISO +
    ': [%s] repeats the key %s and the ini only reads the first one. ' +
    'That workspace stays CLOSED (fail closed) until the key appears ' +
    'only once.';

  SL_GUARD_REPITE_CLAVE_IGNORA_FMT =
    SL_MARCA_AVISO +
    ': [%s] repeats the key %s: the ini only reads the first one and the ' +
    'second is silently ignored.';

  SL_GUARD_ROOTS_NO_PARSEA_FMT =
    SL_MARCA_AVISO +
    ': [Workspace.%s] Roots= has no entry that could be loaded: that ' +
    'workspace admits NOBODY (fail closed).';

  { La version de Delphi es del SERVIDOR (David, 5-oct-2026): la de un
    workspace ya no se lee, y se dice al arrancar en vez de callarlo. }
  SL_GUARD_DELPHIVERSION_EN_WORKSPACE_FMT =
    SL_MARCA_AVISO +
    ': [Workspace.%s] DelphiVersion= is no longer read: the Delphi ' +
    'version belongs to the whole server - [Server] DelphiVersion=. For ' +
    'another version, run another server from its own folder.';

  { Las claves RETIRADAS de un workspace: no hacen nada, y el arranque lo dice
    en vez de callarlo (11.1 de la 1.18.0; Lsp.Settings.CLAVES_RETIRADAS). La
    vieja seccion [Security] NO se nombra: desde la 0.98 "ni autentica, ni
    avisa, ni existe" (test_round24 A4b). }
  SL_GUARD_CLAVE_RETIRADA_FMT =
    SL_MARCA_AVISO +
    ': [%s] %s= is no longer read (gone in %s): it does nothing - remove it.';

  { [Server] DelphiUpdate= con otra forma que numero.numero: se ignora. }
  SL_GUARD_DELPHIUPDATE_MAL_FMT =
    SL_MARCA_AVISO +
    ': [Server] DelphiUpdate=%s is not an update like 13.1 or 13.2: ' +
    'ignored, as if it were not there.';

  SL_GUARD_SIN_TOKEN_IGNORADA_FMT =
    SL_MARCA_AVISO +
    ': [Workspace.%s] has no Token= and no ReadOnlyToken=: section ' +
    'IGNORED. The key is Token= (AuthToken= also works as an alias).';

  SL_GUARD_WORKSPACE_SIN_PUNTO =
    SL_MARCA_AVISO +
    ': the section [Workspace] (with no dot) NO longer exists and is ' +
    'IGNORED entirely: its Roots, its tokens and its permissions count ' +
    'for nothing. Since v0.98 nothing is global - rename it to ' +
    '[Workspace.<name>] and give it a Token=.';

  SL_GUARD_WORKSPACE_MAL_ESCRITO_FMT =
    SL_MARCA_AVISO +
    ': section [%s] looks like a misspelled workspace and is IGNORED. ' +
    'The format is [Workspace.<name>] (with the dot).';

  { Una entrada de Roots / ReadOnlyRoots / ReadOnlyPaths / VaultPath que el
    cargador dejo fuera: no parsea, o no es una ruta con letra. %s: la clave
    ('[Workspace.X] Roots=', 'DELPHI_MCP_ROOTS') y la entrada como se escribio. }
  SL_GUARD_SITIO_NO_CARGADO_FMT =
    SL_MARCA_AVISO +
    ': %s has an entry that is NOT loaded, %s: it does not parse, or it ' +
    'is not a path with a drive letter. A place is declared by its drive ' +
    'letter (D:\...), never by a network or a device path. For a share, ' +
    'map it to a letter with "reconnect at sign-in" and declare the place ' +
    'by that letter: at startup the server tries to connect it for itself.';

  SL_GUARD_PROTECCION_NO_CARGADA_FMT =
    SL_MARCA_AVISO +
    ': %s has an entry that is NOT loaded, %s: it does not parse, or it ' +
    'is not a path with a drive letter (a place is declared by its drive ' +
    'letter, never by a network or a device path). That key says what ' +
    'must not be written, and without the entry it could be: its ' +
    'workspace - or, for an entry of the environment, the local mode of ' +
    'this process - admits NOBODY (fail closed) until the entry is fixed ' +
    'or removed.';

  { Una entrada de ReadOnlyPaths FUERA de todas las raices de su workspace (y
    de sus referencias): se carga, pero para sus agentes ni abre ni protege
    nada. %s: la clave ('[Workspace.X] ReadOnlyPaths=',
    'DELPHI_MCP_READONLY_PATHS'), la entrada ya completa, y la clave que SI
    abre para leer, como se llama alli ('ReadOnlyRoots',
    'DELPHI_MCP_READONLY_ROOTS'). No dice "no la leen": la zona de
    biblioteca se lee igual (primera revision de la 1.9.1). }
  SL_GUARD_SOLO_LECTURA_FUERA_FMT =
    SL_MARCA_AVISO +
    ': %s has an entry outside every root of its workspace, %s. ' +
    'ReadOnlyPaths marks as read-only what is INSIDE the roots: for the ' +
    'agents of that workspace this entry neither opens nor protects ' +
    'anything. To let them read a folder outside their roots, and never ' +
    'write it, the key is %s.';

  // Las letras de red de los sitios declarados, al arrancar (Lsp.NetDrives)
  SL_NET_LETRA_CONECTADA_FMT =
    'Network drive %s: was not connected for this process: connected to %s ' +
    '(this account''s persistent mapping, HKCU\Network\%s) in %d ms.';

  SL_NET_LETRA_YA_CONECTADA_FMT =
    'Network drive %s: was not connected for this process when the server ' +
    'looked, and it is now: something else connected it meanwhile.';

  SL_NET_LETRA_NO_CONECTA_FMT =
    SL_MARCA_AVISO +
    ': network drive %s: is not connected for this process, and connecting ' +
    'it to %s (this account''s persistent mapping, HKCU\Network\%s) failed ' +
    'after %d ms with Windows error %d (%s). Declared on it: %s. %s';

  { ...y lo que sigue, segun el error: solo se reintenta el que dice que la
    red o el recurso no estan. }
  SF_NET_SE_REINTENTA =
    'Windows says the network or the share is not there: the server keeps ' +
    'trying in the background and says here when it connects.';

  SF_NET_NO_SE_REINTENTA =
    'That is not the error of a network that is not there yet, so the ' +
    'server does not try again: fix it and restart the server.';

  SL_NET_LETRA_SIN_MAPEO_FMT =
    SL_MARCA_AVISO +
    ': drive %s: does not exist for this process, and HKCU\Network\%s ' +
    'names no share for it (this account has no persistent network ' +
    'mapping of that letter). Declared on it: %s. A network drive belongs ' +
    'to the logon session that connected it; one mapped with "reconnect ' +
    'at sign-in" is recorded for the account, and at startup the server ' +
    'tries to connect it for itself.';

  SL_NET_SITIO_ENTRA_FMT =
    'Network drive %s: %s is reachable (%d ms).';

  SL_NET_SITIO_NO_ENTRA_FMT =
    SL_MARCA_AVISO +
    ': %s, on network drive %s:, could not be opened: Windows error %d ' +
    '(%s), after %d ms.';

  SL_NET_PLAZO_FMT =
    SL_MARCA_AVISO +
    ': checking the drive letters (%s) of the declared places did not ' +
    'finish in %d s. The startup goes on without waiting for it; the check ' +
    'goes on in the background, and what it finds will be said here.';

  SL_NET_REVISION_FALLO_FMT =
    SL_MARCA_AVISO +
    ': checking the drive letters of the declared places failed: %s: %s';

  SL_NET_PURGA_FMT =
    'Temporary folders under %s, on a network drive, were cleaned apart ' +
    'from the startup: %d found, in %d ms. What was created or written ' +
    'there in the last hour is left: a server on another machine may be ' +
    'using it.';

  SR_GUARD_RUTA_INVALIDA_FMT =
    '[GUARD-011 INVALID_PARAM] Invalid path: %s';

  SR_GUARD_RUTA_VACIA =
    '[GUARD-018 INVALID_PARAM] No path given: the path parameter of this ' +
    'call (path, root, project, dest...) is empty or missing. Pass an ' +
    'absolute path, as delphi_workspace and the listings return it.';

  SR_GUARD_FICHERO_EN_RUTA_FMT =
    '[GUARD-019 INVALID_PARAM] %s cannot be created: %s is a FILE, not a ' +
    'folder. Choose another path.';

  SR_GUARD_FICHERO_EN_CARPETA_SERVIDOR_FMT =
    '[GUARD-020 DENIED] %s is a FILE where the server keeps its own ' +
    'folder (the recoverable copies or its temporary files): nothing can ' +
    'be written next to it until that file is renamed or removed. If ' +
    'your tools cannot, report it (delphi_report).';

  SR_GUARD_RUTA_RELATIVA_FMT =
    '[GUARD-021 INVALID_PARAM] "%s" is a RELATIVE path: this server ' +
    'takes absolute paths, inside its roots (%s). Repeat with the full ' +
    'path.';

  { De 233 a 259 caracteres una escritura moria como SYS-009 INTERNAL con las
    carpetas ya creadas (novena revision, R9): la medida, a la entrada. }
  SR_GUARD_RUTA_LARGA_FMT =
    '[GUARD-028 INVALID_PARAM] The path is %d characters long (measured on ' +
    'its long form) and this server writes up to %d (Windows MAX_PATH minus ' +
    'the atomic writer''s temporary suffix). Reading it is fine; to write, ' +
    'use a shorter path.';

  // Mensajes que estaban en linea en Lsp.BuildRunner.pas (paso 3c a mano, 27-sep-2026)
  SL_BUILD_DELPHI_BUILD_REFUSED_FMT =
    'delphi_build: REFUSED "%s" - %s';

  SL_BUILD_DELPHI_BUILD_TARGET_FMT =
    'delphi_build: BUILD "%s" %s/%s target=%s%s';

  // Mensajes que estaban en linea en Lsp.Patch.pas (paso 3c a mano, 27-sep-2026)
  SR_EDIT_FICHERO_BINARIO_NUL_FMT =
    '[EDIT-063 DENIED] %s is a BINARY file (NUL byte in the first 64 ' +
    'KB): it cannot be read as numbered text. To download it use ' +
    'delphi_fetch (or the download field of /files).';

  SN_EDIT_RECORTADO_EN_LINEA_FMT =
    '[EDIT-064] ... truncated at line %d of %d. Ask for another range ' +
    'with fromline/toline.';

  SR_EDIT_CARPETA_COPIAS_SEGURIDAD_FMT =
    '[EDIT-065 DENIED] %s\ is the backup folder of this tool. Copies, ' +
    'not live files: this tool does not edit them (restore brings one ' +
    'back). The live file is one level up.';

  SR_EDIT_AL_CODIFICAR_CONTENIDO_FMT =
    '[EDIT-066 DENIED] Could not encode the content: %s'#10 +
    'Use native Pascal literals (#$XXXX) for characters outside the ' +
    'character set.';

  SK_EDIT_CREADA_UNIT_FMT =
    '[EDIT-067] CREATED %s (unit %s) - %s, encoding %s (the one ' +
    'configured in the IDE, or UTF-8 with a BOM when that is ANSI and the ' +
    'content does not fit), %s.'#10 +
    'Verification (re-read from disk): %s'#10 +
    'NEXT STEP - register it with delphi_config command=add-unit (it ' +
    'writes the .dpr uses with its in ''...'' path and the .dproj entry): ' +
    'without that, the unit is not part of the project.';

  SN_EDIT_RESTAURAR_NADA_HECHO_FMT =
    '[EDIT-068] RESTORE %s from %s: NOTHING done yet.'#10 +
    'The copy was taken on %s (%s ago): it is the FIRST copy of this ' +
    'file that day, and it does not know who has edited the file since. ' +
    'If another agent touched it after that time, restoring takes away ' +
    'THEIR work TOO; to undo precisely use delphi_git (diff, stash). ' +
    'After a rename (delphi_move) the copy is the one the rename took; ' +
    'earlier copies live under the old name.'#10 +
    'These %d lines of the CURRENT file are not in the copy and WILL BE ' +
    'LOST:'#10 +
    '%s'#10 +
    'If you really want to restore, repeat with confirm: true.';

  SK_EDIT_RESTAURADO_DESDE_FMT =
    '[EDIT-069] RESTORED %s from %s'#10 +
    '  now: %s'#10 +
    '  NOTE: %d lines you had written are lost. Redo and RE-VERIFY every ' +
    'task on this file.'#10 +
    '  (previous state saved in %s)';

  SR_EDIT_BLOQUE_NO_EMPIEZA_FIRMA_FMT =
    '[EDIT-070 INVALID_PARAM] The block does not start with a routine signature ' +
    '(a comment, or attributes such as [Test], above it are allowed). First ' +
    'useful line: |%s|';

  SR_EDIT_RUTINA_GLOBAL_DE_CLASE_FMT =
    '[EDIT-117 INVALID_PARAM] ''class %s'' is a METHOD of a class, not a ' +
    'global routine: insert="metodo" with inclass=<the class>.';

  SN_EDIT_CABECERA_NO_ANADIDA_FMT =
    '  [EDIT-118] NOTE: your block also carried |%s|, which belongs to the ' +
    'declaration - and the declaration was already in the class and was NOT ' +
    'touched: check that line %d has it (delphi_edit old/new).';

  SR_EDIT_FIRMA_NO_CIERRA_FMT =
    '[EDIT-071 INVALID_PARAM] The signature never closes with '';''. It starts at ' +
    '|%s|';

  SR_EDIT_INSERT_FALLO_MITAD1_FMT =
    '[EDIT-072 DENIED] INSERT method - FAILED in half 1 (declaration in ' +
    'class %s):'#10 +
    '%s';

  SR_EDIT_INSERT_FALLO_IMPLEMENTACION_FMT =
    '[EDIT-073 DENIED] INSERT method - FAILED in the implementation (the ' +
    'declaration already existed and was not touched; the file has NOT ' +
    'changed).'#10 +
    '%s';

  SR_EDIT_INSERT_METODO_DESHECHO_FMT =
    '[EDIT-074 DENIED] INSERT method - the declaration was written but the ' +
    'implementation FAILED, so the declaration was UNDONE: the file has NOT ' +
    'changed (a declaration without its body does not compile).'#10 +
    '%s';

  SR_EDIT_NEW_SIN_ANCLA =
    '[EDIT-075 INVALID_PARAM] You passed "new" with no anchor ("old" empty). ' +
    'This tool NEVER rewrites a whole file.'#10 +
    '- To edit: old = the WHOLE line to replace, copied from delphi_read.'#10 +
    '- To read: use delphi_read.';

  SN_EDIT_AVISO_DESIGNER_PROPIEDADES_FMT =
    '[EDIT-076] *** DESIGNER WARNING: properties the %s streaming does ' +
    'NOT know (checked against the tables generated from the framework ' +
    'itself). The build packs them anyway (it only validates grammar) ' +
    'and the app CRASHES when it loads the form at runtime - on Android ' +
    'it dies with no message. Fix them before deploying: ***';

  SR_EDIT_ANCLA_NO_UNICA_FMT =
    '[EDIT-077 INVALID_PARAM] The anchor appears %d times (lines %s), it is ' +
    'not unique. Nothing written.'#10 +
    'Pick another unique line if there is one; only if there is NONE ' +
    '(signature repeated in interface/implementation) repeat with ' +
    'atline: <number>.';

  SR_EDIT_CARACTERES_NO_CABEN_FMT =
    '[EDIT-078 DENIED] %s. The file is in %s and the new text carries ' +
    'characters that do not fit. Nothing written.';
  { ...y en un FUENTE Pascal, la salida sin convertir. Solo ahi: la llevaba
    la negativa de todos, y un .ini o un .bat recibian el consejo de un
    literal Pascal (decima revision). }
  SF_EDIT_LITERAL_PASCAL_FMT =
    #10'LEGITIMATE WAY OUT WITHOUT CONVERTING: a native Pascal literal - ' +
    '#$%s concatenated (''before '' + #$%s + '' after'') or ChrW($%s) / ' +
    'WideChar($%s) - the source stays ASCII and keeps its encoding. ' +
    'Declare it in the report.';
  { ...y la de un caracter FUERA del BMP (un emoji): en Pascal es un PAR de
    sustitutos, y ChrW/WideChar no llegan mas alla de $FFFF (r5-L1 de la
    1.18.0: proponia el literal del sustituto alto solo). }
  SF_EDIT_LITERAL_PASCAL_PAR_FMT =
    #10'LEGITIMATE WAY OUT WITHOUT CONVERTING: a native Pascal literal - its ' +
    'UTF-16 pair #$%s#$%s concatenated (''before '' + #$%s#$%s + '' after'') ' +
    'or Char.ConvertFromUtf32($%s) - the source stays ASCII and keeps its ' +
    'encoding. Declare it in the report.';

  SN_EDIT_CARACTERES_CORRUPCION =
    '[EDIT-079] *** CORRUPTION CHARACTERS HAVE APPEARED. Restore with ' +
    'restore:true and STOP. ***';

  SN_EDIT_ERA_ASCII_PURO_FMT =
    '[EDIT-080] (the file was pure ASCII, so it had no encoding to keep: ' +
    'the new characters were written in %s, as the compiler reads them - ' +
    'a Delphi source goes to the machine''s ANSI code page when they all ' +
    'fit and to UTF-8 with a BOM when one does not, as the IDE saves it; a ' +
    'form stays ANSI (the ' +
    'IDE would write #NNN codes, which the compiler reads the same); any ' +
    'other file follows the IDE''s setting.)';

  SN_EDIT_ACENTOS_FUERA_CUADRO_FMT =
    '[EDIT-081] *** ACCENTS OUT OF BALANCE: expected %d high bytes and ' +
    'there are %d. Restore with restore:true and STOP. ***';

  SN_EDIT_FINALES_LINEA_AJENOS_FMT =
    '[EDIT-082] *** FOREIGN LINE ENDINGS: the file is %s and endings of ' +
    'the other style have come in. Restore with restore:true and STOP. ' +
    '***';

  { La ida y vuelta del lado de la ESCRITURA (revisor propio de la 4.1,
    9-oct-2026): los bytes que se van a escribir, leidos por EL detector,
    saldrian en otra codificacion que la escrita - casi siempre mojibake (una
    A con tilde y un superindice tres en ANSI (1252) son los bytes de una o con
    acento en UTF-8). Escrito asi, el detector y el IDE leerian el fichero
    con otros caracteres que los escritos. %s = el
    fichero, %s = la codificacion escrita, %s = la que leeria el detector,
    %s = la escrita otra vez. }
  SR_EDIT_SE_LEERIA_DISTINTO_FMT =
    '[EDIT-122 DENIED] %s, written in %s, would be read back as %s: the ' +
    'new text has characters whose %s bytes read as another encoding. ' +
    'Usually that is mojibake - an accent that arrived already broken into ' +
    'two characters: put the clean one. If the characters are right, in a ' +
    'Delphi source write them as #$XXXX literals, or convert the file to ' +
    'UTF-8 in the IDE (it saves it with a BOM). Nothing written.';

  SN_EDIT_FIRMA_MOJIBAKE_NUEVO =
    '[EDIT-083] *** MOJIBAKE SIGNATURE IN YOUR NEW TEXT. If you meant to ' +
    'write an accent, put the CLEAN character; if you are copying an ' +
    'existing corruption on purpose, declare it. ***';

  SN_EDIT_DESIGNER_FORMATO_TEXTO =
    '[EDIT-084] (designer file in text format: edited, but the IDE owns ' +
    'it. MENTION IT in your report.)';

  SN_EDIT_ESTRUCTURA_ROTA_END_FMT =
    '[EDIT-085] *** BROKEN STRUCTURE: the file had ONE ''end.'' and now ' +
    'has %d. Restore with restore:true and STOP. ***';

  SN_EDIT_ESTRUCTURA_ROTA_ULTIMA =
    '[EDIT-086] *** BROKEN STRUCTURE: the ''end.'' is no longer the last ' +
    'line - whatever is left after it drops out of the compilation. ' +
    'Restore with restore:true and STOP. ***';

  SK_EDIT_ESCRITO_EN_FMT =
    '[EDIT-087] WRITTEN to %s';

  SK_EDIT_BORRADA_LINEA_FMT =
    '[EDIT-088] DELETED line %d of %s (the line no longer exists)';

  SK_EDIT_BLANQUEADA_LINEA_FMT =
    '[EDIT-089] BLANKED line %d of %s (it still exists, empty; to remove ' +
    'it completely use delete:true)';

  // Mensajes que estaban en linea en Lsp.Scaffold.pas (paso 3c a mano, 27-sep-2026)
  SR_CREATE_IDENTIFICADOR_NOMBRE_PROYECTO_FMT =
    '[CREATE-022 INVALID_PARAM] ''%s'' is not a valid Pascal identifier for a ' +
    'project name.';

  SR_CREATE_YA_EXISTE_PROYECTO_FMT =
    '[CREATE-023 DENIED] A project %s already exists in %s. The ' +
    'scaffolder never overwrites.';

  SK_CREATE_CREADO_PROYECTO_FMT =
    '[CREATE-024] CREATED project %s (%s) in %s'#10 +
    '  files: %s'#10 +
    'Sources in %s (the encoding configured in the IDE) + CRLF. It ' +
    'builds now with delphi_build (the IDE will enrich the .dproj when ' +
    'it opens it).%s';

  SR_CREATE_IDENTIFICADOR_FORM_FMT =
    '[CREATE-026 INVALID_PARAM] ''%s'' is not a valid form identifier.';

  SR_CREATE_YA_EXISTE_SOBREESCRIBE_FMT =
    '[CREATE-027 DENIED] %s already exists. The scaffolder never ' +
    'overwrites.';

  SR_CREATE_CREADOS_NO_REGISTRADOS_FMT =
    '[CREATE-028 DENIED] %s.pas/%s could NOT be registered in the ' +
    'project, so they were removed: NOTHING was created. The cause: %s';

  SK_CREATE_CREADO_FORM_FMT =
    '[CREATE-029] CREATED %s %s (T%s, %s) with its %s.'#10 +
    '%s%s';

  // UNA para las dos gemelas de delphi_create (form y unit): la de forms
  // tenia la suya, CREATE-025, con el mismo texto (retirada el 28-sep)
  SR_CREATE_NO_EXISTE_PROYECTO_FMT =
    '[CREATE-030 NOT_FOUND] The project %s does not exist';

  SR_CREATE_UNIT_YA_EXISTE_ADD_UNIT_FMT =
    '[CREATE-031 DENIED] %s already exists. The scaffolder never ' +
    'overwrites. To register it in the project use delphi_config ' +
    'command=add-unit.';

  SR_CREATE_CREADA_NO_REGISTRADA_FMT =
    '[CREATE-032 DENIED] %s.pas could NOT be registered in the project, ' +
    'so it was removed: NOTHING was created. The cause: %s';

  SK_CREATE_CREADA_UNIT_LINEAS_FMT =
    '[CREATE-033] CREATED unit %s (%s), %d lines.'#10 +
    '%s';

  // Mensajes que estaban en linea en Mcp.Tools.Scaffold.pas (paso 3c a mano, 27-sep-2026)
  SR_CREATE_KIND_DEBE_SER_ALL =
    '[CREATE-034 INVALID_PARAM] kind must be project-console | project-vcl | ' +
    'project-fmx | project-package | project-test | form-vcl | form-fmx ' +
    '| frame-vcl | frame-fmx | datamodule | unit | include.';

  // Mensajes que estaban en linea en Mcp.Tools.FileOps.pas (paso 3c a mano, 27-sep-2026)
  SR_FILE_PAPELERA_NO_SE_BORRA_FMT =
    '[FILE-018 DENIED] %s\ is the trash/backups folder of this tool. It ' +
    'is not deleted from here (to really delete copies that are yours: ' +
    'delphi_delete purge=true on them).';

  SN_FILE_UNITS_CARPETA_QUITADAS_FMT =
    '  [FILE-019] units of the folder removed from their projects (%d):';

  SR_FILE_ERROR_MOVER_PAPELERA_FMT =
    '[FILE-020 INTERNAL] Moving to the trash failed: %s';

  SR_FILE_UNIT_DESHECHO_FMT =
    '[FILE-039 DENIED] %s could not be deleted, and what had already ' +
    'changed (its projects, its form) was put back: NOTHING was changed. ' +
    'The cause: %s';

  SK_FILE_BORRADO_PAPELERA_FMT =
    '[FILE-021] DELETED %s (moved to the recoverable trash).'#10 +
    '  copy: %s'#10 +
    '  To recover it: delphi_move with path=that copy and dest=wherever ' +
    'you want it (restoring from the trash is allowed).';

  SR_FILE_PAPELERA_NO_SE_MUEVE_FMT =
    '[FILE-022 DENIED] %s\ is the trash folder; it is not moved as a ' +
    'whole.';

  SR_FILE_NO_MUEVAS_DENTRO_PAPELERA_FMT =
    '[FILE-023 DENIED] Do not move files INTO the trash (%s\); it is for ' +
    'the copies the tool makes. Move them to a normal folder.';

  SR_FILE_NO_EXISTE_ORIGEN_FMT =
    '[FILE-024 NOT_FOUND] The source %s does not exist';

  SR_FILE_DESTINO_YA_EXISTE_FMT =
    '[FILE-025 DENIED] The destination already exists: %s (not ' +
    'overwriting).';

  SR_FILE_IDENTIFICADOR_UNIT_FMT =
    '[FILE-026 INVALID_PARAM] ''%s'' is not a valid unit identifier (the file ' +
    'name is the unit name).';

  SR_FILE_YA_EXISTE_NO_SOBREESCRIBO_FMT =
    '[FILE-027 DENIED] %s already exists (not overwriting).';

  SN_FILE_COPIA_SEGURIDAD_EN_FMT =
    '  [FILE-028] (backup in %s)';

  // Mensajes que estaban en linea en Lsp.Files.pas (paso 3c a mano, 27-sep-2026)
  SR_FILES_UNIDAD_VIRTUAL_NO_SERVIDA_FMT =
    '[FILE-029 DENIED] Virtual drive not served: %s (delphi_workspace ' +
    'tells which ones exist)';

  SR_FILES_RUTA_INVALIDA_FMT =
    '[FILE-031 INVALID_PARAM] Invalid path (%s)';

  SL_FILES_GET_FMT =
    'files: GET %s (%d bytes)';

  // Mensajes que estaban en linea en Lsp.TextEdit.pas (paso 3c a mano, 27-sep-2026)
  SR_TEXT_YA_EXISTE_NUNCA_SOBREESCRIBE_FMT =
    '[TEXT-005 DENIED] %s already exists. This tool never overwrites; ' +
    'edit with old/new.';

  { ...y si esta VACIO no hay ancla para old/new: se decia lo mismo y no
    habia salida (sexta revision). }
  SR_TEXT_YA_EXISTE_VACIO_FMT =
    '[TEXT-015 DENIED] %s already exists and is EMPTY, so there is no ' +
    'line for old/new to anchor on, and this tool never overwrites. ' +
    'Write it whole with delphi_upload, or delete it (delphi_delete) and ' +
    'create it again.';

  SK_TEXT_CREADO_ENCODING_FINALES_FMT =
    '[TEXT-006] CREATED %s  encoding=%s  eol=%s  bytes=%d';

  SR_TEXT_NO_EXISTE_CREARLO_FMT =
    '[TEXT-007 NOT_FOUND] %s does not exist. To create it use ' +
    'create=true.';

  SR_TEXT_PARECE_BINARIO_FMT =
    '[TEXT-008 DENIED] %s looks BINARY (null bytes). This tool is for ' +
    'text only.';

  SR_TEXT_ANCLA_APARECE_LINEAS_FMT =
    '[TEXT-009 INVALID_PARAM] The anchor appears on %d lines (%s). Repeat with ' +
    'atline=<number> to pick the exact occurrence.';

  SR_TEXT_AL_CODIFICAR_FMT =
    '[TEXT-010 DENIED] Could not write the file: %s';

  SR_TEXT_EOL_FMT =
    '[TEXT-014 INVALID_PARAM] eol "%s" does not exist: crlf (the ' +
    'default) or lf.';

  SK_TEXT_RANGO_VERIFICACION_FMT =
    '[TEXT-011] %s  encoding=%s  (backup in %s\)'#10 +
    'Verification (re-read from disk):'#10 +
    '%s';

  SK_TEXT_OK_BORRADA_LINEA_FMT =
    '[TEXT-012] OK deleted line %d of %s  encoding=%s  (backup in %s\)'#10 +
    'Verification (re-read from disk):'#10 +
    '%s';

  SK_TEXT_OK_LINEA_FMT =
    '[TEXT-013] OK line %d of %s  encoding=%s  (backup in %s\)'#10 +
    'Verification (re-read from disk):'#10 +
    '%s';

  { old sin new: la linea queda en blanco y se DICE, como delphi_edit
    (EDIT-089); contestaba "OK line" (decima revision). }
  SK_TEXT_BLANQUEADA_LINEA_FMT =
    '[TEXT-016] BLANKED line %d of %s (it still exists, empty; to remove ' +
    'it completely use delete:true)  encoding=%s  (backup in %s\)'#10 +
    'Verification (re-read from disk):'#10 +
    '%s';

  // Mensajes que estaban en linea en UTrayMain.pas (paso 3c a mano, 27-sep-2026)
  SL_SYS_ERROR_STARTING_SERVER_FMT =
    'ERROR starting the server: %s';

  SF_SYS_SERVICE_ERROR_FMT =
    'DelphiLSP MCP Service - ERROR: %s';

  SL_SYS_SERVER_URL_COPIED_FMT =
    'Server URL copied to the clipboard: %s. %s';

  SN_SYS_SERVER_URL_COPIED =
    '[SYS-005] Server URL copied';

  // Mensajes que estaban en linea en Lsp.Service.pas (paso 3c a mano, 27-sep-2026)
  SL_SYS_COULD_NOT_START_FMT =
    '%s could not start: %s';

  // Mensajes que estaban en linea en Lsp.Host.pas (paso 3c a mano, 27-sep-2026)
  SL_SYS_KNOWLEDGE_VAULT_FMT =
    'Knowledge vault: %s (%s)';

  SL_SYS_BEARER_AUTH_ENABLED =
    'Bearer auth enabled (per-workspace tokens).';

  SL_SYS_NO_CREDENTIALS_FMT =
    'No credentials: there is no [Workspace.<name>] section with Token=. ' +
    'Every HTTP request gets 401; only the local stdio mode works. %s';

  SL_SYS_NO_BINDIP_LOCALHOST_ONLY =
    'And no [Server] BindIP: HTTP listens on 127.0.0.1 ONLY. To expose ' +
    'it to the network, add a [Workspace.<name>] section with Token=.';

  // Mensajes que estaban en linea en Lsp.LogSink.pas (paso 3c a mano, 27-sep-2026)
  SL_SYS_LOG_EN_DISCO_FMT =
    'Log on disk: %s (actual.log live; one block every %d lines, the ' +
    'newest %d are kept - [Log] LinesPerFile/MaxFiles in settings.ini).';

  SL_SYS_LOG_LINEAS_DESCARTADAS_FMT =
    '... %d log lines discarded (buffer full) ...';

  // Mensajes que estaban en linea en DelphiLspMcp.dpr (paso 3c a mano, 27-sep-2026)
  SL_SYS_SERVICE_STDIO_FMT =
    'DelphiLSP MCP Service v%s (stdio)';

  // Mensajes que estaban en linea en Mcp.Tools.Components.pas (paso 3c a mano, 27-sep-2026)
  SN_COMPONENTS_DESIGN_PACKAGES_FMT =
    '[COMP-007] %d design packages in RAD Studio %s%s%s:';

  // Descripciones que estaban en linea en Mcp.Tools.Config.pas (paso 3d, 27-sep-2026)
  SP_CFG_PROJECT =
    'Absolute path of the project .dproj (its .dpr/.dpk resolves to it). ' +
    'A .groupproj (a project group) takes view, add-project, ' +
    'remove-project and fix-references; every other command is refused';

  { La lista, y explicado SOLO lo que la descripcion de la tool (SD_CFG_CONFIG)
    no cuenta: los dos textos explicaban lo mismo (revisor de tokens,
    4-oct-2026). }
  SP_CFG_COMMAND =
    'view (default; section= for the detail) | add-platform | ' +
    'remove-platform | set-output | set-version | set-sdk (the SDK this ' +
    'project builds a remote platform with, by name; "none" = back to the ' +
    'SDK Manager default) | set-profile (the PAServer profile it deploys ' +
    'and runs that platform with; "none" = the platform''s active profile) ' +
    '| add-searchpath | remove-searchpath | add-deployfile | ' +
    'remove-deployfile | add-unit | remove-unit | add-requires (packages: ' +
    'names for the .dpk requires clause, from requiresSuggested after a ' +
    'W1033) | fix-references | add-project | remove-project. The ' +
    'description says what each does.';

  SP_CFG_PLATFORM =
    'add/remove-platform: the platform name (Win32, Win64, Linux64, ' +
    'Android64...; an unknown one is refused with the list). ' +
    'add/remove-searchpath: the platform whose path changes; empty = the ' +
    'base group (all). add/remove-deployfile: the platform it ships on ' +
    '(required). set-sdk / set-profile: the platform they apply to.';

  SP_CFG_OUTPUT =
    'set-output: a simple relative folder name (Compiled by default): .exe ' +
    'to <folder>\$(Platform)\$(Config), .dcu to ' +
    '<folder>\Dcu\$(Platform)\$(Config). "default" restores the RAD Studio ' +
    'layout. No absolute paths, no "..".';

  SP_CFG_REQUIRES =
    'add-requires: package names for the .dpk requires clause, separated ' +
    'by ; (vcl;dbrtl) - take them from requiresSuggested of delphi_build. ' +
    'Names already there are kept.';

  SD_CFG_CONFIG =
    'See and manage a project''s build configurations and target PLATFORMS. ' +
    'view (read-only): the framework (VCL is Windows-only; FMX and console ' +
    'cross platforms), the configurations (Debug/Release/custom), the defaultPlatform (what delphi_build builds without platform=) and every ' +
    'platform - enabled or not, possible for THIS project, needing a ' +
    'PAServer profile. add-platform / remove-platform: enable or disable a ' +
    'platform in the .dproj (a curated edit of <Platforms> only). ' +
    'set-version: the project VERSION everywhere it must agree. ' +
    'set-output: every binary under one folder (Compiled by default), ' +
    'keeping the platform/config subfolders. add-searchpath / ' +
    'remove-searchpath: a unit search path for ONE platform, as the IDE''s ' +
    'Project Options > Search path; a platform added to a project inherits ' +
    'NO search paths from the others - the usual reason a unit is "not ' +
    'found" only there. add-deployfile / remove-deployfile: ship an extra ' +
    'file with the build on ONE platform, as the IDE''s Deployment Manager ' +
    '(a native .so/.dylib/.dll a component loads, data files), into the ' +
    '.deployproj, creating the standard manifest if missing. add-unit / ' +
    'remove-unit: the IDE''s Add to / Remove from project for an EXISTING ' +
    '.pas (.dpr uses, CreateForm for forms, the .dproj); the file stays on ' +
    'disk. fix-references, on a project or a group: re-points what was ' +
    'moved by hand, finding it by name in the workspace - one match only, ' +
    'never a guess. On a .groupproj: view lists its projects, and ' +
    'add-project / remove-project write what the IDE''s Add existing ' +
    'project writes. set-sdk, set-profile and add-requires: see command. ' +
    'To BUILD a combination: delphi_build with platform+config.';

  // Descripciones que estaban en linea en Mcp.Tools.DelphiExtra.pas (paso 3d, 27-sep-2026)
  SP_BUILD_PATH =
    'Absolute path of the Delphi source file to lint (.pas/.dpr)';

  SP_BUILD_PATH_2 =
    'Absolute path of the Delphi source file';

  SP_BUILD_LINE =
    'Zero-based line of the identifier to find references for (a hit''s ' +
    '"line0"; its "line" is 1-based)';

  SP_BUILD_CHARACTER =
    'Zero-based character inside the identifier (a hit''s "character0")';

  SP_BUILD_PROJECT =
    'Absolute path of the project''s .dproj (its .dpr/.dpk resolves to it)';

  SP_BUILD_PLATFORM =
    'Target platform. Omitted: the project''s own default, the one the IDE ' +
    'builds while nobody changes it. Only a platform the project declares ' +
    'and has enabled (delphi_config add-platform / remove-platform), so the ' +
    'IDE builds the same: Win32/Win64 build natively here; ' +
    'Linux64/OSX64/OSXARM64/Android64/iOSDevice64... need their SDK pulled ' +
    'once (delphi_paserver get-sdk). Building is LOCAL against that SDK and ' +
    'does NOT use profile - a profile is only for target=Deploy.';

  SP_BUILD_CONFIG =
    'A configuration the project declares, e.g. Debug (default) or ' +
    'Release; another is refused (delphi_config view lists them).';

  SP_BUILD_TARGET =
    'Build (full, default) | Make (incremental) | Clean | Deploy (builds ' +
    'first, then deploys: to the PAServer of "profile" for Linux/macOS, or ' +
    'packages the app for Android). After switching platforms use Build.';

  SP_BUILD_PROFILE =
    'target=Deploy on a PAServer platform: the connection profile ' +
    '(delphi_paserver command=profiles). The files land on the target ' +
    'under its PAServer scratch dir, in <windows user>-<profile>/<project ' +
    'name>/.';

  SP_BUILD_SDK =
    'The platform SDK to link against, by name (delphi_paserver ' +
    'command=profiles lists them with their glibc). Omit it and the ' +
    'project decides (its own PlatformSDK), or the only one there is; with ' +
    'several and no hint the build is refused instead of guessing.';

  SP_BUILD_DEVICEID =
    'target=Deploy: device id - msbuild installs only on iOS devices with ' +
    'it; for Android, Deploy builds the .apk and delphi_adb install puts ' +
    'it on a device.';

  SD_BUILD_DIAGNOSTICS =
    'Compiler-grade errors/warnings/hints for one Delphi source file ' +
    '(Error Insight via the official DelphiLSP linter), WITHOUT ' +
    'building. Real compiler codes (E2003, W1000, H2164...) with exact ' +
    '0-based positions (range) and line, the 1-based line delphi_read ' +
    'shows. Severity is the LSP scale: 1=error, 2=warning, ' +
    '3=information, 4=hint. The "hints" counter groups 3 and 4 together; ' +
    'the per-diagnostic severity tells them apart. Lints the CURRENT ' +
    'on-disk content. A big unit can take over a minute the first time: ' +
    'the answer then says the lint is in progress - call again with the ' +
    'same file and the result is returned (the lint is not restarted ' +
    'while the file is unchanged).';

  SD_BUILD_REFERENCES =
    'Find references to the identifier at a 0-based line:character ' +
    'position. Hybrid method (DelphiLSP has no native references): ' +
    'project-wide text scan, then every candidate is validated by asking ' +
    'the compiler engine for its definition - only candidates resolving ' +
    'to the SAME symbol are confirmed, homonyms are rejected. A name ' +
    'written in a COMMENT or inside a string literal is not a reference ' +
    'and does not count as unverified: those go to "mentions". A comment ' +
    'is harmless; a string literal blocks delphi_rename_symbol ' +
    '(RENAME-020), because it may be a FindComponent/RTTI by name. ' +
    'Bounded work: leftovers are listed as unverified, never silently ' +
    'dropped; a file it cannot read, as unreadable.';

  SD_BUILD_BUILD =
    'Build a Delphi project for real with MSBuild on this machine - the ' +
    'closing check after editing (the linter neither links nor produces ' +
    'binaries). The answer carries the success flag, the compiler ' +
    'errors/warnings (as much as "verbosity" asks), the output tail, where ' +
    'the binary landed and, with several Delphi, which one built. ' +
    'Compile-only: a project that would EXECUTE a shell during build (a ' +
    'custom <Target>/<Exec>, a foreign <Import>) is refused unless the ' +
    'workspace declares AllowBuildScripts=1; its pre/post build EVENTS ' +
    '(signing, copies) are skipped instead (buildEventsSkipped says so) - ' +
    'the final binary is built where the events run. For a package (.dpk) ' +
    'the answer adds implicitImports (units of OTHER packages it compiled ' +
    'into itself, W1033) and requiresSuggested (their packages, from this ' +
    'install''s BPLs, or a .dpk of your workspace with ' +
    'requiresWorkspaceNote telling you to build it first), the list ' +
    'delphi_config add-requires takes; a unit dcc cannot find at all ' +
    '(F2613) comes back in missingUnits.';

  // Descripciones que estaban en linea en Mcp.Tools.DelphiLsp.pas (paso 3d, 27-sep-2026)
  SP_LSP_LINE =
    'Zero-based line number of the identifier: the "line0" of a search, ' +
    'references, symbols or definition hit (their "line" is 1-based)';

  SP_LSP_CHARACTER =
    'Zero-based character (column) inside the identifier (a hit''s ' +
    '"character0")';

  SP_LSP_TRIGGER =
    'Optional trigger character, e.g. "." (empty = manual invocation)';

  SP_LSP_KIND =
    'Optional: definition (default) | declaration (jump to the interface ' +
    'declaration) | implementation (accepted, but DelphiLSP answers it ' +
    'like declaration - measured)';

  SD_LSP_SYMBOLS =
    'Document symbol tree of a Delphi unit (classes, methods, properties, ' +
    'sections) with 0-based ranges, from the official DelphiLSP engine; ' +
    'works without project settings. Big trees come as a compact summary ' +
    'by default (mode/filter control it); a FOLDER answers with the ' +
    'interface digest of every unit inside. The engine parses as the ' +
    'COMPILER would for Windows: code inside an inactive {$IFDEF} (LINUX, ' +
    'ANDROID, MACOS...) is not in the tree, and nothing says so - for ' +
    'those blocks use delphi_search or delphi_read.';

  SD_LSP_DEFINITION =
    'Resolve the identifier at a 0-based line:character position in a ' +
    'Delphi source file, using the official DelphiLSP engine ' +
    '(compiler-grade, cross-unit, including RTL/VCL sources). Point ' +
    'INSIDE the identifier. kind selects the half of the unit (a Delphi ' +
    'method exists in BOTH): definition (default) = the BODY in the ' +
    'implementation section; declaration = the interface declaration OF ' +
    'THE TARGET SYMBOL (on a call site the tool chains ' +
    'definition->declaration, so you get the callee; when definition ' +
    'does not resolve, the answer is the direct declaration and a note ' +
    'says so). (kind=implementation is accepted but DelphiLSP answers it ' +
    'like declaration - measured.) Requires project settings for full ' +
    'answers.';

  SD_LSP_SIGNATURE =
    'Signature help (parameter completion) for the call under a 0-based ' +
    'line:character position: the routine signatures with their ' +
    'parameter list, from the official DelphiLSP engine - the IDE''s ' +
    'Ctrl+Shift+Space. Point INSIDE the parentheses of the call (right ' +
    'after "(" or a ","). Requires project settings for full answers.';

  SD_LSP_HOVER =
    'Type/signature information for the identifier at a 0-based ' +
    'line:character position (official DelphiLSP engine). IMPORTANT: ' +
    'hover answers on identifier USAGES (call sites, type references); ' +
    'hovering a declaration itself returns null. Requires project ' +
    'settings for full answers.';

  SD_LSP_COMPLETION =
    'Code completion candidates at a 0-based line:character position ' +
    '(official DelphiLSP engine). Returns at most 50 items ' +
    '(label/kind/detail) plus the total count.';

  // Descripciones que estaban en linea en Mcp.Tools.DelphiPatch.pas (paso 3d, 27-sep-2026)
  SP_EDIT_PATH =
    'Absolute path of the Delphi file (.pas/.dpr/.dpk/.inc/.dfm/.fmx)';

  SP_EDIT_FROMLINE =
    'First line to show, 1-based (0 = from the start)';

  SP_EDIT_TOLINE =
    'Last line to show, 1-based (0 = to the end; capped at 400 lines per ' +
    'call)';

  SP_EDIT_PATH_2 =
    'Absolute path of the Delphi file';

  { Que el ancla sea UNICA y que la sangria no cuente, dicho asi: con "la
    sangria puede omitirse" Qwen3.8 desempataba por sangria dos lineas
    iguales (medido el 5-oct-2026; el motor las da por la misma, EDIT-077). }
  SP_EDIT_OLD =
    'EDIT mode: the line to replace - ONE full line copied from ' +
    'delphi_read (everything after the | bar). It must be UNIQUE in the ' +
    'whole file, and indentation does not count: if the same text is on ' +
    'another line too, add atline (occurrence inside edits).';

  SP_EDIT_ATLINE =
    'EDIT mode tie-break when the anchor appears on several lines: ' +
    '1-based line number of the exact occurrence (the rejection lists ' +
    'the valid numbers)';

  SP_EDIT_DELETE =
    'DELETE mode: true = remove the "old" anchored line ENTIRELY ' +
    '(old+new="" only blanks it). A BLANK line has no text to copy: ' +
    'delete + atline, without old, removes it if that line is blank. ' +
    'No "new" here';

  SP_EDIT_INSERT =
    'INSERT mode (preferred for NEW routines/methods): "rutina-global" ' +
    'or "metodo". The tool places the block at the legal boundary (in a ' +
    '.dpr: between uses and the main begin; in a unit: before the final ' +
    'end./initialization); with "metodo" it also writes the class ' +
    'declaration. Pass code, not old/new';

  SP_EDIT_CODE =
    'INSERT mode: the COMPLETE block, signature UNQUALIFIED (procedure ' +
    'Save; - not procedure TOrder.Save;) + begin..end;. NEVER include end. ' +
    'For a method, attributes before the signature ([Test]) and ' +
    'directives after it (virtual; override; static;...) go to the class ' +
    'declaration, and the implementation goes without them, as the IDE ' +
    'writes it.';

  SP_EDIT_INCLASS =
    'INSERT "metodo": exact class name (e.g. TOrderForm)';

  SP_EDIT_VISIBILITY =
    'INSERT "metodo" optional: private/protected/public/published; empty ' +
    '= end of class. "published" also works on a form class without the ' +
    'keyword (the implicit section after the class header, where event ' +
    'handlers go).';

  SP_EDIT_VISIBLE =
    'INSERT "rutina-global" optional: true = also declare it in the ' +
    'interface section (visible outside the unit)';

  SP_EDIT_CREATEUNIT =
    'CREATE mode: true = create the .pas (never overwrites). Then ' +
    'register it with delphi_config command=add-unit';

  SP_EDIT_CONTENT =
    'CREATE mode: the COMPLETE file content in one call (empty = ' +
    'standard IDE skeleton). Use this when you already know the whole ' +
    'unit: one call instead of create + N patches';

  SP_EDIT_EOL =
    'CREATE mode: line endings, "crlf" (default, Delphi standard) or "lf"';

  SP_EDIT_RESTORE =
    'RESTORE mode: true = restore the file from this tool''s backup. ' +
    'First call shows what would be LOST; repeat with confirm=true to ' +
    'execute';

  SP_EDIT_CONFIRM =
    'Only with restore: execute after having seen the losses';

  SP_EDIT_ADDUSES =
    'ADDUSES mode: units to add to a uses clause of this .pas, separated ' +
    'by ; (System.SysUtils;UCustomer). The engine writes the commas and ' +
    'the terminator, creates the clause when there is none, and skips ' +
    'units already in either section (a unit cannot be in both). For a ' +
    '.dpr/.dpk: delphi_config add-unit.';

  SP_EDIT_SECTION =
    'ADDUSES mode: "interface" or "implementation" (default ' +
    'implementation: a new unit goes there unless one of its types is ' +
    'used in the interface)';

  SP_EDIT_REMOVEUSES =
    'REMOVEUSES mode: units to take out of the uses clause of "section", ' +
    'separated by ; - the inverse of adduses. A directive around the ' +
    'entry stays with its neighbour, the clause goes when it empties, and ' +
    'names not there are reported. For a .dpr/.dpk: delphi_config ' +
    'remove-unit.';

  SD_EDIT_READ =
    'Read a Delphi source file DECODED CORRECTLY (ANSI - the machine''s ' +
    'code page, CP1252 on a Western Windows - / UTF-8 with or without BOM / ' +
    'UTF-16 / UTF-32 detected for real). Returns numbered lines in ' +
    'the format number|content - to build a delphi_edit anchor, copy ' +
    'everything after the bar, exactly. ALWAYS use this instead of a ' +
    'generic read for Delphi files: generic reads turn ANSI accents ' +
    'into U+FFFD and poison every anchor built from them.';

  SD_EDIT_PATCH =
    'SAFE editing of Delphi sources (.pas .dpr .dpk .inc, plus text ' +
    '.dfm/.fmx), keeping their real encoding and line endings. Modes: EDIT ' +
    '(old = ONE full line from delphi_read + new; fragment + atline for a ' +
    'piece of a LONG line; edits for several at once), DELETE, INSERT (a ' +
    'new routine or method at the legal spot, both halves of a method), ' +
    'CREATE (in the encoding configured in the IDE, or UTF-8 with a BOM ' +
    'when ANSI cannot hold it), RESTORE, ADDUSES and ' +
    'REMOVEUSES - each parameter says which mode it belongs to. Refuses ' +
    'whole-file rewrites and binary designer files (TPF0); backs up, ' +
    'writes atomically and audits the result (encoding, EOLs, mojibake, ' +
    'end. structure, a brace comment with a brace inside - warned, never ' +
    'refused), reporting the REAL lines read back from disk: use them as ' +
    'evidence. Never edit Delphi files with generic tools: ANSI sources ' +
    'get destroyed.';

  // Descripciones que estaban en linea en Mcp.Tools.FileOps.pas (paso 3d, 27-sep-2026)
  SP_FILE_PATH =
    'Absolute path of the file or folder to delete (inside the workspace ' +
    'roots). Moved to a recoverable trash, not hard-deleted';

  SP_FILE_PATH_2 =
    'Absolute path of the file or folder to move (inside the workspace ' +
    'roots)';

  SP_FILE_DEST =
    'Destination absolute path (inside the workspace roots). Parent ' +
    'folders are created. Renames when the parent is the same';

  SD_FILE_DELETE =
    'Delete a file or folder inside the workspace - NOT a hard delete: it ' +
    'goes to a recoverable trash (__delphi-patch\<date>\deleted\ next to ' +
    'it), so a mistake can be undone. The exception is the server''s ' +
    '__delphi-temp: nothing is restored from a temp, so a delete there is ' +
    'for good (the temp folder itself is refused: it is every agent''s). ' +
    'Jailed to the workspace roots, refused in read-only mode; a folder ' +
    'that is or holds a workspace root, a reference project or a read-only ' +
    'folder is refused (it would go along). Use it to clean up stray files ' +
    'and leftovers. Deleting a unit (.pas) also trashes its .dfm/.fmx and ' +
    'takes it out of every project that lists it (uses, CreateForm, ' +
    'DCCReference), looked for from its folder up to the edge of the ' +
    'workspace. To keep the file but drop it from a project: delphi_config ' +
    'remove-unit.';

  SD_FILE_MOVE =
    'Move or rename a file or folder inside the workspace, or COPY it with ' +
    'copy=true (how something is brought in from a reference project). The ' +
    'destination must be inside the workspace roots, and so must the ' +
    'source of a move; parent folders are created; a move copies the ' +
    'source to the recoverable trash first. Jailed, refused in read-only ' +
    'mode. A FOLDER moves only as a rename on the same drive, whole or not ' +
    'at all (links inside travel as links); to another drive, copy=true ' +
    'and then delphi_delete. A folder that is or holds a root, a reference ' +
    'or a read-only folder is refused. Moving or renaming a unit (.pas) ' +
    'takes its .dfm/.fmx along, rewrites its "unit X;" header on a rename ' +
    'and re-points every project that lists it (the .dpr uses and ' +
    'DCCReference, the uses of the project''s other units and their ' +
    'qualified UnitOld.X references), looked for from its folder up to the ' +
    'edge of the workspace - all or nothing: a project that cannot be ' +
    're-pointed (read-only, open elsewhere) refuses the whole move with ' +
    'nothing changed (MOVE-019). A FOLDER re-points every unit inside it ' +
    'the same way: reorganise freely, the projects follow. Every RELATIVE ' +
    'path that crosses the border of what moved is re-pointed in the same ' +
    'call: inside it (the units from outside each project lists, the ' +
    '.dproj search/output paths, icon, manifest, .rc, deployed files and ' +
    '.optset, {$I}/{$R}/{$L} - only if the file was where the directive ' +
    'says -, the projects and dependencies of a .groupproj) and outside ' +
    'it, in everything this session can write (a sibling project, an {$I} ' +
    'from another unit, a group): a project moved one level deeper still ' +
    'compiles. What it could not re-point is named, for delphi_config ' +
    'fix-references. A copy re-points only its OWN relative paths that ' +
    'cross its border, so it compiles where it lands, and touches no ' +
    'project that lists the source (see copy); to start a project from ' +
    'another, delphi_create.';

  // Descripciones que estaban en linea en Mcp.Tools.Messages.pas (paso 3d, 27-sep-2026)
  SP_MSGS_COMMAND =
    'read (default: deliver every pending message in your box, then DELETE ' +
    'it) | check (titles and dates of what waits, nothing consumed)';

  SP_MSGS_AGENT =
    'Your agent id - the same value you give delphi_report as "agent" ' +
    '(e.g. dsh, hermes). Omitted: the id your client declared at the ' +
    'handshake';

  // Descripciones que estaban en linea en Mcp.Tools.Scaffold.pas (paso 3d, 27-sep-2026)
  SP_CREATE_KIND =
    'project-console | project-vcl | project-fmx | project-package ' +
    '(requires rtl; its units go into contains with kind=unit or add-unit) ' +
    '| project-test (green at birth; DUnitX ships with RAD Studio) | ' +
    'form-vcl | form-fmx | frame-vcl | frame-fmx | datamodule | unit | ' +
    'include (never registered; used with {$I}). The description says what ' +
    'each one creates.';

  SP_CREATE_DIR =
    'Projects: ABSOLUTE target folder (created if missing). Units, forms, ' +
    'frames, data modules: optional SUBFOLDER relative to the project, as ' +
    'deep as you like (Domain\Models\Dto), created if missing and ' +
    'registered with that path - no drive, no absolute path, no "..". ' +
    'Empty = next to the .dpr. kind=unit or include WITHOUT project: the ' +
    'ABSOLUTE folder of the standalone file.';

  SP_CREATE_NAME =
    'Projects: project name. Forms, frames, data modules and units: unit ' +
    'name (e.g. UCustomers)';

  SP_CREATE_PROJECT =
    'Everything but projects: the ABSOLUTE path of the .dpr, .dpk or ' +
    '.dproj that registers the ' +
    'new unit (uses of a program, contains of a package). kind=unit may go ' +
    'without it, with an ABSOLUTE dir (standalone, listed by no project ' +
    'yet). kind=include: optional, and dir is then relative to it.';

  SP_CREATE_FORMNAME =
    'Forms/frames/data modules optional: instance name without the T ' +
    '(default: Form+unit, Frame+unit, DM+unit)';

  SP_CREATE_CONTENT =
    'kind=unit optional: the FULL source, written as it comes (CRLF) and ' +
    'registered in the same call - no empty skeleton first. Its `unit X;` ' +
    'must match "name" and it must end in `end.`. Without it, a standard ' +
    'empty skeleton. kind=include: REQUIRED, the text of the .inc.';

  SD_CREATE_CREATE =
    'Create a NEW Delphi project - console/VCL/FMX (.dpr + buildable ' +
    '.dproj + main form), a runtime PACKAGE (.dpk + .dproj, built to ' +
    'BPL+DCP in its folder, never installed) or a TEST project (a DUnitX ' +
    'console runner with its first fixture, what delphi_test runs) - or a ' +
    'NEW form, frame, data module or unit (.pas, plus its .dfm/.fmx for ' +
    'the visual ones), registered in the project (.dpr uses - with ' +
    'Application.CreateForm for forms and data modules - and the .dproj). ' +
    'IDE-equivalent skeletons, CRLF, the IDE''s configured source encoding ' +
    '(UTF-8 with a BOM when that is ANSI and the content does not fit), ' +
    'never overwrites anything. kind=unit with NO project and an ABSOLUTE ' +
    'dir creates it STANDALONE (no project lists it yet); kind=include ' +
    'creates a .inc with its content. An EXISTING .pas joins a project ' +
    'with delphi_config add-unit. A uses clause split in {$IFDEF} branches ' +
    '(each ending in its own ";") is never rewritten by add-unit, ' +
    'remove-unit or a rename - it would land in the wrong branch: edit the ' +
    'branch with delphi_edit.';

  // Descripciones que estaban en linea en Mcp.Tools.Styles.pas (paso 3d, 27-sep-2026)
  SP_STYLE_COMMAND =
    'view (styles of a .style file: StyleName, class, lines) | get (one ' +
    'style, whole text) | set (one property of a style or of one of its ' +
    'parts) | clone (a new style copied from an existing one) | delete ' +
    '(remove a whole style by StyleName; the __delphi-patch copy is the ' +
    'way back) | lint (duplicated StyleNames, StyleLookup values of the ' +
    'project''s .fmx that no style defines, design tokens missing in a ' +
    'theme, .rc entries without file) | build (every text .style of the ' +
    'folder -> .bin.style, then the .rc -> .res with brcc32)';

  SP_STYLE_PROJECT =
    'lint: the project .dproj (or a folder) whose .fmx/.pas files are ' +
    'scanned for StyleLookup. Default: the parent folder of the styles ' +
    'folder';

  SP_STYLE_STYLE =
    'get/set/clone: the StyleName of the style (top-level object of the ' +
    'container), e.g. buttonstyle or cardstyle';

  SP_STYLE_CHILD =
    'set optional: a part inside the style, by StyleName or object name, ' +
    'as a path: background or background/text';

  SP_STYLE_PROP =
    'set: the property, as written in the file: Fill.Color, Size.Height, ' +
    'Visible, TextSettings.Font.Size...';

  SP_STYLE_VALUE =
    'set: the value EXACTLY as it appears in a .style file: xFFF6ECDB ' +
    '(colors AARRGGBB), 44.000000000000000000 (floats), True/False, ' +
    '''text'' (strings quoted), Center (enums)';

  SP_STYLE_NAME =
    'clone: the StyleName of the new style';

  SP_STYLE_FILTER =
    'view optional: substring the StyleName must contain';

  SP_STYLE_DELETE =
    'set: true = remove the property instead of setting it';

  // Descripciones que estaban en linea en Mcp.Tools.TextEdit.pas (paso 3d, 27-sep-2026)
  SP_TEXT_PATH =
    'Absolute path of the text file (.md .txt .html .js .css .sql .py ' +
    '.bat .ini .json .yml .xml ... any plain text - Delphi files are ' +
    'refused, use delphi_edit)';

  SP_TEXT_ATLINE =
    'EDIT mode tie-break when the anchor appears on several lines: ' +
    '1-based line number of the exact occurrence';

  SP_TEXT_DELETE =
    'DELETE mode: true = remove the "old" anchored line ENTIRELY (old + ' +
    'an empty new only blanks it). A BLANK line has no text to copy: ' +
    'delete + atline, without old, removes it if that line is blank. ' +
    'No "new" here';

  SP_TEXT_CREATE_ =
    'CREATE mode: true = create a NEW file (never overwrites). UTF-8, ' +
    'parent directories created';

  SP_TEXT_CONTENT =
    'CREATE mode: the initial content of the new file (may be empty)';

  SP_TEXT_EOL =
    'CREATE mode: line endings, "crlf" (default) or "lf"';

  SD_TEXT_TEXTEDIT =
    'SAFE editing of plain-text NON-Delphi files (.md .txt .html .js ' +
    '.css .sql .py .bat .ini .json .yml .xml - ANY plain text): docs, ' +
    'web assets, tests, scripts, config. Same discipline as delphi_edit ' +
    '- one-full-line unique anchor (old/new, atline tie-break; for a ' +
    'LONG line such as a README paragraph, fragment + atline + new ' +
    'changes just a piece of it), DELETE mode (delete=true + old), ' +
    'several edits on the SAME file in one all-or-nothing call ("edits", ' +
    'where an anchor may be ONE line or a contiguous BLOCK), real ' +
    'encoding preserved (UTF-8 +/- BOM / ANSI / UTF-16 / UTF-32), line endings ' +
    'preserved, automatic backup, atomic write - without the Pascal ' +
    'gates. CREATE mode (create=true + content) for new files, never ' +
    'overwrites. Whole-file rewrites are refused. Delphi ' +
    'sources/designers are refused (use delphi_edit) and so are .dproj ' +
    'and binaries. Read first with delphi_read and copy the anchor ' +
    'exactly.';

  // Descripciones que estaban en linea en Mcp.Tools.Vault.pas (paso 3d, 27-sep-2026)
  SP_VAULT_TARGET =
    'files (search by note NAME, a glob pattern such as *meeting*.md) | ' +
    'content (search INSIDE the notes, pattern is a regular expression)';

  SP_VAULT_PATTERN =
    'Name glob if target=files (*.md, *delphi*), or a regular expression ' +
    'if target=content';

  SP_VAULT_SUBFOLDER =
    'Optional: vault-relative folder to narrow the search (projects, ' +
    'conventions...)';

  SP_VAULT_MAXRESULTS =
    'Results PER PAGE (default 50, cap 500).';

  SP_VAULT_SEARCH_OFFSET =
    'Skip the first N results of the FULL list: pass the offset the ' +
    'previous answer gives; walking it reaches every result.';

  SP_VAULT_PATH =
    'RELATIVE path of the note inside the vault (projects/x/context.md). ' +
    'WITHOUT path it returns the rules + the index: do that when you ' +
    'start';

  SP_VAULT_OFFSET =
    'Optional: first line to return (1 = beginning)';

  SP_VAULT_LIMIT =
    'Optional: how many lines to return from offset';

  SP_VAULT_PATH_2 =
    'RELATIVE path of the note (must exist)';

  SP_VAULT_CONTENT =
    'Markdown content to add, in the vault''s language';

  SP_VAULT_ANCHOR =
    'Optional: UNIQUE text after which to insert. Without anchor, it is ' +
    'appended at the end of the file';

  SP_VAULT_PATH_3 =
    'RELATIVE path of the new note (must NOT exist; never overwrites)';

  SP_VAULT_CONTENT_2 =
    'Full markdown content, with the structure/template the vault asks ' +
    'for';

  SP_VAULT_PATH_4 =
    'RELATIVE path of the note';

  SP_VAULT_OLD_TEXT =
    'Text to replace: it must appear EXACTLY ONCE in the file';

  SP_VAULT_NEW_TEXT =
    'New text that replaces it';

  // Descripciones que estaban en linea en Mcp.Tools.Workspace.pas (paso 3d, 27-sep-2026)
  SP_WS_ROOT =
    'Directory to search recursively (project root) - or ONE file (a ' +
    '.dproj, .dpr, .inc, .xml...) to search inside it in a single call';

  SP_WS_QUERY =
    'Text to find on ONE line (case-insensitive - it is Pascal): literal, ' +
    'or a regular expression with regex=true. Line by line, so a query ' +
    'with a line break is refused.';

  SP_WS_REGEX =
    'true = query is a regular expression (PCRE, case-insensitive), ' +
    'matched line by line: ^ and $ are the ends of a line; \w and \b only ' +
    'see ASCII letters.';

  SP_WS_MAXRESULTS =
    'Hits PER PAGE (default 100, cap 500) - not a global limit: offset ' +
    'walks the whole list.';

  SP_WS_OFFSET =
    'Pagination: skip the first N hits of the FULL list - pass the ' +
    'previous answer''s nextOffset; walking it until hasMore=false reaches ' +
    'every hit.';

  SP_WS_WHOLEWORD =
    'true = match whole identifiers only (word boundaries)';

  SP_WS_PATTERN =
    'Optional file mask to search instead of the Delphi set, e.g. ' +
    '*.style, *.ini, *.md, *.rc (one mask)';

  SP_WS_ROOT_2 =
    'Directory to list recursively';

  SP_WS_PATTERN_2 =
    'Filename mask, e.g. *.pas (default: Delphi source and project files)';

  SP_WS_DIRS =
    'true = list SUBDIRECTORIES of root (one level, explorer-style) ' +
    'instead of files';

  SP_WS_INCLUDETRASH =
    'true = also show the recoverable trash (__delphi-patch). Default ' +
    'false.';

  SP_WS_LIST_MAXRESULTS =
    'Entries PER PAGE (default and cap 500).';

  SP_WS_LIST_OFFSET =
    'Skip the first N entries of the FULL list: pass the previous ' +
    'answer''s nextOffset; walking it until hasMore=false reaches every ' +
    'entry.';

  SP_WS_ROOT_3 =
    'Directory to search under; empty = the workspace roots.';

  SP_WS_NAME =
    'Optional name filter (substring, case-insensitive), e.g. "messenger"';

  SP_WS_MAXRESULTS_2 =
    'Projects PER PAGE (default 50, cap 300).';

  SP_WS_OFFSET_2 =
    'Skip the first N projects of the FULL list: pass the previous ' +
    'answer''s nextOffset.';

  SP_WS_REPO =
    'Path of the repository (or any path inside it). The repository ITSELF ' +
    '- root folder and .git - has to be inside your roots: git works on ' +
    'the whole tree. clone: the DESTINATION folder (created if needed, ' +
    'inside your roots).';

  SP_WS_COMMAND =
    'status | diff | log | show | branch | switch | merge | stash | add | ' +
    'restore | commit | init | push | tag | config | clone | pull | fetch ' +
    '| ls-remote | worktree. switch: args=<branch> (create=true for a new ' +
    'one). merge: args=<branch>, always --ff-only (one needing a commit is ' +
    'refused, never left half-done). pull: args=<remote> <branch>, always ' +
    '--ff-only; options: only the download ones (--tags, --no-tags, ' +
    '--prune, --depth=<n>, --unshallow). fetch: those and --all. push: ' +
    '--tags, -u, --set-upstream, --dry-run, and after the remote the NAMES ' +
    'to send (main, v1.3.2, local:remote): it adds to the remote, never ' +
    'overwrites or deletes. ls-remote: args=<remote> [refs], read-only, ' +
    'same remote policy (--heads, --tags, --refs, --symref, --exit-code). ' +
    'The remote of these is a network address the operator allows or a ' +
    'folder inside your roots. stash: args=push|pop|list (never drop); ' +
    'push -- <paths> parks ONLY those paths and sets them back to HEAD - ' +
    'how you discard one file''s changes without losing them (pop brings ' +
    'them back); its label goes in message. config: ' +
    'args=user.name|user.email, the value in message. clone: URL in ' +
    'message, destination in repo. worktree: args=list | add (path = a NEW ' +
    'folder inside your roots, ref = tag|branch|commit, detached) | remove ' +
    '(path = one that list shows; refused with changes or a link inside). ' +
    'restore: args=<paths> (. = all), always --staged: they leave the ' +
    'index and the working tree is never touched - how you undo an add (to ' +
    'discard changes: stash push -- <paths>).';

  SP_WS_ARGS =
    'Optional extra arguments (paths, --staged, a commit hash...), SPLIT ' +
    'ON SPACES: a path with spaces goes in double quotes (args="my ' +
    'notes.txt"). No shell, and shell metacharacters (; | & ` $ < >) are ' +
    'refused anyway - if a legitimate option needs one ' +
    '(--pretty=format:...), ask for it with delphi_report.';

  SP_WS_CREATE =
    'switch: true = create the branch and move to it (git switch -c). ' +
    'Refused with any other command (GIT-038).';

  SP_WS_MESSAGE =
    'commit: the commit message. tag: makes the tag annotated. config: ' +
    'the value. clone: the repository URL';

  SP_WS_PATH =
    'worktree add: a NEW folder inside your roots for the second working ' +
    'copy (like the destination of a clone). worktree remove: a folder ' +
    'that command=worktree args=list shows';

  SP_WS_REF =
    'worktree add: the tag, branch or commit to put there, detached - a ' +
    'version to build and compare, not a place to work (v1.3.2, main, ' +
    'HEAD~3, a commit hash)';

  { la salida de git por paginas (muro de la lista del 4-oct-2026: un diff
    de mas de 30000 caracteres salia cortado y no habia forma de ver el resto) }
  SP_WS_OFFSET_GIT =
    'status/diff/log/show, branch/tag without arguments, stash list, ' +
    'worktree list: lines to skip when the answer did not fit in one page ' +
    '- pass the offset its note gives.';

  SN_GIT_PAGINA_FMT =
    '[GIT-053] Lines %d-%d of %d: the answer is longer than one page. The ' +
    'rest: the same call with offset=%d - or narrow it (args="-- <path>", ' +
    '--stat, -n <count>).';

  SN_GIT_OFFSET_FUERA_FMT =
    '[GIT-054] offset=%d is past the end: the answer has %d lines.';

  { Una linea mas larga que la pagina sale cortada y la pagina siguiente
    empieza en la otra: su cola no se veia nunca, sin aviso (revision de la
    1.13.0). %s: sus numeros (1-based); %d: lo que se ensena de cada una. }
  SN_GIT_LINEA_CORTADA_FMT =
    '[GIT-055] Line(s) %s are longer than a page: only their first %d ' +
    'characters are shown, and offset does not reach the rest. Narrow it ' +
    '(args="-- <path>", --stat) or read the file.';

  { offset pagina la respuesta de una CONSULTA: branch y tag sin argumentos
    lo son, y su nota GIT-053 lo ofrecia mientras el parametro se rechazaba
    (revision de la 1.13.0). Con los que escriben no: repetir la llamada con
    offset la volveria a ejecutar. %s: el comando. }
  SR_GIT_OFFSET_SOLO_CONSULTA_FMT =
    '[GIT-056 INVALID_PARAM] offset pages the answer of a query, and this ' +
    '%s writes (with arguments or a message it creates, not lists). Call ' +
    'it without offset. Nothing was done.';

  SP_WS_PATH_2 =
    'Absolute path of the file to download from the server';

  SP_WS_OFFSET_3 =
    'Byte offset to start from (0 = beginning). Loop increasing it until ' +
    'eof=true and reassemble';

  SP_WS_PATH_3 =
    'Absolute path of the file to write ON the server (inside the ' +
    'workspace roots)';

  SP_WS_CHUNKBASE64 =
    'One chunk of the file, base64-encoded. offset=0 truncates/creates; ' +
    'later offsets append';

  SP_WS_OFFSET_4 =
    'Byte offset this chunk starts at (0 = beginning). Send chunks in ' +
    'order, increasing offset by the bytes written';

  SP_WS_SHA256 =
    'Optional, on the LAST chunk: the whole-file SHA-256; a mismatch FAILS ' +
    'the call and the file is set aside as <name>.corrupt instead of being ' +
    'published.';

  SP_WS_CHUNKSHA256 =
    'Optional: the SHA-256 of THIS chunk (of its decoded bytes), verified ' +
    'BEFORE it is written - a slip in transit is caught at the chunk that ' +
    'carried it, with nothing on disk.';

  SP_WS_DIR =
    'Directory to package (e.g. the build output Win64\Debug). ' +
    'Recursive; *.dcu and dcu\ intermediates excluded';

  SP_WS_OUTFILE =
    'Optional zip path, ending in .zip (default: sibling of dir, named ' +
    '<dirname>-deploy.zip). An existing .zip there is replaced. Must be ' +
    'inside the workspace roots';

  SD_WS_SEARCH =
    'Search Delphi sources recursively for a text (case-insensitive; ' +
    'literal, or a regular expression with regex=true), skipping IDE ' +
    'artifacts BELOW the root (__history, Win32/Win64, dcu, .git, the ' +
    'server''s __delphi-temp...) - naming such a folder as root searches ' +
    'inside it, and skipped files are counted with why ("hidden" + ' +
    '"note"). Files are decoded with their real encoding, so accented text ' +
    'matches. Hits come grouped by folder and file: folders = [{dir, files ' +
    '= [{name, hits = [{line (1-based, as delphi_read numbers it), line0 ' +
    'and character0 (0-based, what the LSP tools take), text}]}]}]; total ' +
    'and shown count hits. A ' +
    'file over 8 MB is not read: the result names it.';

  SD_WS_LIST =
    'List Delphi files under a directory recursively (sources and project ' +
    'files, or a mask), skipping IDE artifacts BELOW the root (naming a ' +
    'build-output folder - Win32/Win64/Debug/Release... - as root lists ' +
    'inside it; hidden entries are counted). Each folder once with its ' +
    'files by name, size and last-write time: folders = [{dir, files = ' +
    '[{name, size, modified}]}]; 500 entries per page (offset walks the ' +
    'rest; a page that starts inside a folder names it again). dirs=true lists ' +
    'the SUBDIRECTORIES of root ' +
    'instead (one level, explorer-style: folders = [{dir, dirs = [names]}]) ' +
    '- to browse the machine and ' +
    'decide where to create or look for projects. includeTrash=true also ' +
    'shows the recoverable trash (__delphi-patch), to find a file ' +
    'delphi_delete moved and restore it with delphi_move.';

  SD_WS_GIT =
    'Whitelisted git operations on a repository of this machine, so a ' +
    'remote agent can bring in code and version its work - the rules of ' +
    'each are in "command". clone is the fast way to get a whole repo onto ' +
    'the server (far better than recreating files one by one). worktree ' +
    'puts ANOTHER version of the repo next to it to build and compare, ' +
    'without touching anybody''s working tree (yours to clean up). ' +
    'Commit/tag messages, config values and the clone URL travel in ' +
    '"message"; push/pull use the credentials and remotes stored on the ' +
    'server. The repository - root folder and .git - has to be inside your ' +
    'roots: git works on the whole repository it finds from "repo" ' +
    'upwards, so one that starts above your roots is refused (GIT-041). No arbitrary ' +
    'git commands, no shell.';

  SD_WS_INSTALLS =
    'List EVERY RAD Studio installation on this machine: version, root ' +
    'directory, whether it ships DelphiLSP.exe and rsvars.bat (msbuild), ' +
    'and the name, personality, edition and build each one states about ' +
    'itself ("RAD Studio 13", "Delphi 13", "Enterprise", ' +
    '"37.0.59082.6021"), plus installedUpdate (its installer''s label). ' +
    'activeForLsp is the one THIS server uses, pinned by [Server] ' +
    'DelphiVersion (requested; written at the first start); ' +
    'requestedUpdate, the declared [Server] DelphiUpdate. A server whose ' +
    'pinned version is not installed does not start. Read-only, no ' +
    'parameters.';

  SD_WS_PROJECTS =
    'Locate Delphi projects (.dproj/.groupproj) under a directory - or ' +
    'under the workspace roots when root is empty; optional name filter. ' +
    'The way to answer "open project X" without knowing the disk layout. ' +
    'Answers in PAGES (maxresults, default 50; offset + nextOffset to walk ' +
    'them): a work machine holds thousands of .dproj. Grouped by folder: ' +
    'projects = [{dir, files = [{name, kind}]}], and each git repository ' +
    'once in repos = [{dir, branch}]: a project''s is the LONGEST dir its ' +
    'folder is inside.';

  SD_WS_UPLOAD =
    'Upload a file TO the server in base64 chunks - the mirror of ' +
    'delphi_fetch, for what you cannot recreate by editing: binaries ' +
    '(.res, icons, images), binary designer files, archives, reference ' +
    'material. Chunks in order: offset=0 creates/truncates, later offsets ' +
    'append and must match the current size. sha256 on the LAST chunk has ' +
    'the server verify the assembled file; chunkSha256 on ANY chunk checks ' +
    'that chunk BEFORE it is written. Jailed to the workspace roots; ' +
    'parent folders are created; a fresh upload over an existing file ' +
    'backs the old one up to the recoverable trash first. For SOURCE CODE ' +
    'prefer delphi_edit / delphi_textedit (they audit encoding and keep ' +
    'backups).';

  SD_WS_PACKAGE =
    'Zip a build-output directory ON the server into a single deploy ' +
    'artifact (recursive, *.dcu intermediates excluded), ready to ' +
    'download with ONE delphi_fetch. The standard way to bring a GUI app ' +
    'to the client machine: delphi_build -> delphi_package -> ' +
    'delphi_fetch.';

  // Excepciones que estaban en linea en Lsp.BuildRunner.pas (paso 3e, 27-sep-2026)
  SE_BUILD_CREATEPIPE_FAILED =
    'CreatePipe failed';

  SE_BUILD_CREATEPROCESS_FAILED_FMT =
    'CreateProcess failed (%d)';

  SR_BUILD_DPROJ_NO_EXISTE_FMT =
    '[BUILD-043 NOT_FOUND] The project %s does not exist. ' +
    'delphi_projects lists the .dproj files of your roots.';

  SR_BUILD_VERBOSITY_FMT =
    '[BUILD-044 INVALID_PARAM] verbosity "%s" does not exist: quiet (the ' +
    'default), normal or verbose.';

  SE_BUILD_RAD_STUDIO_INSTALLATION_DISCOVERED =
    'No RAD Studio installation discovered.';

  SE_BUILD_RSVARS_BAT_FOUND_FMT =
    'rsvars.bat not found: %s';

  // Excepciones que estaban en linea en Lsp.Patch.pas (paso 3e, 27-sep-2026)
  SF_EDIT_CARACTER_NO_EXISTE_FMT =
    'The character "%s" (U+%s) does not exist in %s';

  { Lo que el rename final no pudo con un codigo que no es "ocupado" ni
    "acceso denegado" (esos, SYS-027 / SYS-028): decia "otro proceso lo
    tiene" de cualquier codigo (septima revision). }
  SR_EDIT_RENAME_ATOMICO_FALLIDO_FMT =
    '[EDIT-106 DENIED] Could not replace %s: Windows refused the final ' +
    'rename (error %d: %s). Nothing was written.';

  // Excepciones que estaban en linea en Lsp.References.pas (paso 3e, 27-sep-2026)
  SE_LSP_THIDDENCOUNT_MOTIVO_SIN_CAJON_FMT =
    'THiddenCount: reason with no bucket "%s"';

  SR_LSP_LINE_OUT_RANGE_FMT =
    '[LSP-031 INVALID_PARAM] Line %d does not exist in that file (lines ' +
    'count from 0 here; delphi_read numbers them from 1).';

  SR_LSP_NO_IDENTIFIER =
    '[LSP-030 INVALID_PARAM] There is no identifier at that position: ' +
    'line and character count from 0 here and must point INSIDE a name ' +
    '(delphi_read numbers lines from 1).';

  // Excepciones que estaban en linea en Mcp.Tools.Config.pas (paso 3e, 27-sep-2026)
  SR_CFG_NO_ENCUENTRO_PROPERTYGROUP_CONFIG =
    '[CFG-104 DENIED] Cannot find the base configuration PropertyGroups ' +
    'of the .dproj; open the project once in the IDE (it writes them) ' +
    'and try again.';

  // Excepciones que estaban en linea en Mcp.Vault.Session.pas (paso 3e, 27-sep-2026)
  // Excepciones que estaban en linea en Lsp.Client.pas (paso 3e, 27-sep-2026)
  SE_LSP_LSP_REQUEST_TIMED_OUT_FMT =
    'LSP request "%s" timed out after %d ms';

  SE_LSP_LSP_RESPONSE_VALID_JSON_FMT =
    'LSP response to "%s" is not valid JSON';

  // Excepciones que estaban en linea en Lsp.Transport.Process.pas (paso 3e, 27-sep-2026)
  SE_LSP_LSP_EXECUTABLE_FOUND_FMT =
    'LSP executable not found: %s';

  SE_LSP_CREATEPROCESS_FAILED_FMT =
    'CreateProcess failed (%d) for %s';

  SE_LSP_TRANSPORT_STARTED =
    'Transport not started';

  { (el motor parado por el servidor: SR_LSP_ENGINE_STOPPED, con etiqueta,
    junto a SR_LSP_FOLDER_LEAVING_FMT) }

  SE_LSP_WRITEFILE_LSP_STDIN_FAILED_FMT =
    'WriteFile to LSP stdin failed (%d)';

  // El puerto ocupado al arrancar (issue #5, 27-sep-2026): Indy solo decia
  // "Could not bind socket." - ni que puerto, ni por que, ni que hacer
  SE_SYS_PORT_TAKEN_FMT =
    'Could not listen on port %d (%s): another program is already ' +
    'listening there - most often another copy of this server (the tray, ' +
    'the DelphiLspMcp Windows service, or a terminal with --http) - or ' +
    'Windows keeps that port reserved. Close the other one, or pick another ' +
    'port with [Server] Port= in the settings.ini next to DelphiLspMcp.exe.';

  // Textos que estaban en linea en DelphiLspMcp.dpr (el resto, 27-sep-2026)
  SL_SYS_SERVICE_HTTP_FMT =
    'DelphiLSP MCP Service v%s (HTTP :%s%s)';

  // Textos que estaban en linea en Lsp.BuildRunner.pas (el resto, 27-sep-2026)
  SF_NINGUNO =
    '(none)';

  SF_BUILD_LINKER_RESUMIDA_FMT =
    '  Linker command line: --sysroot %s  (+%d -L paths omitted: they ' +
    'are the same 2 KB in every build)';

  // Textos que estaban en linea en Lsp.Scaffold.pas (el resto, 27-sep-2026)
  SF_CREATE_CLASE_FRAME =
    'frame';

  SF_CREATE_CLASE_DATA_MODULE =
    'data module';

  SF_CREATE_CLASE_FORM =
    'form';

  // Textos que estaban en linea en Lsp.Service.pas (el resto, 27-sep-2026)
  SD_SYS_SERVICE_DESCRIPTION =
    'Remote control of Delphi over MCP: semantic navigation, safe ' +
    'editing, build and git for AI agents working from any platform.';

  SF_SYS_ALL_INTERFACES =
    'all interfaces';

  SL_SYS_STOPPING_FMT =
    '%s stopping: %s';

  // Textos que estaban en linea en Lsp.Transport.Process.pas (el resto, 27-sep-2026)
  SE_LSP_CREATEPIPE_STDOUT_FAILED =
    'CreatePipe (stdout) failed';

  SE_LSP_CREATEPIPE_STDIN_FAILED =
    'CreatePipe (stdin) failed';

  // Textos que estaban en linea en Mcp.Tools.Adb.pas (el resto, 27-sep-2026)
  SK_ADB_KEY_ENVIADA_FMT =
    '[ADB-026] KEY %s %s';

  // Textos que estaban en linea en Mcp.Tools.DelphiLsp.pas (el resto, 27-sep-2026)
  SN_LSP_NO_SE_PUEDE_LEER =
    '[LSP-028] cannot be read';

  // Textos que estaban en linea en Mcp.Tools.PAServer.pas (el resto, 27-sep-2026)
  SN_PAS_MACOS_FETCH_OPEN_PKG =
    '[PAS-046] macOS: fetch, then open the .pkg to install, and run ' +
    'PAServer (port 64211).';

  SN_PAS_WINARM_FETCH_RUN_SETUP =
    '[PAS-047] Windows on ARM: fetch and run the setup, then start ' +
    'PAServer.';

  SN_PAS_DOS_DISTROS_MISMO_SYSROOT =
    '[PAS-048] two distros inside the same sysroot';

  SF_PAS_STATUS_READY_NATIVE =
    'ready (native Windows target, no PAServer needed)';

  SF_PAS_STATUS_READY_SDK =
    'ready (SDK present)';

  SF_PAS_STATUS_NEEDS_PROFILE_SDK =
    'needs a PAServer profile + SDK (see command=packages)';

  SF_PAS_SIN_NAME =
    '(no name)';

  SF_PAS_PULL_ALREADY_UP_TO_DATE =
    'already up to date';

  SF_PAS_PULL_SKIPPED_NOT_TARGET =
    'skipped (not on this target)';

  // Textos que estaban en linea en Mcp.Tools.Workspace.pas (el resto, 27-sep-2026)
  SF_GIT_TRUNCATED =
    '... (truncated)';

  SF_WS_UPTIME_S_FMT =
    '%ds';

  SF_WS_UPTIME_M_S_FMT =
    '%dm %ds';

  SF_WS_UPTIME_H_M_FMT =
    '%dh %dm';

  SF_WS_UPTIME_D_H_FMT =
    '%dd %dh';

  SD_WS_WORKSPACE_FMT =
    'The lay of the land on the SERVER: the workspace roots this server ' +
    'operates within (your entire allowed universe here), the access ' +
    'level (read-write / read-only), the [Workspace.<name>] section of ' +
    'the server this token is scoped to ("workspace"), and the active ' +
    'RAD Studio by version AND by name (activeDelphiName / Personality / ' +
    'Edition / Build, read from the installation - use them when you ' +
    'look anything up for this Delphi), plus delphiUpdate if declared. ' +
    'It also says WHO is answering ' +
    '("server"): version, how this process was started (tray / service / ' +
    'console), transport, pid, uptime, the open sessions, the machine it ' +
    'runs on ("host", also in serverInfo) and the Windows account it runs ' +
    'as - the way to check a deployment without looking ' +
    'at the machine from outside. %s Call this FIRST. Read-only, no ' +
    'parameters.';

  SF_WS_JAIL_CERRADA_FMT =
    'closed (%s): every path is refused (GUARD-030)';

  SF_WS_JAIL_NONE =
    'none (no [Workspace.<name>] Roots: a tokenless local process may ' +
    'look at any path, never touch - see "access")';

  SF_WS_SUBCARPETAS_REGISTRADAS_FMT =
    '%s  (+%d registered subfolders)';

  // Textos que estaban en linea en UTrayMain.pas (el resto, 27-sep-2026)
  SF_SYS_TRAY_CAPTION_FMT =
    'DelphiLSP MCP Service v%s - %s';

  SF_SYS_TRAY_HINT_FMT =
    'DelphiLSP MCP Service v%s'#13#10 +
    '%s';

  // Textos que estaban en linea en Lsp.Patch.pas (el resto, 27-sep-2026)
  SF_EDIT_METRICAS_FMT =
    'bytes=%d breaks=%d CRLF=%d loneLF=%d accents=%d corruption=%d';
  // los contadores cuando no hay nada que mirar (Lsp.Patch.Auditoria): sin
  // U+FFFD, sin CR suelto y un solo tipo de salto; los acentos se quedan,
  // dicen si la codificacion importa (revisor de tokens, 4-oct-2026)
  SF_EDIT_AUDITORIA_LIMPIA_FMT =
    'audit=clean accents=%d';
  SF_EDIT_ANTES_DESPUES_FMT =
    '  before:  %s'#10 +
    '  after:   %s';

  // la ruta solo cuando la copia es NUEVA: en cada edicion del mismo fichero
  // salia otra vez entera (revisor de tokens, 4-oct-2026)
  SF_EDIT_COPIA_YA_EXISTIA =
    'already existed (the first one of today stays)';

  SF_EDIT_EDAD_MIN_FMT =
    '%d min';

  SF_EDIT_EDAD_HORAS_MIN_FMT =
    '%d h %.2d min';

  SF_EDIT_EDAD_DIAS_FMT =
    '%d days';

  SF_EDIT_PISTA_Y_MAS_FMT =
    '  ...and %d more';

  SF_EDIT_NO_ES_OBJETO =
    'not an {old,new} object';

  { Otra forma que la de una cita (N|texto, de CitaDeLinea): con '%d| (line
    removed)' un lector de citas la tomaba por una linea que decia eso
    (revision de paisaje de la 1.13.0) }
  SF_EDIT_LINEA_QUITADA_FMT =
    '(line %d removed)';

  SF_EDIT_OK_BLOQUE_LINEAS_FMT =
    '  %d OK (block of %d lines)';

  SF_EDIT_OK_ANCLA_FMT =
    '  %d OK: %s';

  SF_EDIT_SIN_CAMBIOS_ANCLA_FMT =
    '  %d UNCHANGED (it already says that): %s';

  SR_EDIT_DESDE_MAS_ALLA_FINAL_FMT =
    '[EDIT-100 INVALID_PARAM] %s  encoding=%s  eol=%s  %s'#10 +
    'The file has %d lines; from=%d is past the end.';

  SK_EDIT_LECTURA_NUMERADA_FMT =
    '[READ-005] %s  encoding=%s  eol=%s  %s'#10 +
    'Lines %d-%d of %d (format number|content: copy the anchor from just ' +
    'after the bar):'#10 +
    '%s%s';

  SK_EDIT_LECTURA_VACIO_FMT =
    '[READ-006] %s  encoding=%s  eol=%s  %s'#10 +
    'The file is EMPTY (0 lines).';

  SF_EDIT_CONTENIDO_APORTADO =
    'supplied content';

  SF_EDIT_ESQUELETO_ESTANDAR_IDE =
    'standard IDE skeleton';

  SF_EDIT_NINGUNA_YA_EN_COPIA =
    '  (none: the current file has no lines that are not already in the ' +
    'backup)';

  SF_EDIT_Y_MAS_FMT =
    '  ... and %d more';

  SF_EDIT_VISIBLE_IGNORADO_PROGRAM =
    '(visible ignored: a program has no interface section)';

  SK_EDIT_INSERT_RUTINA_DPR_FMT =
    '[EDIT-102] INSERT rutina-global (.dpr): placed AFTER line %d ' +
    '(|%s|), between the uses and the main block - the legal boundary in ' +
    'a program.'#10 +
    '%s%s';

  SF_EDIT_VISIBLE_DECLARACION_ANADIDA_FMT =
    '--- visible: declaration ''%s'' added at the end of the interface ---';

  SF_EDIT_VISIBLE_NO_PUDE_ANADIR =
    '*** visible: could NOT add the declaration to the interface - write ' +
    'it with old/new. ***';

  SF_EDIT_VISIBLE_NO_ENCUENTRO_IMPLEMENTATION =
    '*** visible: no single ''implementation'' line found; add the ' +
    'declaration with old/new. ***';

  SK_EDIT_INSERT_RUTINA_ANTES_FMT =
    '[EDIT-103] INSERT rutina-global: placed BEFORE line %d (|%s|), the ' +
    'legal boundary chosen by the tool.'#10 +
    '%s%s';

  { Ya habia una rutina con ese nombre: se AVISA, no se niega (dcc dira si es
    la misma; "metodo" si la niega porque escribe las dos mitades). Se
    insertaba a ciegas (decima revision). }
  SN_EDIT_RUTINA_YA_EXISTE_FMT =
    '  [EDIT-116] WARNING: a routine named %s already exists at line %d (a ' +
    'global routine, or a method declaration with that name). If it is the ' +
    'same global routine, dcc will report the duplicate: check before building.';

  SF_EDIT_CLASE_YA_DECLARABA_FMT =
    'the class ALREADY declared ''%s'' (line %d) and NO second declaration ' +
    'is added (if you wanted an OVERLOAD, its declaration goes with ' +
    'old/new)';

  SK_EDIT_INSERT_METODO_SOLO_IMPL_FMT =
    '[EDIT-104] INSERT metodo in %s: %s. Only the implementation was ' +
    'written.'#10 +
    '--- Implementation ''%s'' at the legal boundary ---'#10 +
    '%s';

  SK_EDIT_INSERT_METODO_DOS_MITADES_FMT =
    '[EDIT-105] INSERT metodo in %s: the tool did BOTH halves.%s'#10 +
    '--- Half 1: declaration ''%s'' inside the class ---'#10 +
    '%s'#10 +
    '--- Half 2: implementation ''%s'' at the legal boundary ---'#10 +
    '%s';

  SF_EDIT_NO_LOCALIZAR_LINEA_NUEVA =
    '(could not locate the new line)';

  SN_EDIT_POSIBLE_INSERCION_METODO_FMT =
    '[EDIT-101] *** POSSIBLE INSERTION INSIDE A METHOD: the signature ' +
    '''%s'' ended up with ''%s'' above it, which looks like a statement. ' +
    'Check the begin/end balance; if the method was split, restore with ' +
    'restore:true. ***';

  SF_EDIT_ECO_ESCRITURA_FMT =
    '%s'#10 +
    '  encoding=%s  eol=%s  backup=%s'#10 +
    '%s'#10 +
    '  resulting lines read back from disk:'#10 +
    '%s';

  SN_EDIT_RELECTURA_FALLIDA_FMT =
    '[EDIT-108] WRITTEN, but the file could not be re-read to show it ' +
    '(another process took it right after: %s). What is shown is what ' +
    'was written.';

  SR_EDIT_VISIBLE_DESHECHO_FMT =
    '[EDIT-109 DENIED] visible=true: the declaration could not be added ' +
    'to the interface, so NOTHING was written (the routine would have ' +
    'been private to the unit, which is not what you asked for). %s';

  // Textos que estaban en linea en Lsp.TextEdit.pas (el resto, 27-sep-2026)
  SF_TEXT_ASCII_COMPATIBLES =
    'ascii (utf8/ansi compatible)';

  // Textos que estaban en linea en Mcp.Tools.TextEdit.pas (el resto, 27-sep-2026)
  SP_TEXT_NEW =
    'EDIT mode: the new text; may be several lines. Empty = blank the ' +
    'line';

  // Textos que estaban en linea en Mcp.Tools.DelphiPatch.pas (el resto, 27-sep-2026)
  SP_EDIT_NEW =
    'EDIT mode: the new text; may be several lines (to insert code, ' +
    'anchor on an existing line and return it inside new with the added ' +
    'code)';

  // Textos que estaban en linea en Lsp.Changeset.pas (el resto, 27-sep-2026)
  SF_CHSET_YA_EXISTE_FMT =
    '%s already exists';

  SF_CHSET_NO_EXISTE_FMT =
    '%s does not exist';

  SF_CHSET_LINEA_NO_EXISTE_FMT =
    'line %d does not exist (%s has %d)';

  SF_CHSET_LINEA_NO_ESPERADA_FMT =
    'line %d is not the expected one (it is "%s")';

  SF_CHSET_DESTINO_YA_EXISTE_FMT =
    'the destination already exists: %s';

  SF_CHSET_ANCLA_PENDIENTE =
    'pending';

  SF_CHSET_ANCLA_NO_ENCONTRADA =
    'NOT FOUND';

  SF_CHSET_ANCLA_AMBIGUA =
    'AMBIGUOUS (set atline)';

  SF_CHSET_MISMO_NUMERO_LINEAS =
    '  (same number of lines)';

  SF_CHSET_LINEAS_EN_TOTAL_FMT =
    '  (%s%d lines in total)';

  // Textos que estaban en linea en Mcp.Tools.Config.pas (el resto, 27-sep-2026)
  SF_CFG_NO_VCL_WINDOWS_ONLY =
    'no (VCL = Windows only; use FMX or a console app to target ' +
    'Linux/macOS/mobile)';

  SF_CFG_YES_FMX_CONSOLE_TARGET =
    'yes (FMX/console can target other platforms)';

  SR_CFG_NO_ENCUENTRO_BLOQUE_PLATFORMS =
    '[CFG-101 DENIED] Cannot find a <Platforms>...</Platforms> ' +
    'block in the .dproj.';

  SR_CFG_PLATFORM_FORMA_INESPERADA =
    '[CFG-102 DENIED] The <Platform> of the .dproj has an ' +
    'unexpected shape.';

  SF_CFG_RAD_STUDIO_DEFAULT =
    '(RAD Studio default)';

  SF_CFG_SIN_DEFINIR =
    '(not set)';

  SF_CFG_TODAS_PLATAFORMAS_BASE =
    'all platforms (base group)';

  SR_CFG_DEPLOYPROJ_SIN_CIERRE_PROJECT =
    '[CFG-103 DENIED] The .deployproj has no </Project>; open it ' +
    'in the IDE and try again.';

  SF_CFG_SUFIJO_NO_VA_DPROJ_FMT =
    'The suffix "%s" does not go into the .dproj (the VERSIONINFO is ' +
    'numeric): keep it wherever your project records its version (a ' +
    'constant, the CHANGELOG).';

  SF_CFG_EN_NUMEROS_Y_CLAVES_FMT =
    '%s in the numbers and %s in the keys';

  // Textos que estaban en linea en Lsp.Dproj.pas (el resto, 27-sep-2026)
  SF_CFG_VCL_SOLO_WINDOWS_FMT =
    'the project is VCL and VCL only exists on Windows (Vcl.Forms does ' +
    'not compile for %s). For cross-platform with a UI use FMX; without ' +
    'a UI, a console app.';

  SF_CFG_HAZARD_PROPERTY_FUNCTION =
    'a static MSBuild property function (may read files or load code during evaluation)';

  SF_CFG_HAZARD_TASK_FMT =
    'a <%s> task (executes a program or writes files during build)';

  SF_CFG_HAZARD_SHELL_COMMAND_FMT =
    'a non-empty <%s> shell command';

  SF_CFG_HAZARD_IMPORT_UNC_FMT =
    'an <Import> from a UNC path (%s)';

  SF_CFG_HAZARD_IMPORT_PROFUNDO_FMT =
    'an <Import> chain too deep to verify (%s)';

  SF_CFG_HAZARD_IMPORT_NO_VERIFICABLE_FMT =
    'an <Import> whose path cannot be verified (%s)';

  SF_CFG_HAZARD_IMPORT_NO_ESTA_FMT =
    'an <Import> of a file that is not there to be checked (%s)';

  SF_CFG_HAZARD_IMPORT_ILEGIBLE_FMT =
    'an <Import> that cannot be read to be checked (%s)';
  { La puerta de leer (Lsp.Patch.LeeTexto): un Import que no es del IDE y
    cae FUERA de las raices no se lee para escanearlo - se leia, y limpio, el
    build lo cargaba de alli (decisions/puertas-diseno-2026-10-09). }
  SF_CFG_HAZARD_IMPORT_FUERA_FMT =
    'an <Import> of a file outside the workspace (%s): the build would load ' +
    'it from there';

  SF_CFG_HAZARD_POR_IMPORT_FMT =
    '%s, brought in by <Import> "%s"';

  // Textos que estaban en linea en Lsp.ProjectUnits.pas (el resto, 27-sep-2026)
  SF_USES_EL_FICHERO =
    '(the file)';

  SF_USES_DCCREFERENCE_DEL_DPROJ =
    ', DCCReference of the .dproj';

  SF_USES_REAPUNTADAS_FMT =
    '  re-pointed: %s';

  SF_USES_NO_ENCONTRADAS_WORKSPACE_FMT =
    '  not found in the workspace: %s';

  // Textos que estaban en linea en Mcp.Tools.Components.pas (el resto, 27-sep-2026)
  SF_COMP_NO_EXISTE =
    '  (does not exist)';

  SF_COMP_REGISTRADO_EN_FMT =
    '  %s   (registered in: %s)';

  SF_COMP_DESHABILITADO =
    ' (DISABLED)';

  SF_COMP_CON_FILTRO_FMT =
    ' with "%s"';

  SF_COMP_DESHABILITADOS_FMT =
    ' (%d disabled)';

  // Textos que estaban en linea en Mcp.Tools.Vault.pas (el resto, 27-sep-2026)
  SF_VAULT_CONTENIDO =
    'content';

  SF_VAULT_NOMBRES =
    'names';

  SF_VAULT_SOLO_NOMBRES_NOTAS =
    ' Only the note NAMES were searched: to search inside the text, ' +
    'repeat with target=content.';

  SF_VAULT_PAGINA_FMT =
    ' of %d, from offset=%d';

  SF_VAULT_SIGUIENTE_FMT =
    ' - the next page is offset=%d';

  SN_VAULT_CABECERA_NOTA_FMT =
    '[VAULT-039] # %s (%d lines)';

  SL_VAULT_APPEND_FMT =
    'vault_append: %s';

  SF_VAULT_TRAS_EL_ANCHOR =
    'after the anchor';

  SF_VAULT_AL_FINAL =
    'at the end';

  SF_VAULT_SIN_COPIA =
    '(no copy)';

  SL_VAULT_CREATE_FMT =
    'vault_create: %s';

  SL_VAULT_PATCH_FMT =
    'vault_patch: %s';

  // Textos que estaban en linea en Mcp.Vault.Session.pas (el resto, 27-sep-2026)
  SD_VAULT_PROMPT_TITLE =
    'Load the knowledge vault';

  // Textos que estaban en linea en Lsp.TestRunner.pas (el resto, 27-sep-2026)
  SF_TEST_USA_DUNITX =
    'uses DUnitX';

  SF_TEST_CONSOLA_NOMBRE_TEST =
    'console and the name says test';

  SF_TEST_CONSOLA_PASS_FAIL =
    'console (PASS/FAIL + ExitCode)';

  // Textos que estaban en linea en Mcp.Tools.Designer.pas (el resto, 27-sep-2026)
  SF_DSGN_BLOQUE_LINEAS_FMT =
    '%s (%s) lines %d-%d of %s:'#13#10 +
    '%s';

  SF_DSGN_LADO_A_CERO_FMT =
    '%s: %s (line %d) is %s x %s: with one side at zero it is not ' +
    'visible, even if the form loads';

  // un control sin Width/Height en el .dfm: el tamano de su constructor (lo
  // deja asi el insert de delphi_designer; antes se saltaba como no visual)
  SF_DSGN_TAMANO_DEL_CONSTRUCTOR_FMT =
    '%s: %s (line %d) carries no Width/Height: it takes the size its ' +
    'constructor gives, which is not in the .dfm and is not measured here ' +
    '(command=preview shows it)';

  SF_DSGN_NO_LLEVA_EN_DFM_FMT =
    '%s: %s (line %d) has no %s in the .dfm; with align %s it is needed ' +
    'to know where it ends';

  SF_DSGN_NO_CABE_ALTO_FUERA_FMT =
    '%s (line %d) does not fit entirely in "%s": of %d px of height only ' +
    '%d are visible, the rest is outside';

  SF_DSGN_NO_CABE_ALTO_FMT =
    '%s (line %d) does not fit entirely in "%s": of %d px of height only ' +
    '%d are visible';

  SF_DSGN_NO_CABE_ANCHO_FMT =
    '%s (line %d) does not fit entirely in "%s": of %d px of width only ' +
    '%d are visible';

  SF_DSGN_OCUPA_SE_SALE_FMT =
    '%s: %s (line %d) spans from (%d,%d) to (%d,%d), and "%s" is only %d ' +
    'x %d: it sticks out and that part is not visible';

  SF_DSGN_AMBOS_ALCLIENT_FMT =
    '%s (line %d) and %s (line %d) are both alClient in "%s": the VCL ' +
    'gives the WHOLE rectangle to both, so they cover each other 100%%';

  SF_DSGN_SE_SOLAPAN_FMT =
    '%s (line %d) and %s (line %d) overlap in "%s": they share from ' +
    '(%d,%d) to (%d,%d), one covers the other';

  SF_DSGN_NO_DICE_CUANTO_MIDE_FMT =
    '%s does not say how big it is (%d x %d): without the size of the ' +
    'form I cannot place anything';

  SF_DSGN_TEXTO =
    'text';

  SF_DSGN_BINARIO =
    'binary';

  // Textos que estaban en linea en Lsp.DesignerBin.pas (el resto, 27-sep-2026)
  SR_DSGN_NO_ES_DESIGNER_BINARIO =
    '[DSGN-043 INVALID_PARAM] Not a binary designer: it starts as text.';

  SR_DSGN_BINARIO_DANADO_FMT =
    '[DSGN-044 DENIED] Damaged BINARY designer, or not a .dfm: could not ' +
    'convert it to text (%s: %s). If this server ever wrote it, its ' +
    'copies are in the __delphi-patch trash next to it (delphi_list ' +
    'includetrash=true shows them).';

  SR_DSGN_CARACTERES_NO_CABEN_ANSI =
    '[DSGN-045 DENIED] The text has characters that do not fit in the ' +
    'ANSI code page of this machine: in a text .dfm they are written as ' +
    '#NNNN (the decimal code of the character, outside the quotes), as ' +
    'the IDE does. Fix them and repeat.';

  SR_DSGN_NO_PUDE_CONVERTIR_BINARIO_FMT =
    '[DSGN-046 DENIED] Could not convert the text to a binary designer ' +
    '(%s: %s).';
  { to-binary con un NOMBRE no ASCII (de un objeto, su clase o una
    propiedad): el parser de forms de la RTL no lo lee - salia su
    EParserError 'Identifier expected' - y dcc si, guardandolo en UTF-8
    (medido 9-oct, 4.1 de la 1.18.0). %s = el nombre, %d = su linea. }
  SR_DSGN_NOMBRE_NO_ASCII_BINARIO_FMT =
    '[DSGN-120 DENIED] %s (line %d) is a name with letters outside ASCII: ' +
    'the RTL''s form parser, the one to-binary uses, reads only ASCII ' +
    'names. The compiler reads it (the form compiles as text, saved as ' +
    'UTF-8 with BOM), so keep this form as text, or rename it with ASCII ' +
    'letters to convert it. Nothing was written.';
  { Un form de TEXTO en UTF-16 o UTF-32 (lo deja guardar el selector de
    codificacion del editor del IDE): dcc no lo compila - RLINK32 toma su
    FF FE por un recurso de 16 bits, o no lo abre: E2161 con los cuatro
    (medido el 9-oct-2026, r5 de la 1.18.0) -; si UTF-8 con BOM, ANSI o el
    binario. El renderizador lee el UTF-16 (lo pasa a UTF-8 para el parser
    de forms), el UTF-32 no. %s = el fichero, %s = su codificacion. }
  SN_DSGN_FORM_ANCHO_FMT =
    '[DSGN-121] NOTE: %s is a text form in %s. The IDE opens it, but the ' +
    'compiler does not build it (RLINK32 refuses a text form in UTF-16 or ' +
    'UTF-32: E2161, measured). Save it from the IDE as UTF-8 (the IDE adds ' +
    'the BOM) or ANSI before building.';
  SR_DSGN_FORM_UTF32_FMT =
    '[DSGN-122 DENIED] %s is a text form in %s: the renderer reads forms ' +
    'the way the IDE''s form parser takes them (ANSI, UTF-8 with a BOM, or ' +
    'UTF-16, which it converts first), and the compiler does not build a ' +
    'UTF-32 form either (E2161, measured). Save it from the IDE as UTF-8 or ' +
    'ANSI; delphi_read, tree and lint read it as it is. Nothing was ' +
    'rendered.';

  // 8.10 y 9.B de la 1.18.0: lo que dice EL parser del IDE
  // (Lsp.DesignerForma.ErrorDelParserDeForm), no una gramatica propia
  SN_DSGN_PARSER_FMT =
    '[DSGN-123] *** The IDE''s form parser does not read this file: "%s". ' +
    'Line %d: %s - the parser names the line where it NOTICED the ' +
    'problem, which can be the one after it. As it is, the IDE will not ' +
    'open the form and the program will not load it.';

  SR_DSGN_PARSER_NO_ESCRIBE_FMT =
    '[DSGN-124 INVALID_PARAM] Nothing was written: after this change ' +
    'the IDE''s form parser would not read %s: "%s" (line %d of the ' +
    'result: %s).';

  SR_DSGN_PREVIEW_PARSER_FMT =
    '[DSGN-126 INVALID_PARAM] Nothing was rendered: the IDE''s form parser ' +
    'does not read %s: "%s" (line %d: %s - where it NOTICED the problem, ' +
    'which can be the line after it). The IDE would not open it either; ' +
    'lint says the same, and delphi_edit fixes the line.';

  // props de insert y set (3.10 de la 1.18.0): 'Prop=valor;...'
  SR_DESIGNER_PROPS_VACIO =
    '[DSGN-127 INVALID_PARAM] props has no entries: it is "Prop=value" ' +
    'pairs separated by ";" (a ";" inside a quoted value does not split).';

  SR_DESIGNER_PROPS_PAR_FMT =
    '[DSGN-128 INVALID_PARAM] props, entry %d (%s) has no "=": each entry ' +
    'is Prop=value. Nothing was written.';

  SR_DESIGNER_PROPS_ENTRADA_FMT =
    '[DSGN-129 INVALID_PARAM] props, entry %d (%s): nothing was written - ' +
    'all or none. %s';

  SR_DESIGNER_PROPS_NAME_FMT =
    '[DSGN-130 INVALID_PARAM] props, entry %d is Name: a rename changes ' +
    'the unit too, so it goes alone (set prop=Name; or component= in ' +
    'insert). Nothing was written.';

  SR_DESIGNER_PROPS_DOBLE_FMT =
    '[DSGN-131 INVALID_PARAM] props names %s twice (entries %d and %d). ' +
    'Nothing was written.';

  SR_DESIGNER_PROPS_SOLO =
    '[DSGN-132 INVALID_PARAM] props is the whole set: it does not go with ' +
    'prop/value (one property) nor with parent (a move).';

  // TrozosDeEstado: un literal que se abre y no se cierra (revisor 2, M-A)
  SR_DESIGNER_COMILLA_SIN_CERRAR_FMT =
    '[DSGN-134 INVALID_PARAM] "%s" opens a quoted value and never closes ' +
    'it, so the rest of the list would be swallowed into it. Nothing was ' +
    'done: close the quote (a quote inside a quoted value is written twice) ' +
    'or write the value without quotes - a quote that does not START the ' +
    'value is just a letter (Caption=Don''t save).';

  // set before=/after=/index= (3.11 de la 1.18.0): el orden entre hermanos,
  // si el IDE lo guarda ahi (se le pregunta: Lsp.FormRender.ComoLoEscribeElIde)
  SR_DESIGNER_ORDEN_SOLO =
    '[DSGN-135 INVALID_PARAM] before, after and index are three ways to say ' +
    'where: give ONE of them, alone (no prop, value, props or parent - ' +
    'parent= moves it into another container first). Nothing was written.';
  SR_DESIGNER_ORDEN_EL_IDE_FMT =
    '[DSGN-136 INVALID_PARAM] %s cannot go %s: the IDE''s own writer - asked ' +
    'with the form loaded as the designer loads it - keeps the children of ' +
    '%s in this order: %s. That is what it would save, so this order would ' +
    'not hold (VCL writes graphic controls before windowed ones; an ' +
    'inherited form places a new component by its [n]...). Nothing was ' +
    'written.';
  SR_DESIGNER_ORDEN_NO_HERMANO_FMT =
    '[DSGN-137 INVALID_PARAM] %s is in %s and %s is in %s: before and after ' +
    'order children of the SAME parent. To take it into another one, set ' +
    'parent= first. Nothing was written.';
  SR_DESIGNER_ORDEN_INDICE_FMT =
    '[DSGN-138 INVALID_PARAM] index=%d: %s has %d sibling(s) in %s (itself ' +
    'included), so index goes from 1 to %d. Nothing was written.';
  SR_DESIGNER_ORDEN_SI_MISMO_FMT =
    '[DSGN-139 INVALID_PARAM] %s cannot go before or after itself. Nothing ' +
    'was written.';
  SR_DESIGNER_ORDEN_SIN_CLASE_FMT =
    '[DSGN-140 INVALID_PARAM] %s cannot be ordered there: the renderer could ' +
    'not load the class %s (of %s) - no installed package registers it, or ' +
    'it is a frame whose .dfm is not in the form''s folder -, so where the IDE ' +
    'would write it cannot be asked. Nothing was written.';
  SR_DESIGNER_ORDEN_INCOMPLETO_FMT =
    '[DSGN-143 INVALID_PARAM] %s cannot be ordered there: the renderer loaded ' +
    'the form without %s (what it said: %s) - an ancestor it did not find ' +
    'next to the form, or a component its loader skipped -, so the IDE''s ' +
    'writer cannot say where it would put it. Nothing was written.';
  SR_DESIGNER_ORDEN_CAMBIO_FMT =
    '[DSGN-144 INVALID_PARAM] %s changed while the IDE''s writer was being ' +
    'asked: nothing was written. Repeat the call.';
  SN_DESIGNER_ORDEN_YA_ESTA_FMT =
    '[DSGN-141] %s is already at position %d of %d in %s: nothing was changed.';
  SN_DESIGNER_ORDEN_NOTA =
    '[DSGN-142] Placed where the IDE''s own writer keeps it (asked before ' +
    'writing, with the form loaded as the designer loads it). The file order ' +
    'is the order the IDE keeps for these children - for controls their ' +
    'z-order, a later one drawn over an earlier one (in an inherited form, ' +
    'after the ancestor''s, unless a [n] places it among them); in a toolbar ' +
    'or a page control, their place -; the keyboard order is TabOrder, which ' +
    'this does not change.';
  SF_DESIGNER_ORDEN_DELANTE_DE_FMT = 'before %s';
  SF_DESIGNER_ORDEN_DETRAS_DE_FMT = 'after %s';
  SF_DESIGNER_ORDEN_EN_LA_POSICION_FMT = 'to position %d';
  SF_DESIGNER_ES_EL_FORM = 'nothing (it is the form itself)';

  // Restaura (Lsp.TodoONada): lo creado no se borra si algo no volvio (revisor
  // de la noche del 10-oct, A-1)
  SF_FOTO_LO_CREADO_SE_QUEDA =
    'left where it is: something that had to go back did not, and this ' +
    'file may be the only copy of it (the destination of a move whose ' +
    'origin could not be restored)';

  SF_DSGN_PARSER_FIN_DE_FICHERO =
    '(the end of the file)';
  // un error del parser que no nombra linea (un numero que no cabe)
  SF_DSGN_PARSER_SIN_LINEA =
    '(the parser names no line: look for the value its message quotes)';

  SR_DSGN_PARSER_YA_ROTO_FMT =
    '[DSGN-125 INVALID_PARAM] Nothing was written: %s is ALREADY ' +
    'unreadable by the IDE''s form parser, before this change: "%s" ' +
    '(line %d: %s). Fix that line first (delphi_edit), then repeat.';

  // Textos que estaban en linea en Lsp.DesignerBinding.pas (el resto, 27-sep-2026)
  SF_DSGN_REPITE_UN_NOMBRE_FMT =
    '%s (line %d of the .dfm) repeats a name already used in this form: ' +
    'loading it raises EComponentError';

  SF_DSGN_NO_TIENE_CAMPO_PUBLICADO_FMT =
    '%s: %s (line %d of the .dfm) has no published field in the class';

  SF_DSGN_QUEDADO_SIN_VALOR_FMT =
    '"%s" (line %d of the .dfm) has been left without a value: the .dfm ' +
    'is not valid and the linker rejects it without telling you which ' +
    'line';

  SF_DSGN_NO_ESTA_EN_PUBLISHED_FMT =
    '%s = %s (line %d of the .dfm): %s exists but is NOT in published; ' +
    'the form loader only sees published methods, so this blows up with ' +
    'EReadError when the window is created';

  SF_DSGN_METODO_NO_DECLARADO_FMT =
    '%s = %s (line %d of the .dfm): the method %s is not declared';

  SF_DSGN_CAMPO_SIN_OBJETO_FMT =
    '  published field with no object in the designer: %s';

  // Textos que estaban en linea en Lsp.Styles.pas (el resto, 27-sep-2026)
  SR_STYLE_NINGUN_ESTILO_STYLENAME_FMT =
    '[STYLE-036 NOT_FOUND] There is no style with StyleName ''%s'' in %s. ' +
    'See the names with command=view.';

  SR_STYLE_NO_TIENE_UNA_PARTE_FMT =
    '[STYLE-037 NOT_FOUND] The style ''%s'' has no part ''%s'' (child=%s). ' +
    'command=get shows it whole.';

  SR_STYLE_BINARIO_NO_SE_GUARDA_FMT =
    '[STYLE-035 DENIED] %s is a BINARY .dfm on disk: it is read on the ' +
    'fly but not saved that way. Convert it to text with delphi_designer ' +
    'command=to-text and repeat.';

  // Textos que estaban en linea en Mcp.Tools.Styles.pas (el resto, 27-sep-2026)
  SF_STYLE_BLOQUE_LINEAS_FMT =
    '%s (%s) lines %d-%d of %s:'#10 +
    '%s';

  SF_STYLE_CAMBIADA =
    'CHANGED';

  SF_STYLE_ANADIDA =
    'ADDED';

  // Textos que estaban en linea en Mcp.Tools.FileOps.pas (el resto, 27-sep-2026)
  SF_FILE_SIGUE_AHI_DESPUES_BORRARLO =
    'still there after deleting it';

  SF_FILE_TAMBIEN_A_PAPELERA =
    'also moved to the trash';

  SF_FILE_AL_MOVER_PAPELERA =
    'while moving to the trash';

  { Una unit cuyo form no se pudo mover: salia MOVED con la unit en su sitio
    nuevo, el form en el viejo y el .dpr re-apuntado (octava revision). }
  SR_MOVE_FORM_NO_VA_FMT =
    '[MOVE-017 DENIED] Its form %s could not go with the unit (%s): the unit ' +
    'is back at %s and no project was touched. Nothing was done.';

  { La causa de un MOVE-017 cuando el deshacer NO pudo devolverlo todo: va
    dentro de SYS-018, que dice que no todo volvio - el MOVE-017 entero
    decia "the unit is back... Nothing was done" debajo (decima revision). }
  SF_MOVE_FORM_NO_VA_FMT =
    'Its form %s could not go with the unit (%s).';

  { Un proyecto que no se deja re-apuntar (su .dpr o su .dproj en +R, abierto
    sin compartir): salia MOVED con la unit en su sitio nuevo y el proyecto
    apuntando al viejo, "ERROR" en una nota (medido en vivo, 28-sep-2026).
    Todo o nada, como su form (MOVE-017) y como borrarla (FILE-039). }
  SR_MOVE_PROYECTO_NO_VA_FMT =
    '[MOVE-019 DENIED] Project %s could not be re-pointed (%s): the unit ' +
    'is back at %s with its header and its designer file, and every ' +
    'project is as it was. Nothing was done.';

  { La causa de un MOVE-019 cuando el deshacer NO pudo devolverlo todo: va
    dentro de SYS-018, que dice lo que no volvio. }
  SF_MOVE_PROYECTO_NO_VA_FMT =
    'Project %s could not be re-pointed (%s).';

  SR_MOVE_UNIT_SOLO_SE_MUEVE_FMT =
    '[MOVE-010 INVALID_PARAM] A .pas unit can only be moved to another .pas ' +
    'name (%s).';

  SN_FILE_SIN_COPIA_DESDE_PAPELERA =
    '  [FILE-040] (no backup: the source was already in the trash, and a ' +
    'copy of a copy is not made)';

  SF_STYLE_LINEAS_Y_FMT =
    '%d and %d';

  SR_MOVE_ERROR_AL_COPIAR_FMT =
    '[MOVE-011 INTERNAL] Copy failed: %s';

  { La copia a medias de una carpeta, en su bajada, cuando ni ella se deja
    quitar (otro proceso tiene un fichero suyo): se dice donde queda
    (decima revision). }
  SF_MOVE_BAJADA_QUEDA_FMT =
    'The partial copy could not be removed: it is in %s (delete it with ' +
    'delphi_delete once nothing holds it).';

  SR_MOVE_ERROR_AL_MOVER_FMT =
    '[MOVE-012 INTERNAL] Move failed: %s';

  SK_MOVE_MOVIDO_FMT =
    '[MOVE-013] MOVED'#10 +
    '  from: %s'#10 +
    '  to:   %s';

  SK_MOVE_COPIADO_FMT =
    '[MOVE-014] COPIED'#10 +
    '  from: %s'#10 +
    '  to:   %s';

  SF_MOVE_COPIADO_CON_UNIT =
    'copied with the unit';

  SF_MOVE_MOVIDO_CON_UNIT =
    'moved with the unit';

  SN_MOVE_CABECERA_REESCRITA_FMT =
    '  [MOVE-015] header rewritten: unit %s;';

  SN_MOVE_ERROR_REESCRIBIR_CABECERA_FMT =
    '  [MOVE-016] ERROR rewriting the header (it still says unit %s;): %s';

  { La cabecera no se encontro (o ya decia otro nombre): no se toca y se
    dice. MOVE-015 decia "rewritten" sin mirar si cambio algo (decima). }
  SN_MOVE_CABECERA_NO_ENCONTRADA_FMT =
    '  [MOVE-018] header NOT rewritten: I did not find "unit %s" at the ' +
    'head of the file. Make it "unit %s;" with delphi_edit, or the build ' +
    'stops with E1038.';

  // Textos que estaban en linea en Lsp.Guard.pas (el resto, 27-sep-2026)
  SL_GUARD_WORKSPACE_JAIL_ROOTS_FMT =
    'Workspace jail (roots, %d): %s';

  SF_GUARD_RUTA_VACIA_O_RELATIVA =
    'empty or relative path';

  SF_GUARD_RUTA_INVALIDA =
    'invalid path';

  SF_GUARD_UNIDAD_O_RECURSO_ENTERO =
    'it is a whole drive or a whole network share';

  SF_GUARD_NO_DENTRO_DESECHABLE_FMT =
    'it is not inside a disposable folder (%s) and is not a temporary ' +
    'download';

  SF_GUARD_CONTIENE_LUGAR_PROTEGIDO_FMT =
    'it is or contains a protected location (%s)';

  // Textos que estaban en linea y se vieron al traducir (27-sep-2026)
  SF_MSGS_CABECERA_FMT =
    '===== MESSAGE %d/%d  (%s) =====';

  SF_DSGN_NO_EXISTE_SEGUN_FRAMEWORK_FMT =
    '"%s" does not exist in %s according to the framework (it publishes: %s)';

  { Bajando por una propiedad objeto la instancia puede ser de un
    descendiente del tipo declarado (TLabel.TextSettings declara
    TTextSettings, que no publica nada, y guarda un TLabelTextSettings): el
    aviso es para lo que no publica nadie de la familia. }
  SF_DSGN_NO_EXISTE_EN_LA_FAMILIA_FMT =
    '"%s" does not exist in %s nor in any class that descends from it, ' +
    'according to the framework (between them they publish: %s)';

  SF_DSGN_NO_ES_VALOR_FMT =
    '"%s" is not a value of %s; valid: %s';

  SL_SYS_PARADO_FMT =
    '%s v%s: stopped';

  SF_LOG_BASE64_FMT =
    '[base64: %d chars]';

  SF_GUARD_ESCRIBIR_FMT =
    'write %s';

  SF_DSGN_LINEA_AVISO_FMT =
    '  line %d: %s  ->  %s';

  SF_DSGN_SIN_SUBPROPIEDADES_FMT =
    '"%s" (%s) has no subproperties';

  SF_DSGN_ES_UN_SET_FMT =
    '%s is a SET: the values go between brackets, e.g. [%s]';

  SF_DSGN_NO_ES_ELEMENTO_FMT =
    '"%s" is not an element of %s';

  // ---------------------------------------------------------------------
  // Las ETIQUETAS de los mensajes (decision de David, 27-sep-2026)
  // ---------------------------------------------------------------------
  { Cada mensaje del catalogo EMPIEZA por [AREA-NNN] o, si es un rechazo o
    un fallo, por [AREA-NNN RESULTADO] con el code que publica
    structuredContent (DENIED, NOT_FOUND, INVALID_PARAM, INTERNAL). Las
    baterias, los agentes y el propio servidor reconocen el mensaje por su
    id y no por su frase, asi el texto se puede cambiar sin romper nada; y
    el resultado lo DECLARA quien escribe el mensaje, en vez de que
    ToolsManager lo adivine leyendo el texto. Al PRINCIPIO (David, 27-sep):
    al final no se leia con fiabilidad -un mensaje de varias lineas, un %s
    con saltos, un mensaje metido en otro, el eco de un fichero que cita
    etiquetas-; al principio, la respuesta declara su resultado en sus
    primeros caracteres y lo que viene detras no puede estorbar. Un solo
    lector del formato, el de abajo; el de las baterias
    (mcp_cliente.ETIQUETA) lo vigila test_catalogo contra este. }
  MSG_TAG_REGEX = '\[([A-Z]{2,6}-\d{3})(?: (DENIED|NOT_FOUND|INVALID_PARAM|INTERNAL))?\]';

  { MsgFmt con unos argumentos que no cuadran con los % del mensaje. }
  { EL fallo interno de una tool: la excepcion que nadie espero, envuelta por
    ToolsManager. Era un literal alli, y Lsp.Guard lo reconocia por su texto. }
  SR_SYS_TOOL_FAILED_FMT =
    '[SYS-006 INTERNAL] Error executing tool: %s';
  { Una excepcion que nadie esperaba, con su clase y su mensaje: salia como
    'ERROR: ...', que ninguna regla reconocia, y la tool daba EXITO (visto
    27-sep en delphi_edit; y en delphi_styles igual). }
  SR_FALLO_INTERNO_FMT =
    '[SYS-009 INTERNAL] ERROR: %s: %s';

  SR_FOTO_NO_VOLVIO_FMT =
    '[SYS-018 DENIED] It failed halfway and the undo could NOT put ' +
    'everything back: these files are NOT as they were before (each line ' +
    'says why):'#10 +
    '%s'#10 +
    'Look at them before anything else. What failed:'#10 +
    '%s';

  SF_FOTO_CAMBIADO_POR_OTRO =
    'someone else changed it after this operation wrote it; left as it ' +
    'is, so nothing of theirs was undone';

  SF_FOTO_CAMBIADO_DURANTE =
    'someone else changed it WHILE the operation was running; left as it ' +
    'is (it may hold part of this operation), so nothing of theirs was ' +
    'undone';
  { Los envoltorios de siempre, uno por forma: el motivo que trae otro
    sitio (una funcion que devuelve el porque, el mensaje de una excepcion)
    con la marca y el resultado de la respuesta. }
  SR_RECHAZADO_FMT =
    '[SYS-010 DENIED] %s';
  SR_ERROR_FMT =
    '[SYS-011 INVALID_PARAM] %s';
  SR_NO_EXISTE_FMT =
    '[SYS-012 NOT_FOUND] %s does not exist';
  { Los dos de ToolsManager antes de llegar a la tool: una peticion sin
    nombre de tool o sin argumentos legibles, y una tool que no existe.
    Salian como 'Error:', o sea INTERNAL: no se rompio nada, la llamada
    estaba mal. }
  SR_SYS_INVALID_TOOL_PARAMS =
    '[SYS-013 INVALID_PARAM] Invalid tool parameters';
  SR_SYS_TOOL_NOT_FOUND_FMT =
    '[SYS-014 NOT_FOUND] Tool not found: %s';

  SR_SYS_UNKNOWN_PARAM_FMT =
    '[SYS-015 INVALID_PARAM] Unknown parameter "%s". Valid parameters: ' +
    '%s.';

  SR_SYS_MISSING_PARAM_FMT =
    '[SYS-019 INVALID_PARAM] Missing "%s": this tool requires it ' +
    '(tools/list names it in "required"). Nothing was done. If your ' +
    'client''s tool list does not show it, the server was updated after ' +
    'you connected: reconnect the MCP session, or read the current ' +
    'contract with delphi_help command=tool.';

  SR_SYS_MISSING_METHOD_PARAM_FMT =
    '[SYS-026 INVALID_PARAM] Missing "%s": this method requires it. ' +
    'Nothing was done.';

  SR_FICHERO_OCUPADO_FMT =
    '[SYS-027 DENIED] Another process has the file open and does not ' +
    'share it (the IDE, a build, an antivirus...): close it or wait a ' +
    'moment, then repeat. Windows said: %s';

  { El error 5 de Windows, sin saber cual de sus tres causas es (la
    cuenta de ella la da MotivoDelSistema). Salia INTERNAL en unas tools
    y DENIED en otras (sexta revision). }
  SR_ACCESO_DENEGADO_FMT =
    '[SYS-028 DENIED] Windows refused access: %s. Usually one of three: ' +
    'it is marked read-only, another process holds it without sharing ' +
    'it, or this server''s account has no permission there. Repeating ' +
    'only helps in the second case.';

  { "arguments" que no es un objeto: se cambiaba en silencio por un objeto vacio y el
    agente leia "falta path" habiendolo mandado (dentro de un texto JSON,
    como lo mandan algunos puentes; sexta revision). }
  SR_SYS_ARGUMENTOS_NO_OBJETO_FMT =
    '[SYS-030 INVALID_PARAM] "arguments" has to be a JSON object ' +
    '({"path": ...}); it came as %s. Nothing was done.';
  SF_SYS_ARGS_TEXTO =
    'a string (a JSON encoded twice? send the object itself)';
  SF_SYS_ARGS_LISTA =
    'an array';
  SF_SYS_ARGS_OTRO =
    'a number or a boolean';

  { El atributo de SOLO LECTURA de un fichero que se iba a sustituir:
    se decia "otro proceso lo tiene, cierralo y repite" (EDIT-106) y el
    agente repetia para siempre (sexta revision, medido). }
  SR_SOLO_LECTURA_ATRIBUTO_FMT =
    '[SYS-029 DENIED] %s is marked READ-ONLY on disk (its read-only ' +
    'attribute is set). Nothing was written, moved or deleted. It is ' +
    'not a lock, so repeating will not help: the attribute has to be ' +
    'cleared first (this server does not clear it: it may be ' +
    'deliberate); to change its content meanwhile, work on a copy.';

  SR_SYS_METODO_NO_EXISTE_FMT =
    '[SYS-021 NOT_FOUND] Method "%s" does not exist here (or is not ' +
    'available).';

  { Un id que no es texto ni numero entero (1.5, 1e30, true, null, un
    objeto): 1.5 lanzaba dos veces y salia un 500 sin etiqueta; true o un
    objeto se tomaban por notificacion y el cliente esperaba para siempre
    (septima revision). MCP: el id no puede ser null. }
  SR_SYS_ID_NO_VALIDO =
    '[SYS-031 INVALID_PARAM] "id" has to be a string or a whole number ' +
    '(and not null). Nothing was done.';

  { "method" que no es texto: null buscaba el metodo "null" (septima
    revision). }
  SR_SYS_METODO_NO_TEXTO =
    '[SYS-032 INVALID_PARAM] "method" has to be the name of a method, ' +
    'as a string. Nothing was done.';

  SR_SYS_RECURSO_NO_EXISTE_FMT =
    '[SYS-022 NOT_FOUND] Resource "%s" does not exist (resources/list ' +
    'names the ones there are).';

  SR_SYS_RECURSO_ILEGIBLE_FMT =
    '[SYS-023 INTERNAL] Could not read resource "%s": %s';

  SR_SYS_JSON_INVALIDO =
    '[SYS-024 INVALID_PARAM] The request is not valid JSON.';

  SR_SYS_JSON_NO_OBJETO =
    '[SYS-025 INVALID_PARAM] A JSON-RPC request must be an object.';

  SE_SYS_SIN_REGISTRO =
    'The manager registry is not initialized.';

  SE_SYS_METODO_NO_ATENDIDO_FMT =
    'Method %s is not handled by %s.';

  SN_LIST_DIRS_CAPPED_FMT =
    '[LIST-013] Here are %d of %d folders. The next page is offset=%d.';

  SR_SYS_PARAM_VALUE_FMT =
    '[SYS-016 INVALID_PARAM] Parameter "%s": %s';

  SF_SYS_EXPECTED_WHOLE_FMT =
    'expected a whole number, got "%s".';

  SF_SYS_EXPECTED_TEXT =
    'expected a text (a JSON string), got a JSON array or object.';

  SF_SYS_NO_NEGATIVO_FMT =
    'a whole number that is not negative was expected, got "%s".';

  SF_SYS_EXPECTED_NUMBER_FMT =
    'expected a number, got "%s".';

  SF_SYS_EXPECTED_BOOL_FMT =
    'expected true or false, got "%s".';

  SF_SYS_INVALID_VALUE_FMT =
    'Invalid value "%s". Valid values: %s.';

  SF_SYS_OUT_OF_RANGE_FMT =
    'the number %s is outside the accepted range (%d..%d).';

  SR_SYS_UNAUTHORIZED =
    '[SYS-017 DENIED] Missing or invalid bearer token.';
  SL_MSG_FORMAT_FMT =
    'Message %s: the arguments do not match its format (%s): "%s"';

{ Los ids de las etiquetas que trae AText, en orden. }
function MsgIds(const AText: string): TArray<string>;
{ El id de la etiqueta de un mensaje del catalogo; '' si aun no la lleva. }
function MsgTag(const AMsg: string): string;
{ True si AText trae la etiqueta del mensaje AMsg del catalogo. Se compara
  con el id que lleva LA CONSTANTE, asi que el id se escribe en un solo
  sitio: HasMsg(Respuesta, SK_EDIT_WRITTEN). }
function HasMsg(const AText, AMsg: string): Boolean;
{ El resultado que declara el mensaje que ABRE el texto (una respuesta
  entera, lo que devuelve una funcion, lo que trae una excepcion): el de la
  etiqueta con la que EMPIEZA; '' si no empieza por una o si esa no declara
  ninguno (un exito). Un JSON empieza por { y no declara nada: lo decide su
  campo error (ToolsManager). }
function MsgOutcome(const AText: string): string;

{ EL paso de todo mensaje del catalogo hacia fuera (David, 27-sep-2026:
  para poder traducir un dia el mensaje de cada constante). Hoy devuelve el
  texto tal cual; cuando haya traducciones las buscara aqui, por el id de
  su etiqueta, y ninguna llamada tendra que cambiar. }
function MsgText(const AMsg: string): string;
{ Lo mismo con los argumentos de Format. Si no cuadran con los % del
  mensaje, no revienta la tool con una excepcion de conversion: devuelve
  el mensaje sin formatear con el motivo detras, y lo anota en el log. }
function MsgFmt(const AMsg: string; const AArgs: array of const): string;
{ Una lista para un mensaje, o "(none)" si esta vacia: estaba escrito a mano
  siete veces (IfThen(X = '', SF_NINGUNO, X); octava revision). }
function ONinguno(const ALista: string): string;
{ EL paso de una CAUSA por un envoltorio del catalogo (RECHAZADO: %s,
  error: %s, Error executing tool: %s...): si la causa ya es un mensaje
  que declara su resultado, sale tal cual (envolverla le quitaria la
  etiqueta y el resultado cambiaria: un <Exec> en delphi_test pasaba de
  DENIED a INVALID_PARAM); si no, se envuelve. Con AArgs, los argumentos
  del envoltorio cuando no son solo la causa (clase + mensaje). }
function MsgEnvuelve(const AMsg, ACausa: string): string; overload;
{ La negativa de un fallo del SISTEMA por su causa: ocupado (SYS-027),
  acceso denegado (SYS-028); '' si no es de esos. La usan los envoltorios
  y quien tiene el codigo de Windows en la mano (el rename de AtomicWrite). }
function MotivoDelSistema(const ACausa: string): string;
{ El TEXTO de un campo JSON que tiene que ser una cadena: '' si falta, es
  null o no es texto. El .Value de un null es 'null' y el de un numero su
  cifra: "method": null buscaba el metodo "null", "name": null la tool
  "null", y dos clientInfo.name null compartian la sesion "null" (buzon,
  papelera, confinamiento; septima revision). UN lector para los campos
  que manda el cliente. }
function CampoDeTexto(const AObj: TJSONValue; const ANombre: string): string;
function MsgEnvuelve(const AMsg, ACausa: string;
  const AArgs: array of const): string; overload;

{ Un envoltorio que CUENTA una causa (una tanda o un commit que se deshizo,
  un rename que no paso): el texto es el del envoltorio, pero el RESULTADO
  es el de la causa - una tanda que cae porque un ancla no esta es
  NOT_FOUND, no el DENIED del envoltorio (revision 27-sep-2026). Sin
  resultado en la causa, se queda el del envoltorio. }
function MsgConCausa(const AMsg, ACausa: string;
  const AArgs: array of const): string;
{ "El que llama se equivoco": una EArgumentException, que es como el
  deserializador dice que la llamada esta mal - salvo EArgumentOutOfRange-
  Exception, que la RTL hereda de ella y es un indice fuera de rango DENTRO del
  servidor, lo inesperado. UN lector para los dos que lo preguntan (el gestor
  de tools y el procesador JSON-RPC: la regla estaba escrita en uno solo;
  verificacion de la tercera ronda). AExcepcion es una Exception. }
function EsFalloDelLlamador(AExcepcion: TObject): Boolean;
{ Lo que sale de una excepcion CAPTURADA: si su mensaje ya declara un
  resultado (un SR_ lanzado a proposito: el que llama se equivoco, algo no
  existe), sale tal cual; si no, es lo inesperado - INTERNAL, con la clase.
  Un criterio para todos los "on E: Exception": cada tool envolvia con un
  generico distinto y la misma causa salia DENIED, INVALID_PARAM o INTERNAL
  segun quien la cogiera (revision 27-sep-2026). }
function MsgExcepcion(const AClase, AMensaje: string): string;
{ Un rechazo: DENIED, NOT_FOUND o INVALID_PARAM. }
function EsRechazo(const AText: string): Boolean;
{ Cualquier resultado de error, INTERNAL incluido. }
function EsFallo(const AText: string): Boolean;
{ True si AText EMPIEZA por la etiqueta de la constante AMsg: "este
  resultado ES ese mensaje" (un eco que venga detras no cuenta). }
function EsMsg(const AText, AMsg: string): Boolean;
{ El texto SIN la etiqueta que lo abre (ni el blanco de detras): para mirar
  como sigue un mensaje, p. ej. la marca *** de un aviso del motor. }
function MsgCuerpo(const AText: string): string;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.RegularExpressions,
  MCPServer.Logger,
  Lsp.Regex;

function MsgIds(const AText: string): TArray<string>;
begin
  Result := [];
  for var M in TRegEx.Matches(AText, MSG_TAG_REGEX) do
    Result := Result + [M.Groups[1].Value];
end;

function MsgTag(const AMsg: string): string;
var
  Ids: TArray<string>;
begin
  Ids := MsgIds(AMsg);
  if Length(Ids) > 0 then
    Result := Ids[0]
  else
    Result := '';
end;

function HasMsg(const AText, AMsg: string): Boolean;
var
  Tag: string;
begin
  Result := False;
  Tag := MsgTag(AMsg);
  if Tag <> '' then
    for var Id in MsgIds(AText) do
      if Id = Tag then
        Exit(True);
end;

function MsgOutcome(const AText: string): string;
var
  M: TMatch;
begin
  Result := '';
  // la etiqueta que ABRE el texto, y solo esa: lo que venga detras (un
  // mensaje anidado, un eco, un fichero leido) no declara nada
  M := TRegEx.Match(AText, '^\s*' + MSG_TAG_REGEX);
  // el resultado es un grupo opcional: GrupoDe (Lsp.Regex)
  Result := GrupoDe(M, 2);
end;

function MsgText(const AMsg: string): string;
begin
  Result := AMsg;
end;

function ONinguno(const ALista: string): string;
begin
  if ALista.Trim = '' then
    Result := MsgText(SF_NINGUNO)
  else
    Result := ALista;
end;

function MsgFmt(const AMsg: string; const AArgs: array of const): string;
begin
  try
    // la etiqueta del mensaje va delante: un mensaje metido en otro por un
    // %s, o un dato que cite etiquetas, quedan DETRAS y no estorban (antes,
    // con la etiqueta al final, aqui se borraban... y con ellas las de los
    // datos: el eco de un ancla de Lsp.Texts salia mutilado)
    Result := Format(MsgText(AMsg), AArgs);
  except
    on E: Exception do
    begin
      Result := MsgText(AMsg) + ' (' + E.Message + ')';
      TLogger.Error(Format(SL_MSG_FORMAT_FMT, [MsgTag(AMsg), E.Message, Copy(AMsg, 1, 60)]));
    end;
  end;
end;

function MsgEnvuelve(const AMsg, ACausa: string): string;
begin
  Result := MsgEnvuelve(AMsg, ACausa, [ACausa]);
end;

function EsFalloDelLlamador(AExcepcion: TObject): Boolean;
begin
  Result := (AExcepcion is EArgumentException) and
    not (AExcepcion is EArgumentOutOfRangeException);
end;

function CampoDeTexto(const AObj: TJSONValue; const ANombre: string): string;
var
  V: TJSONValue;
begin
  Result := '';
  if not (AObj is TJSONObject) then
    Exit;
  V := TJSONObject(AObj).GetValue(ANombre);
  if V is TJSONString then
    Result := TJSONString(V).Value;
end;

{ Un fichero que otro proceso tiene abierto sin compartir: la causa trae el
  texto del sistema (el de SysErrorMessage, en el idioma de Windows) y ningun
  resultado. Era INTERNAL en cada tool que lo cogia (verificacion de la
  tercera ronda): se reconoce AQUI, donde toda causa se envuelve. }
{ Lo que Windows dijo, en el mensaje con etiqueta que le toca, o '' si la
  causa no es de las suyas conocidas: EL clasificador de "el sistema no
  dejo". Solo reconocia 32 y 33; el 5 salia INTERNAL (SYS-006, MOVE-012). }
function MotivoDelSistema(const ACausa: string): string;
begin
  Result := '';
  if ACausa.Contains(SysErrorMessage(32).Trim) or   // ERROR_SHARING_VIOLATION
     ACausa.Contains(SysErrorMessage(33).Trim) then // ERROR_LOCK_VIOLATION
    Result := MsgFmt(SR_FICHERO_OCUPADO_FMT, [ACausa.Trim])
  else if ACausa.Contains(SysErrorMessage(5).Trim) then // ERROR_ACCESS_DENIED
    Result := MsgFmt(SR_ACCESO_DENEGADO_FMT, [ACausa.Trim]);
end;

function MsgEnvuelve(const AMsg, ACausa: string;
  const AArgs: array of const): string;
begin
  if not EsFallo(ACausa) and (MotivoDelSistema(ACausa) <> '') then
    Exit(MotivoDelSistema(ACausa));
  if EsFallo(ACausa) then
    Result := ACausa
  else
    Result := MsgFmt(AMsg, AArgs);
end;

function MsgConCausa(const AMsg, ACausa: string;
  const AArgs: array of const): string;
var
  O: string;
  M: TMatch;
begin
  Result := MsgFmt(AMsg, AArgs);
  O := MsgOutcome(ACausa);
  if O = '' then
    Exit;
  M := TRegEx.Match(Result, '^(\s*)' + MSG_TAG_REGEX);
  if M.Success then
    Result := M.Groups[1].Value + '[' + M.Groups[2].Value + ' ' + O + ']' +
      Copy(Result, M.Index + M.Length, MaxInt);
end;

function MsgExcepcion(const AClase, AMensaje: string): string;
begin
  Result := MsgEnvuelve(SR_FALLO_INTERNO_FMT, AMensaje, [AClase, AMensaje]);
end;

function EsRechazo(const AText: string): Boolean;
begin
  Result := MatchStr(MsgOutcome(AText), ['DENIED', 'NOT_FOUND', 'INVALID_PARAM']);
end;

function EsFallo(const AText: string): Boolean;
begin
  Result := MsgOutcome(AText) <> '';
end;

function MsgCuerpo(const AText: string): string;
begin
  Result := TRegEx.Replace(AText, '^\s*' + MSG_TAG_REGEX + '\s*', '');
end;

function EsMsg(const AText, AMsg: string): Boolean;
var
  M: TMatch;
begin
  M := TRegEx.Match(AText, '^\s*' + MSG_TAG_REGEX);
  Result := M.Success and (MsgTag(AMsg) <> '') and (M.Groups[1].Value = MsgTag(AMsg));
end;

end.
