{ El formato de la salida del nodo de escritorio, en UN sitio: lo ESCRIBE el
  nodo (src\DesktopNode) y lo LEE el servidor (Lsp.RemoteRun,
  Mcp.Tools.Desktop). Se incluye dentro de una seccion const, como
  NodeKey.inc. Estaba compuesto a mano en cinco sitios (revision del
  26-sep-2026). }
  NODO_CAPTURA = 'CAPTURE=';           // CAPTURE=<ruta del png>
  NODO_NO_PUDE = 'Could not capture:'; // Could not capture: <motivo>
  NODO_VENTANAS = 'visible windows:';  // '  <n> visible windows:' abre la lista
  NODO_VENTANA = 'WINDOW ';             // '  WINDOW x y ancho alto <titulo>'
  { Y la salida de un TRABAJO del lanzador (src\RunJob): la escribe
    McpRunJob y la lee Lsp.RemoteRun. Estaban a mano en diecinueve sitios
    del lanzador y dos del servidor (28-sep-2026). }
  JOB_ENV = '___ENV=';                 // la primera: ___ENV=<1|0>|<lo anadido>
  JOB_RC = '___RC=';                   // la ultima: ___RC=<codigo de salida>
