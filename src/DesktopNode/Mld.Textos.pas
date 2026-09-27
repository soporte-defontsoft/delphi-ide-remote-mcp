unit Mld.Textos;

{ EL catalogo de mensajes del nodo de escritorio y del lanzador (McpRunJob):
  los dos programas que corren en la maquina DESTINO. No enlazan Lsp.Texts
  (es del servidor y arrastra su logger), asi que tienen el suyo, con las
  mismas reglas (David, 27-sep-2026): una constante por mensaje, la etiqueta
  al PRINCIPIO de su texto (areas NODE y JOB; con el resultado si es un
  rechazo), textos en ingles, y todo sale por MsgText/MsgFmt, el sitio
  unico de salida. test_catalogo vigila los dos catalogos: un id no se repite.
  Las marcas que el SERVIDOR lee de la salida (NodeProtocolo.inc, las
  lineas de ventanas, ___RC=, ___ENV=) no son mensajes y no estan aqui. }

interface

const
  SN_NODE_VENTANAS_FALLO_LISTA_FMT =
    '  [NODE-001] windows: the list failed (%s)';

  SN_NODE_CONTROL_ESCRITORIO_WINDOWS =
    '[NODE-002] McpDesktop - Windows desktop control node';

  SN_NODE_ESCRITORIO_PIXELES_ESCALA_FMT =
    '  [NODE-003] desktop %dx%d pixels, scale %s';

  SN_NODE_VENTANAS_LISTA_CAPTURA =
    '  [NODE-004] windows: the list comes with the screenshot below';

  SN_NODE_NO_PUDE_PULSAR_CAMPO_FMT =
    '  [NODE-005] Could not click on the field: %s';

  SK_NODE_ESCRITO_EN_PIXEL_FMT =
    '  [NODE-006] WRITTEN "%s" at pixel (%d,%d) (typed; the focus is NOT ' +
    'verified: check it on the screenshot)';

  SN_NODE_PULSE_BIEN_NO_ESCRIBIR_FMT =
    '  [NODE-007] The click worked but I could not type: %s';

  SK_NODE_ESCRITO_TECLEADO_FMT =
    '  [NODE-008] WRITTEN: %s (typed; the focus is NOT verified: check ' +
    'it on the screenshot)';

  SN_NODE_NO_PUDE_ESCRIBIR_FMT =
    '  [NODE-009] Could not type: %s';

  SN_NODE_NO_CONOZCO_TECLA_FMT =
    '  [NODE-010] Unknown key %s';

  SN_NODE_NO_ENVIAR_TECLA_FMT =
    '  [NODE-011] Could not send the key: %s';

  SK_NODE_ALT_TAB_ENVIADO =
    '  [NODE-012] ALT+TAB sent';

  SK_NODE_TECLA_ENVIADA_FMT =
    '  [NODE-044] KEY %s%s sent';

  SF_NODE_CON_MODIFICADORES_FMT =
    ' with %d modifier(s)';

  SN_NODE_RESPALDO_FMT =
    '  [NODE-045] FALLBACK: %s';

  SF_NODE_ESTADO_FMT =
    '  STATE: %s';

  SF_NODE_AUSENTE_FMT =
    '     MISSING %s (%s)';

  SN_NODE_NO_ENVIAR_ALT_TAB_FMT =
    '  [NODE-013] Could not send Alt+Tab: %s';

  SK_NODE_CLIC_EN_PIXEL_FMT =
    '  [NODE-014] CLICK at pixel (%d,%d) of the screenshot';

  SN_NODE_NO_PUDE_PULSAR_FMT =
    '  [NODE-015] Could not click: %s';

  SN_NODE_USO_ENUMERA_VENTANAS =
    '  [NODE-016] usage: <x> <y>   click that pixel of the screenshot' +
    sLineBreak +
    '                  altab     switch window with the keyboard' +
    sLineBreak +
    '                  tecla <t> press a key (escape, enter, tab, ' +
    'super...)' +
    sLineBreak +
    '                  texto <t> type that text wherever the focus is' +
    sLineBreak +
    '                  escribe <x> <y> <t>  click there AND type: a ' +
    'single trip' +
    sLineBreak +
    '                  ventanas  list the visible windows with their ' +
    'position';

  SN_NODE_NODO_LISTO =
    '[NODE-017] node ready';

  SN_NODE_NO_RECOGER_CAPTURA_FMT =
    '  [NODE-018] Warning: could not collect the screenshot (%s)';

  SN_NODE_NO_SE_PUDO_ABRIR_FMT =
    '  [NODE-019] %-16s COULD NOT OPEN: %s';

  SN_NODE_ABIERTA_SIMBOLOS_FMT =
    '  [NODE-020] %-16s open, symbols %d/%d';

  SN_NODE_VENTANAS_SIN_OJOS_FMT =
    '  [NODE-021] windows: no X11 eyes (%s)';

  SN_NODE_VENTANAS_NO_ENUMERARLAS_FMT =
    '  [NODE-022] windows: could not enumerate them (%s)';

  SN_NODE_VENTANAS_SIN_CONVERTIR =
    '  [NODE-023] windows: could not read the screenshot size; X11 ' +
    'coordinates not converted';

  SN_NODE_NATIVAS_WAYLAND_NO_SALEN =
    '  [NODE-024] (X11/Xwayland windows: native Wayland windows do not ' +
    'appear in the list)';

  SN_NODE_VENTANAS_FALLO_LISTA_CLASE_FMT =
    '  [NODE-025] windows: the list failed (%s: %s)';

  SN_NODE_CONTROL_ESCRITORIO_LINUX =
    '[NODE-026] McpDesktop - Linux desktop control node';

  SN_NODE_LIBRERIAS_DEL_SISTEMA =
    '[NODE-027] -- 1. system libraries (nothing to install) --';

  SN_NODE_NO_HAY_ESCRITORIO_FMT =
    '[NODE-028] NO desktop to talk to: %s';

  SN_NODE_PANTALLA_ESCALA_CAPTURA =
    '[NODE-029] -- 2. the screen: scale and screenshot --';

  SN_NODE_ESCRITORIO_DICE_ESCALA_FMT =
    '  [NODE-030] The desktop says its scale is %s';

  SN_NODE_NO_LEER_ESCALA_FMT =
    '  [NODE-031] Could not read the scale, assuming 1.00: %s';

  SN_NODE_LAS_MANOS =
    '[NODE-032] -- 3. the hands --';

  SN_NODE_NO_PREPARAR_CANAL_FMT =
    '  [NODE-033] Could not prepare the channel: %s';

  SN_NODE_NO_ABRIR_CANAL_FMT =
    '  [NODE-034] Could not open the channel: %s';

  SN_NODE_CANAL_NO_LISTO_FMT =
    '  [NODE-035] The channel never became ready: %s';

  SN_NODE_LISTAS_PANTALLA_LOGICA_FMT =
    '  [NODE-036] ready. logical screen %dx%d, scale %s';

  SK_NODE_SUPER_ENVIADO =
    '  [NODE-037] SUPER sent: overview of all the windows';

  SN_NODE_NO_ABRIR_VISTA_FMT =
    '  [NODE-038] Could not open the overview: %s';

  SK_NODE_ESCRITO_PIXEL_MAPA_FMT =
    '  [NODE-039] WRITTEN "%s" at pixel (%d,%d)  [%s] (typed; the focus ' +
    'is NOT verified: check it on the screenshot)';

  SK_NODE_ESCRITO_TECLEADO_MAPA_FMT =
    '  [NODE-040] WRITTEN: %s  [%s] (typed; the focus is NOT verified: ' +
    'check it on the screenshot)';

  SN_NODE_USO_TECLA_EVDEV =
    '  [NODE-041] usage: <x> <y>   click that pixel of the screenshot' +
    sLineBreak +
    '                  altab     switch window with the keyboard' +
    sLineBreak +
    '                  tecla <n> press a key (evdev: Escape 1, Enter 28)' +
    sLineBreak +
    '                  texto <t> type that text wherever the focus is' +
    sLineBreak +
    '                  escribe <x> <y> <t>  click there AND type: a ' +
    'single trip' +
    sLineBreak +
    '                  ventanas  show ALL the windows (Super key),' +
    sLineBreak +
    '                            for when they cover each other' +
    sLineBreak +
    '  (to give a window the focus, click its title bar)';

  SN_NODE_NO_SE_USA_MANO =
    '[NODE-042] McpDesktopNode - desktop node of the Delphi IDE Remote ' +
    'MCP.' +
    sLineBreak +
    '  This program is not run by hand: the MCP server launches it, and' +
    sLineBreak +
    '  the server decides (per workspace) whether an agent may see and ' +
    'touch' +
    sLineBreak +
    '  this desktop. Without that call it does nothing.';

  SN_NODE_TODAVIA_NO_TIENE_MANOS =
    '[NODE-043] McpDesktop - this system has no hands in the node yet' +
    sLineBreak +
    '  (today: Linux with GNOME, and Windows; macOS would be next)';

  SR_JOB_FORK_VIGIA_FALLO =
    '[JOB-001 INTERNAL] Fork of the watcher failed';

  SR_JOB_FORK_PROGRAMA_FALLO =
    '[JOB-002 INTERNAL] Fork of the program failed';

  SR_JOB_NO_PUDE_ENTRAR_FMT =
    '[JOB-003 INTERNAL] Could not enter %s: %s';

  SR_JOB_NO_PUDE_ARRANCAR_FMT =
    '[JOB-004 INTERNAL] Could not start %s: %s';

  SR_JOB_KILL_NECESITA_ID =
    '[JOB-005 INVALID_PARAM] @kill needs the id of one of this server''s ' +
    'jobs.';

  SN_JOB_NINGUN_TRABAJO_VIVO_FMT =
    '[JOB-006] No job %s is alive in this folder: either it already ' +
    'ended, or it was not from this project.';

  SK_JOB_TERMINADO_EL_TRABAJO_FMT =
    '[JOB-007] Job %s terminated (pid %d from %s, %s).';

  SN_JOB_NO_PUDE_MATAR_FMT =
    '[JOB-008] Could not kill job %s (pid %d): %s - %s';

  SR_JOB_NO_EXISTE_FMT =
    '[JOB-009 NOT_FOUND] %s does not exist in this project''s deployed ' +
    'folder on the target.';

  SR_JOB_NO_EJECUTABLE_NATIVO_FMT =
    '[JOB-010 DENIED] %s is not a native executable (ELF/PE): only the ' +
    'binary that delphi_build produced is run.';

  // Textos que estaban en linea en Mld.DBus.pas (el resto, 27-sep-2026)
  SF_NODE_FALTA_EN_FMT =
    'missing %s in %s (%s)';

  

  SF_NODE_BUS_NO_DEVOLVIO_CONEXION =
    'the bus returned no connection (no DBUS_SESSION_BUS_ADDRESS?)';

  SF_NODE_NO_HAY_CONEXION_BUS =
    'no connection to the bus';

  SF_NODE_BUS_NO_RESPONDIO =
    'the bus did not answer';

  SF_NODE_RESPUESTA_SIN_ARGUMENTOS =
    'reply without arguments';

  SF_NODE_ESPERABA_ARRAY_CADENAS =
    'an array of strings was expected';

  SF_NODE_ESCRITORIO_NO_RESPONDIO =
    'the desktop did not answer';

  SF_NODE_TERCER_ARGUMENTO_NO_ARRAY =
    'the third argument is not the array of logical monitors';

  SF_NODE_NO_ANADIR_ARGUMENTO =
    'could not add an argument';

  SF_NODE_CREATESESSION_SIN_RUTA_SESION =
    'CreateSession returned no session path';

  SF_NODE_NO_ABRIR_DICCIONARIO =
    'could not open the dictionary';

  SF_NODE_CREATESESSION_NO_DEVOLVIO_RUTA =
    'CreateSession returned no path';

  SF_NODE_NO_LEER_SESSIONID =
    'could not read SessionId';

  SF_NODE_SCREENCAST_NO_DEVOLVIO_RUTA =
    'ScreenCast.CreateSession returned no path';

  SF_NODE_CONNECTTOEIS_NO_DEVOLVIO_NADA =
    'ConnectToEIS returned nothing';

  SF_NODE_CONNECTTOEIS_DEVOLVIO_TIPO_FMT =
    'ConnectToEIS returned type %d, a descriptor was expected';

  SF_NODE_DESCRIPTOR_NO_VALIDO =
    'the received descriptor is not valid';

  SF_NODE_NO_SUSCRIBIRME_RESPUESTA_FMT =
    'could not subscribe to the reply: %s';

  SF_NODE_PORTAL_SIN_OBJETO_PETICION =
    'the portal returned no request object';

  SF_NODE_PORTAL_RECHAZO_CAPTURA_FMT =
    'the portal refused the screenshot (code %d)';

  SF_NODE_RESPUESTA_SIN_RESULTADOS =
    'the reply carries no results';

  SF_NODE_RESPUESTA_SIN_DIRECCION =
    'the reply does not carry the file URI';

  SF_NODE_NO_ENTIENDO_DIRECCION_FMT =
    'I do not understand the URI %s';

  SF_NODE_PORTAL_QUEDO_CALLADO_FMT =
    'the portal stayed silent for %d ms: neither a reply nor an error. ' +
    'Most likely it never got to show the screen capture permission ' +
    'dialog (this happens in a remote session or with the screen ' +
    'locked). Ask the operator to grant screen capture ONCE on that ' +
    'machine, sitting in front of the screen; after that this works ' +
    'silently';

  // Textos que estaban en linea en Mld.Eis.pas (el resto, 27-sep-2026)
  SF_NODE_DESCRIPTOR_INVALIDO =
    'invalid descriptor';

  

  SF_NODE_NO_DEVOLVIO_CONTEXTO =
    'ei_new_sender returned no context';

  SF_NODE_BACKEND_FD_DEVOLVIO_FMT =
    'ei_setup_backend_fd returned %d';

  SF_NODE_DISPOSITIVOS_NO_LISTOS_FMT =
    'the devices did not become ready within %d ms (pointer=%s ' +
    'keyboard=%s)';

  SF_NODE_CANAL_NO_ESTA_LISTO =
    'the channel is not ready';

  SF_NODE_CAE_FUERA_PANTALLA_FMT =
    '(%s,%s) of the screenshot falls outside the screen (scale %s, ' +
    'region %dx%d)';

  SF_NODE_TECLADO_TABLA_FIJA =
    'keyboard: fixed table (US)';

  SF_NODE_LIBEI_NO_ENTREGA_MAPA =
    ' - this libei does not provide the keymap';

  SF_NODE_ESCRITORIO_NO_ENTREGO_MAPA =
    ' - the desktop did not provide its keymap';

  SF_NODE_NO_LEER_MAPA_ESCRITORIO =
    ' - could not read the desktop keymap';

  SF_NODE_TECLADO_DEL_ESCRITORIO_FMT =
    'keyboard: the desktop''s own (%s, %d characters)';

  SF_NODE_ESCRITORIO_NO_DIO_TECLADO =
    'the desktop provided no keyboard';

  SF_NODE_TECLADO_SIN_TECLA_FMT =
    'the desktop keyboard (%s) has no key that gives the character "%s" ' +
    '(position %d), neither directly nor through a dead key (%d dead ' +
    'keys in the map)';

  SF_NODE_NO_SE_TECLEAR_FMT =
    'I do not know how to type the character "%s" (position %d)';

  // Textos que estaban en linea en Mld.DBus.pas (el resto, 27-sep-2026)
  SF_NODE_NO_CONSTRUIR_MENSAJE =
    'could not build the message';

  SF_NODE_SIN_RESPUESTA =
    'no reply';

  // Textos que estaban en linea en Mld.X11.pas (el resto, 27-sep-2026)
  SF_NODE_NO_PUDE_MIRAR_FMT =
    'could not look into %s: %s';

  SF_NODE_SIN_CONEXION_X11 =
    'no connection to X11';

  SF_NODE_NO_LEER_ARBOL_X11 =
    'could not read the X11 window tree';

  SF_NODE_VENTANA_YA_NO_EXISTE =
    'that window no longer exists';

  SF_NODE_VENTANA_NO_VISIBLE =
    'the window is not visible: there is nothing to capture';

  SF_NODE_XGETIMAGE_SIN_IMAGEN =
    'XGetImage returned no image (window covered or without backing ' +
    'store)';

  SF_NODE_XWAYLAND_SIN_AUTORIZACION =
    'There is a Wayland session but I cannot find the Xwayland ' +
    'authorization (.mutter-Xwaylandauth.*). Ask the operator to open ' +
    'some application in that session, or check that Xwayland is active.';

  SF_NODE_SESION_SIN_CONECTAR =
    'There is a graphical session, but I could not connect to it.';

  SF_NODE_PUNTERO_FUERA_PANTALLA =
    'the pointer is not on this screen';

  // Textos que estaban en linea en Mld.Win.pas (el resto, 27-sep-2026)
  SF_NODE_ESCRITORIO_ENTRADA_NO_ABRIR_FMT =
    'input desktop: could not be opened (%s)';

  SF_NODE_ESCRITORIO_ENTRADA_FMT =
    'input desktop: %s';

  SF_NODE_ESCRITORIO_ENTRADA_SIN_NOMBRE =
    'input desktop: no name';

  SF_NODE_SESION_REMOTA =
    '; remote session';

  SF_NODE_SESION_CONSOLA =
    '; console session';

  SF_NODE_FOCO_EN_FMT =
    '; focus on "%s"';

  SF_NODE_SIN_VENTANA_FOCO =
    '; no window has the focus';

  SF_NODE_NO_ABRIR_CONTEXTO_PANTALLA =
    'could not open the screen context';

  SF_NODE_NO_CREAR_CONTEXTO_MEMORIA =
    'could not create the memory context';

  SF_NODE_NO_RESERVAR_IMAGEN =
    'could not allocate the image';

  SF_NODE_CON_CAPTUREBLT_FMT =
    'with CAPTUREBLT: %s [%d]';

  SF_NODE_COPIA_PANTALLA_FALLO_FMT =
    'the screen copy failed (%s; without it: %s [%d]; %s)';

  SF_NODE_PRINTWINDOW_PORQUE_FMT =
    'PrintWindow window by window, because %s';

  SF_NODE_SISTEMA_ACEPTO_ENTRADAS_FMT =
    'the system accepted %d of %d inputs (%s)';

  SF_NODE_PIXEL_FUERA_CAPTURA_FMT =
    'pixel (%d,%d) is outside the screenshot (%dx%d)';

  // Textos que estaban en linea en Mld.Teclado.pas (el resto, 27-sep-2026)
  SF_NODE_ESCRITORIO_SIN_MAPA_TECLADO =
    'the desktop provided no keymap';

  SF_NODE_NO_ABRIR_LIBXKBCOMMON_FMT =
    'could not open libxkbcommon.so.0 (%s)';

  SF_NODE_XKB_CONTEXT_NEW_NIL =
    'xkb_context_new returned nil';

  SF_NODE_XKB_NO_ENTENDIO_MAPA =
    'libxkbcommon did not understand the desktop keymap';

  SF_NODE_MAPA_SIN_CARACTERES =
    'the desktop keymap carries no characters';

  // Textos que estaban en linea en Mld.Captura.pas (el resto, 27-sep-2026)
  SF_NODE_NO_LEER_IMAGEN_VENTANA_FMT =
    'could not read the window image: %s';

  SF_NODE_VENTANA_SIN_PIXELES =
    'the window returned no pixels';

  SF_NODE_FORMATO_PIXEL_NO_CONTEMPLADO_FMT =
    'unsupported pixel format: %d bits';

  SF_NODE_NO_ESCRIBIR_PNG_FMT =
    'could not write the PNG to %s';

  // Textos que estaban en linea en Mld.Sesion.pas (el resto, 27-sep-2026)
  SF_NODE_SIN_SESION_GRAFICA_FMT =
    'There is NO open graphical session of user %s on this machine. Ask ' +
    'the operator to log in to the desktop (or open a remote session) as ' +
    'that user and try again: without a desktop there is nothing to see ' +
    'or to click.';

  // Textos que estaban en linea en Mld.Dyn.pas (el resto, 27-sep-2026)
  SF_NODE_LIBRERIA_NO_ABIERTA =
    'the library is not open';

  // Textos que estaban en linea en McpRunJob.dpr (el resto, 27-sep-2026)
  SF_JOB_SIGKILL_NO_ATENDIO =
    'SIGKILL (it did not honor SIGTERM within 3 s)';

  SF_JOB_PID_DE_OTRO_PROGRAMA =
    'that pid now belongs to another program, outside this folder: left ' +
    'untouched';

  SF_JOB_NO_ABRIR_SALIDA_FMT =
    'could not open the output %s';

  SF_JOB_NOMBRE_DEL_VIGIA =
    'the watcher''s name';

  SR_JOB_EXCEPCION_FMT =
    '[JOB-011 INTERNAL] %s: %s';

  // Textos que estaban en linea en Mld.X11.pas (el resto, 27-sep-2026)
  SF_NODE_NO_HAY_LIB_FMT =
    'there is no %s on this machine: %s';

function MsgText(const AMsg: string): string;
function MsgFmt(const AMsg: string; const AArgs: array of const): string;

implementation

uses
  System.SysUtils;

function MsgText(const AMsg: string): string;
begin
  Result := AMsg;
end;

{ Si los argumentos no cuadran con los % del mensaje, el mensaje sin
  formatear con el motivo detras: nunca una excepcion en mitad del nodo. }
function MsgFmt(const AMsg: string; const AArgs: array of const): string;
begin
  try
    Result := Format(MsgText(AMsg), AArgs);
  except
    on E: Exception do
      Result := MsgText(AMsg) + ' (' + E.Message + ')';
  end;
end;

end.
