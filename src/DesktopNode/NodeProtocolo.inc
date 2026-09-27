{ El formato de la salida del nodo de escritorio, en UN sitio: lo ESCRIBE el
  nodo (src\DesktopNode) y lo LEE el servidor (Lsp.RemoteRun,
  Mcp.Tools.Desktop). Se incluye dentro de una seccion const, como
  NodeKey.inc. Estaba compuesto a mano en cinco sitios (revision del
  26-sep-2026). }
  NODO_CAPTURA = 'CAPTURA=';           // CAPTURA=<ruta del png>
  NODO_NO_PUDE = 'NO pude capturar:';  // NO pude capturar: <motivo>
  NODO_VENTANAS = 'ventanas visibles:'; // '  <n> ventanas visibles:' abre la lista
  NODO_VENTANA = 'VENTANA ';            // '  VENTANA x y ancho alto <titulo>'
