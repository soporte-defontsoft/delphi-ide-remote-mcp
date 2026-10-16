{ El formato de la salida del nodo de escritorio, en UN sitio: lo ESCRIBE el
  nodo (src\DesktopNode) y lo LEE el servidor (Lsp.RemoteRun,
  Mcp.Tools.Desktop). Se incluye dentro de una seccion const, como
  NodeKey.inc. Estaba compuesto a mano en cinco sitios (revision del
  26-sep-2026). }
  NODO_CAPTURA = 'CAPTURE=';           // CAPTURE=<ruta del png>
  NODO_NO_PUDE = 'Could not capture:'; // Could not capture: <motivo>
  NODO_VENTANAS = 'visible windows:';  // '  <n> visible windows:' abre la lista
  NODO_VENTANA = 'WINDOW ';             // '  WINDOW x y ancho alto <titulo>'
  { Lo que el nodo dice en CADA arranque, por su id del catalogo (Mld.Textos,
    todos SN_): cabecera, librerias, escala, "listo". El servidor lo quita de
    la respuesta de un gesto que salio bien (Lsp.RemoteRun.SalidaParaElAgente,
    1.20: ~1.300 caracteres repetidos en cada tap, medido en Hermes). Un
    mensaje nuevo que se diga en cada arranque se anade AQUI; el que no este,
    se ensena (falla contando de mas, nunca de menos). test_catalogo lo vigila. }
  NODO_RUTINA = 'NODE-002 NODE-003 NODE-004 NODE-017 NODE-020 NODE-024 ' +
    'NODE-026 NODE-027 NODE-029 NODE-030 NODE-032 NODE-036';
  { El uso de consola del nodo (y sus lineas de continuacion): nunca al
    agente. Un agente lo tomo por comandos de la tool (command=tecla, escribe;
    Hermes, 16-oct-2026). }
  NODO_USO = 'NODE-016 NODE-041';
  { Y la salida de un TRABAJO del lanzador (src\RunJob): la escribe
    McpRunJob y la lee Lsp.RemoteRun. Estaban a mano en diecinueve sitios
    del lanzador y dos del servidor (28-sep-2026). }
  JOB_ENV = '___ENV=';                 // la primera: ___ENV=<1|0>|<lo anadido>
  JOB_RC = '___RC=';                   // la ultima: ___RC=<codigo de salida>
