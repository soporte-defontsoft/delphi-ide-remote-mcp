{ El formato de la salida del nodo de escritorio, en UN sitio: lo ESCRIBE el
  nodo (src\DesktopNode) y lo LEE el servidor (Lsp.RemoteRun,
  Mcp.Tools.Desktop). Se incluye dentro de una seccion const, como
  NodeKey.inc. Estaba compuesto a mano en cinco sitios (revision del
  26-sep-2026). }
  NODO_CAPTURA = 'CAPTURE=';           // CAPTURE=<ruta del png>
  NODO_NO_PUDE = 'Could not capture:'; // Could not capture: <motivo>
  NODO_VENTANAS = 'visible windows:';  // '  <n> visible windows:' abre la lista
  NODO_VENTANA = 'WINDOW ';             // '  WINDOW x y ancho alto <titulo>'
