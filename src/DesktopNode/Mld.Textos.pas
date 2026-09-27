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
