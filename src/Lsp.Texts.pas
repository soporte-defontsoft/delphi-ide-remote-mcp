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
  SERVER_VERSION = '0.17.0-beta';

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
