{ El formato de la salida del nodo de escritorio, en UN sitio: lo ESCRIBE el
  nodo (src\DesktopNode) y lo LEE el servidor (Lsp.RemoteRun,
  Mcp.Tools.Desktop). Se incluye dentro de una seccion const, como
  NodeKey.inc. Estaba compuesto a mano en cinco sitios (revision del
  26-sep-2026). }
  NODO_CAPTURA = 'CAPTURE=';           // CAPTURE=<ruta del png>
  NODO_NO_PUDE = 'Could not capture:'; // Could not capture: <motivo>
  { ...y detras, si fue Windows quien dijo que no, SU codigo: el servidor
    juzga por el (ERROR_ACCESS_DENIED = sesion bloqueada o sin escritorio),
    no por la frase, que sale en el idioma del destino (V85 de la 1.23.1) }
  NODO_CODIGO_WIN = 'WINERR=';         // '  WINERR=<codigo de Windows>'
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
  { Las ORDENES que el servidor le da al nodo: una palabra y lo suyo detras
    (sin palabra, 'x y' es un clic). Las compone Mcp.Tools.Desktop y las leen
    los dos escritorios del nodo, el de Windows y el de Linux: estaban a mano
    en los tres (forma 17 de la 1.26). }
  NODO_ORDEN_VENTANAS = 'ventanas';    // ensenar las ventanas
  NODO_ORDEN_ESCRIBE = 'escribe';      // escribe x y <texto>: pulsa y teclea
  NODO_ORDEN_TEXTO = 'texto';          // texto <texto>: teclea donde este el foco
  NODO_ORDEN_TECLA = 'tecla';          // tecla [modificadores] <tecla>
  NODO_ORDEN_ALTAB = 'altab';          // Alt+Tab (desde la consola del nodo)
  NODO_ORDEN_ARRASTRA = 'arrastra';    // arrastra x1 y1 x2 y2: pulsa, se mueve y suelta
  { Las teclas por su codigo evdev (linux/input-event-codes.h: una POSICION del
    teclado, la misma en toda distribucion) que nombran los dos lados en Linux:
    los modificadores que manda la tool en "tecla" y las que el nodo pulsa por
    su cuenta (el nivel de un caracter, el salto de type, Alt+Tab, la vista de
    ventanas). Estaban escritas en el servidor y en el nodo (J19 del revisor
    del paisaje de la 1.28). }
  EVDEV_TAB = 15;                      // KEY_TAB
  EVDEV_INTRO = 28;                    // KEY_ENTER: un salto de linea de type
  EVDEV_CTRL = 29;                     // KEY_LEFTCTRL
  EVDEV_MAYUS = 42;                    // KEY_LEFTSHIFT: el nivel 1 de un caracter
  EVDEV_ALT = 56;                      // KEY_LEFTALT
  EVDEV_ALTGR = 100;                   // KEY_RIGHTALT: el nivel 2 (@, #, ~...)
  EVDEV_SUPER = 125;                   // KEY_LEFTMETA
  { Y la salida de un TRABAJO del lanzador (src\RunJob): la escribe
    McpRunJob y la lee Lsp.RemoteRun. Estaban a mano en diecinueve sitios
    del lanzador y dos del servidor (28-sep-2026). }
  JOB_ENV = '___ENV=';                 // la primera: ___ENV=<1|0>|<lo anadido>
  { ...y en Windows, lo anadido es la SESION en la que corre el lanzador:
    win:<n>, y la 0 es la de los servicios, sin escritorio. La leia
    Lsp.RemoteRun con un Substring(4) a mano (forma 17 de la 1.26). }
  JOB_ENV_WIN = 'win:';
  JOB_RC = '___RC=';                   // la ultima: ___RC=<codigo de salida>
