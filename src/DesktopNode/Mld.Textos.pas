unit Mld.Textos;

{ EL catalogo de mensajes del nodo de escritorio y del lanzador (McpRunJob):
  los dos programas que corren en la maquina DESTINO. No enlazan Lsp.Texts
  (es del servidor y arrastra su logger), asi que tienen el suyo, con las
  mismas reglas (David, 27-sep-2026): una constante por mensaje, la etiqueta
  al final de su texto (areas NODE y JOB; con el resultado si es un
  rechazo), y todo sale por MsgText/MsgFmt, el sitio donde entrara la
  traduccion. test_catalogo vigila los dos catalogos: un id no se repite.
  Las marcas que el SERVIDOR lee de la salida (NodeProtocolo.inc, las
  lineas de ventanas, ___RC=, ___ENV=) no son mensajes y no estan aqui. }

interface

const
  SN_NODE_VENTANAS_FALLO_LISTA_FMT =
    '  ventanas: fallo la lista (%s) [NODE-001]';

  SN_NODE_CONTROL_ESCRITORIO_WINDOWS =
    'McpDesktop - nodo de control del escritorio Windows [NODE-002]';

  SN_NODE_ESCRITORIO_PIXELES_ESCALA_FMT =
    '  escritorio %dx%d pixeles, escala %s [NODE-003]';

  SN_NODE_VENTANAS_LISTA_CAPTURA =
    '  ventanas: la lista va con la captura de abajo [NODE-004]';

  SN_NODE_NO_PUDE_PULSAR_CAMPO_FMT =
    '  no pude pulsar en el campo: %s [NODE-005]';

  SK_NODE_ESCRITO_EN_PIXEL_FMT =
    '  ESCRITO "%s" en el pixel (%d,%d) (tecleado; el foco NO se ' +
    'verifica: comprueba con la captura) [NODE-006]';

  SN_NODE_PULSE_BIEN_NO_ESCRIBIR_FMT =
    '  pulse bien pero no pude escribir: %s [NODE-007]';

  SK_NODE_ESCRITO_TECLEADO_FMT =
    '  ESCRITO: %s (tecleado; el foco NO se verifica: comprueba con la ' +
    'captura) [NODE-008]';

  SN_NODE_NO_PUDE_ESCRIBIR_FMT =
    '  no pude escribir: %s [NODE-009]';

  SN_NODE_NO_CONOZCO_TECLA_FMT =
    '  no conozco la tecla %s [NODE-010]';

  SN_NODE_NO_ENVIAR_TECLA_FMT =
    '  no pude enviar la tecla: %s [NODE-011]';

  SK_NODE_ALT_TAB_ENVIADO =
    '  ALT+TAB enviado [NODE-012]';

  SN_NODE_NO_ENVIAR_ALT_TAB_FMT =
    '  no pude enviar Alt+Tab: %s [NODE-013]';

  SK_NODE_CLIC_EN_PIXEL_FMT =
    '  CLIC en el pixel (%d,%d) de la captura [NODE-014]';

  SN_NODE_NO_PUDE_PULSAR_FMT =
    '  no pude pulsar: %s [NODE-015]';

  SN_NODE_USO_ENUMERA_VENTANAS =
    '  uso: <x> <y>   pulsa en ese pixel de la captura' + sLineBreak +
    '       altab     cambia de ventana con el teclado' + sLineBreak +
    '       tecla <t> pulsa una tecla (escape, enter, tab, super...)' + sLineBreak +
    '       texto <t> escribe ese texto donde este el foco' + sLineBreak +
    '       escribe <x> <y> <t>  pulsa ahi Y escribe: un solo viaje' + sLineBreak +
    '       ventanas  enumera las ventanas visibles con su sitio [NODE-016]';

  SN_NODE_NODO_LISTO =
    'nodo listo [NODE-017]';

  SN_NODE_NO_RECOGER_CAPTURA_FMT =
    '  aviso: no pude recoger la captura (%s) [NODE-018]';

  SN_NODE_NO_SE_PUDO_ABRIR_FMT =
    '  %-16s NO SE PUDO ABRIR: %s [NODE-019]';

  SN_NODE_ABIERTA_SIMBOLOS_FMT =
    '  %-16s abierta, simbolos %d/%d [NODE-020]';

  SN_NODE_VENTANAS_SIN_OJOS_FMT =
    '  ventanas: sin ojos X11 (%s) [NODE-021]';

  SN_NODE_VENTANAS_NO_ENUMERARLAS_FMT =
    '  ventanas: no pude enumerarlas (%s) [NODE-022]';

  SN_NODE_VENTANAS_SIN_CONVERTIR =
    '  ventanas: no pude leer el tamano de la captura; coordenadas de ' +
    'X11 sin convertir [NODE-023]';

  SN_NODE_NATIVAS_WAYLAND_NO_SALEN =
    '  (ventanas X11/Xwayland: las nativas Wayland no salen en la lista) ' +
    '[NODE-024]';

  SN_NODE_VENTANAS_FALLO_LISTA_CLASE_FMT =
    '  ventanas: fallo la lista (%s: %s) [NODE-025]';

  SN_NODE_CONTROL_ESCRITORIO_LINUX =
    'McpDesktop - nodo de control del escritorio Linux [NODE-026]';

  SN_NODE_LIBRERIAS_DEL_SISTEMA =
    '-- 1. librerias del sistema (nada que instalar) -- [NODE-027]';

  SN_NODE_NO_HAY_ESCRITORIO_FMT =
    'NO hay escritorio al que hablar: %s [NODE-028]';

  SN_NODE_PANTALLA_ESCALA_CAPTURA =
    '-- 2. la pantalla: escala y captura -- [NODE-029]';

  SN_NODE_ESCRITORIO_DICE_ESCALA_FMT =
    '  el escritorio dice que su escala es %s [NODE-030]';

  SN_NODE_NO_LEER_ESCALA_FMT =
    '  no pude leer la escala, asumo 1,00: %s [NODE-031]';

  SN_NODE_LAS_MANOS =
    '-- 3. las manos -- [NODE-032]';

  SN_NODE_NO_PREPARAR_CANAL_FMT =
    '  no pude preparar el canal: %s [NODE-033]';

  SN_NODE_NO_ABRIR_CANAL_FMT =
    '  no pude abrir el canal: %s [NODE-034]';

  SN_NODE_CANAL_NO_LISTO_FMT =
    '  el canal no llego a estar listo: %s [NODE-035]';

  SN_NODE_LISTAS_PANTALLA_LOGICA_FMT =
    '  listas. pantalla logica %dx%d, escala %s [NODE-036]';

  SK_NODE_SUPER_ENVIADO =
    '  SUPER enviado: vista de todas las ventanas [NODE-037]';

  SN_NODE_NO_ABRIR_VISTA_FMT =
    '  no pude abrir la vista: %s [NODE-038]';

  SK_NODE_ESCRITO_PIXEL_MAPA_FMT =
    '  ESCRITO "%s" en el pixel (%d,%d)  [%s] (tecleado; el foco NO se ' +
    'verifica: comprueba con la captura) [NODE-039]';

  SK_NODE_ESCRITO_TECLEADO_MAPA_FMT =
    '  ESCRITO: %s  [%s] (tecleado; el foco NO se verifica: comprueba ' +
    'con la captura) [NODE-040]';

  SN_NODE_USO_TECLA_EVDEV =
    '  uso: <x> <y>   pulsa en ese pixel de la captura' + sLineBreak +
    '       altab     cambia de ventana con el teclado' + sLineBreak +
    '       tecla <n> pulsa una tecla (evdev: Escape 1, Enter 28)' + sLineBreak +
    '       texto <t> escribe ese texto donde este el foco' + sLineBreak +
    '       escribe <x> <y> <t>  pulsa ahi Y escribe: un solo viaje' + sLineBreak +
    '       ventanas  ensena TODAS las ventanas (tecla Super),' + sLineBreak +
    '                 para cuando se tapan entre ellas' + sLineBreak +
    '  (para dar el foco a una ventana, pulsa en su barra de titulo) [NODE-041]';

  SN_NODE_NO_SE_USA_MANO =
    'McpDesktopNode - nodo de escritorio del Delphi IDE Remote MCP.' + sLineBreak +
    '  Este programa no se usa a mano: lo lanza el servidor MCP, que' + sLineBreak +
    '  es quien decide (por workspace) si un agente puede ver y tocar' + sLineBreak +
    '  este escritorio. Sin esa llamada no hace nada. [NODE-042]';

  SN_NODE_TODAVIA_NO_TIENE_MANOS =
    'McpDesktop - este sistema todavia no tiene manos en el nodo' + sLineBreak +
    '  (hoy: Linux con GNOME y Windows; macOS seria el siguiente) [NODE-043]';

  SR_JOB_FORK_VIGIA_FALLO =
    'error: fork del vigia fallo [JOB-001 INVALID_PARAM]';

  SR_JOB_FORK_PROGRAMA_FALLO =
    'error: fork del programa fallo [JOB-002 INVALID_PARAM]';

  SR_JOB_NO_PUDE_ENTRAR_FMT =
    'error: no pude entrar en %s: %s [JOB-003 INVALID_PARAM]';

  SR_JOB_NO_PUDE_ARRANCAR_FMT =
    'error: no pude arrancar %s: %s [JOB-004 INVALID_PARAM]';

  SR_JOB_KILL_NECESITA_ID =
    'RECHAZADO: @kill necesita el id de un trabajo de este servidor. ' +
    '[JOB-005 DENIED]';

  SN_JOB_NINGUN_TRABAJO_VIVO_FMT =
    'no hay ningun trabajo %s vivo en esta carpeta: o ya termino, o no ' +
    'era de este proyecto. [JOB-006]';

  SK_JOB_TERMINADO_EL_TRABAJO_FMT =
    'terminado el trabajo %s (pid %d por %s, %s). [JOB-007]';

  SN_JOB_NO_PUDE_MATAR_FMT =
    'no pude matar el trabajo %s (pid %d): %s - %s [JOB-008]';

  SR_JOB_NO_EXISTE_FMT =
    'error: no existe %s en la carpeta desplegada de este proyecto en el ' +
    'target. [JOB-009 NOT_FOUND]';

  SR_JOB_NO_EJECUTABLE_NATIVO_FMT =
    'RECHAZADO: %s no es un ejecutable nativo (ELF/PE): solo se ejecuta ' +
    'el binario que produjo delphi_build. [JOB-010 DENIED]';

  // Textos que estaban en linea en Mld.DBus.pas (el resto, 27-sep-2026)
  SF_NODE_FALTA_EN_FMT =
    'falta %s en %s (%s)';

  

  SF_NODE_BUS_NO_DEVOLVIO_CONEXION =
    'el bus no devolvio conexion (sin DBUS_SESSION_BUS_ADDRESS?)';

  SF_NODE_NO_HAY_CONEXION_BUS =
    'no hay conexion con el bus';

  SF_NODE_BUS_NO_RESPONDIO =
    'el bus no respondio';

  SF_NODE_RESPUESTA_SIN_ARGUMENTOS =
    'respuesta sin argumentos';

  SF_NODE_ESPERABA_ARRAY_CADENAS =
    'se esperaba un array de cadenas';

  SF_NODE_ESCRITORIO_NO_RESPONDIO =
    'el escritorio no respondio';

  SF_NODE_TERCER_ARGUMENTO_NO_ARRAY =
    'el tercer argumento no es el array de monitores logicos';

  SF_NODE_NO_ANADIR_ARGUMENTO =
    'no se pudo anadir un argumento';

  SF_NODE_CREATESESSION_SIN_RUTA_SESION =
    'CreateSession no devolvio ruta de sesion';

  SF_NODE_NO_ABRIR_DICCIONARIO =
    'no pude abrir el diccionario';

  SF_NODE_CREATESESSION_NO_DEVOLVIO_RUTA =
    'CreateSession no devolvio ruta';

  SF_NODE_NO_LEER_SESSIONID =
    'no pude leer SessionId';

  SF_NODE_SCREENCAST_NO_DEVOLVIO_RUTA =
    'ScreenCast.CreateSession no devolvio ruta';

  SF_NODE_CONNECTTOEIS_NO_DEVOLVIO_NADA =
    'ConnectToEIS no devolvio nada';

  SF_NODE_CONNECTTOEIS_DEVOLVIO_TIPO_FMT =
    'ConnectToEIS devolvio tipo %d, se esperaba un descriptor';

  SF_NODE_DESCRIPTOR_NO_VALIDO =
    'el descriptor recibido no es valido';

  SF_NODE_NO_SUSCRIBIRME_RESPUESTA_FMT =
    'no pude suscribirme a la respuesta: %s';

  SF_NODE_PORTAL_SIN_OBJETO_PETICION =
    'el portal no devolvio objeto de peticion';

  SF_NODE_PORTAL_RECHAZO_CAPTURA_FMT =
    'el portal rechazo la captura (codigo %d)';

  SF_NODE_RESPUESTA_SIN_RESULTADOS =
    'la respuesta no trae resultados';

  SF_NODE_RESPUESTA_SIN_DIRECCION =
    'la respuesta no trae la direccion del fichero';

  SF_NODE_NO_ENTIENDO_DIRECCION_FMT =
    'no entiendo la direccion %s';

  SF_NODE_PORTAL_QUEDO_CALLADO_FMT =
    'el portal se quedo callado %d ms: ni respuesta ni error. Lo normal ' +
    'es que no llegara a mostrar el dialogo del permiso de captura (pasa ' +
    'en sesion remota o con la pantalla bloqueada). Pide al operador que ' +
    'conceda UNA vez la captura de pantalla en esa maquina, con la ' +
    'pantalla delante; despues esto funciona en silencio';

  // Textos que estaban en linea en Mld.Eis.pas (el resto, 27-sep-2026)
  SF_NODE_DESCRIPTOR_INVALIDO =
    'descriptor invalido';

  

  SF_NODE_NO_DEVOLVIO_CONTEXTO =
    'ei_new_sender no devolvio contexto';

  SF_NODE_BACKEND_FD_DEVOLVIO_FMT =
    'ei_setup_backend_fd devolvio %d';

  SF_NODE_DISPOSITIVOS_NO_LISTOS_FMT =
    'los dispositivos no llegaron a estar listos en %d ms (puntero=%s ' +
    'teclado=%s)';

  SF_NODE_CANAL_NO_ESTA_LISTO =
    'el canal no esta listo';

  SF_NODE_CAE_FUERA_PANTALLA_FMT =
    '(%s,%s) de la captura cae fuera de la pantalla (escala %s, region ' +
    '%dx%d)';

  SF_NODE_TECLADO_TABLA_FIJA =
    'teclado: tabla fija (americano)';

  SF_NODE_LIBEI_NO_ENTREGA_MAPA =
    ' - esta libei no entrega el mapa';

  SF_NODE_ESCRITORIO_NO_ENTREGO_MAPA =
    ' - el escritorio no entrego su mapa';

  SF_NODE_NO_LEER_MAPA_ESCRITORIO =
    ' - no pude leer el mapa del escritorio';

  SF_NODE_TECLADO_DEL_ESCRITORIO_FMT =
    'teclado: el del escritorio (%s, %d caracteres)';

  SF_NODE_ESCRITORIO_NO_DIO_TECLADO =
    'el escritorio no dio teclado';

  SF_NODE_TECLADO_SIN_TECLA_FMT =
    'el teclado del escritorio (%s) no tiene una tecla que de el ' +
    'caracter "%s" (posicion %d), ni directa ni por tecla muerta (%d ' +
    'teclas muertas en el mapa)';

  SF_NODE_NO_SE_TECLEAR_FMT =
    'no se teclear el caracter "%s" (posicion %d)';

  // Textos que estaban en linea en Mld.DBus.pas (el resto, 27-sep-2026)
  SF_NODE_NO_CONSTRUIR_MENSAJE =
    'no se pudo construir el mensaje';

  SF_NODE_SIN_RESPUESTA =
    'sin respuesta';

  // Textos que estaban en linea en Mld.X11.pas (el resto, 27-sep-2026)
  SF_NODE_NO_PUDE_MIRAR_FMT =
    'no pude mirar %s: %s';

  SF_NODE_SIN_CONEXION_X11 =
    'no hay conexion con X11';

  SF_NODE_NO_LEER_ARBOL_X11 =
    'no pude leer el arbol de ventanas de X11';

  SF_NODE_VENTANA_YA_NO_EXISTE =
    'esa ventana ya no existe';

  SF_NODE_VENTANA_NO_VISIBLE =
    'la ventana no esta visible: no hay nada que capturar';

  SF_NODE_XGETIMAGE_SIN_IMAGEN =
    'XGetImage no devolvio imagen (ventana tapada o sin respaldo)';

  SF_NODE_XWAYLAND_SIN_AUTORIZACION =
    'Hay sesion Wayland pero no encuentro la autorizacion de Xwayland ' +
    '(.mutter-Xwaylandauth.*). Pidele al operador que abra alguna ' +
    'aplicacion en esa sesion, o comprueba que Xwayland este activo.';

  SF_NODE_SESION_SIN_CONECTAR =
    'Hay sesion grafica, pero no pude conectar con ella.';

  SF_NODE_PUNTERO_FUERA_PANTALLA =
    'el puntero no esta en esta pantalla';

  // Textos que estaban en linea en Mld.Win.pas (el resto, 27-sep-2026)
  SF_NODE_ESCRITORIO_ENTRADA_NO_ABRIR_FMT =
    'escritorio de entrada: no se pudo abrir (%s)';

  SF_NODE_ESCRITORIO_ENTRADA_FMT =
    'escritorio de entrada: %s';

  SF_NODE_ESCRITORIO_ENTRADA_SIN_NOMBRE =
    'escritorio de entrada: sin nombre';

  SF_NODE_SESION_REMOTA =
    '; sesion remota';

  SF_NODE_SESION_CONSOLA =
    '; sesion de consola';

  SF_NODE_FOCO_EN_FMT =
    '; foco en "%s"';

  SF_NODE_SIN_VENTANA_FOCO =
    '; sin ventana con foco';

  SF_NODE_NO_ABRIR_CONTEXTO_PANTALLA =
    'no pude abrir el contexto de la pantalla';

  SF_NODE_NO_CREAR_CONTEXTO_MEMORIA =
    'no pude crear el contexto en memoria';

  SF_NODE_NO_RESERVAR_IMAGEN =
    'no pude reservar la imagen';

  SF_NODE_CON_CAPTUREBLT_FMT =
    'con CAPTUREBLT: %s [%d]';

  SF_NODE_COPIA_PANTALLA_FALLO_FMT =
    'la copia de pantalla fallo (%s; sin el: %s [%d]; %s)';

  SF_NODE_PRINTWINDOW_PORQUE_FMT =
    'PrintWindow ventana a ventana, porque %s';

  SF_NODE_SISTEMA_ACEPTO_ENTRADAS_FMT =
    'el sistema acepto %d de %d entradas (%s)';

  SF_NODE_PIXEL_FUERA_CAPTURA_FMT =
    'el pixel (%d,%d) se sale de la captura (%dx%d)';

  // Textos que estaban en linea en Mld.Teclado.pas (el resto, 27-sep-2026)
  SF_NODE_ESCRITORIO_SIN_MAPA_TECLADO =
    'el escritorio no entrego mapa de teclado';

  SF_NODE_NO_ABRIR_LIBXKBCOMMON_FMT =
    'no pude abrir libxkbcommon.so.0 (%s)';

  SF_NODE_XKB_CONTEXT_NEW_NIL =
    'xkb_context_new devolvio nil';

  SF_NODE_XKB_NO_ENTENDIO_MAPA =
    'libxkbcommon no entendio el mapa del escritorio';

  SF_NODE_MAPA_SIN_CARACTERES =
    'el mapa del escritorio no trae ningun caracter';

  // Textos que estaban en linea en Mld.Captura.pas (el resto, 27-sep-2026)
  SF_NODE_NO_LEER_IMAGEN_VENTANA_FMT =
    'no pude leer la imagen de la ventana: %s';

  SF_NODE_VENTANA_SIN_PIXELES =
    'la ventana no devolvio pixeles';

  SF_NODE_FORMATO_PIXEL_NO_CONTEMPLADO_FMT =
    'formato de pixel no contemplado: %d bits';

  SF_NODE_NO_ESCRIBIR_PNG_FMT =
    'no pude escribir el PNG en %s';

  // Textos que estaban en linea en Mld.Sesion.pas (el resto, 27-sep-2026)
  SF_NODE_SIN_SESION_GRAFICA_FMT =
    'NO hay sesion grafica abierta del usuario %s en esta maquina. ' +
    'Pidele al operador que inicie sesion en el escritorio (o abra una ' +
    'sesion remota) con ese usuario y vuelve a intentarlo: sin ' +
    'escritorio no hay nada que ver ni que pulsar.';

  // Textos que estaban en linea en Mld.Dyn.pas (el resto, 27-sep-2026)
  SF_NODE_LIBRERIA_NO_ABIERTA =
    'la libreria no esta abierta';

  // Textos que estaban en linea en McpRunJob.dpr (el resto, 27-sep-2026)
  SF_JOB_SIGKILL_NO_ATENDIO =
    'SIGKILL (no atendio al SIGTERM en 3 s)';

  SF_JOB_PID_DE_OTRO_PROGRAMA =
    'ese pid ya es de otro programa, fuera de esta carpeta: no se toca';

  SF_JOB_NO_ABRIR_SALIDA_FMT =
    'no pude abrir la salida %s';

  SF_JOB_NOMBRE_DEL_VIGIA =
    'nombre del vigia';

  SR_JOB_EXCEPCION_FMT =
    'error: %s: %s [JOB-011 INVALID_PARAM]';

  // Textos que estaban en linea en Mld.X11.pas (el resto, 27-sep-2026)
  SF_NODE_NO_HAY_LIB_FMT =
    'no hay %s en esta maquina: %s';

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
