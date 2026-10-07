{ El formato de la salida de los renderizadores de forms, en UN sitio: lo
  ESCRIBEN DelphiFormRenderVcl/DelphiFormRenderFmx (FormRender.Comun.Responde)
  y lo LEE el servidor (Lsp.FormRender.LeeRespuestaDeRender). Se incluye dentro de una
  seccion const, como NodeProtocolo.inc. Una linea por clave, 'CLAVE=valor';
  las repetibles (IGNORED, WARNING) salen tantas veces como haga falta; el
  resto una vez. Lo que empieza por '#' es traza (--verbose) y no se lee. }
  FR_CAPTURE = 'CAPTURE=';       // CAPTURE=<ruta del png> (la misma clave que el nodo de escritorio)
  FR_SIZE = 'SIZE=';             // SIZE=<ancho>x<alto> del png
  FR_DPI = 'DPI=';               // DPI=96: el proceso no es consciente del DPI, un pixel = una unidad del dfm
  FR_ROOT = 'ROOT=';             // ROOT=<Nombre>:<Clase>:<form|frame>
  FR_FIDELITY = 'FIDELITY=';     // FIDELITY=window (pintada real, sesion interactiva) | print (WM_PRINT, sesion 0) | canvas (FMX)
  FR_SESSION = 'SESSION=';       // SESSION=<id de sesion de Windows> (0 = servicio)
  FR_PACKAGES = 'PACKAGES=';     // PACKAGES=<cargados>/<conocidos> de diseno del IDE (0/0 = no hicieron falta)
  FR_COMPONENTS = 'COMPONENTS='; // COMPONENTS=<n> leidos de la raiz
  FR_SUBSTITUTED = 'SUBSTITUTED='; // SUBSTITUTED=<TClase,TClase> que no existen en ningun paquete (sustituto rosa con el nombre)
  FR_IGNORED = 'IGNORED=';       // IGNORED=<propiedad o error del lector que se salto> (repetible)
  FR_NONVISUAL = 'NONVISUAL=';   // NONVISUAL=<n> iconos de no visuales dibujados (solo con --nonvisual on)
  FR_NONVISUALS = 'NONVISUALS='; // NONVISUALS=<Nombre:Clase,...> los no visuales de la raiz, se dibujen o no: el
                                 // agente necesita saber que existen aunque no los vea (David, 7-oct-2026)
  FR_RECT = 'RECT=';             // RECT=<Nombre>=<izq>,<arriba>,<ancho>,<alto> del componente pedido, en pixeles del png
  FR_STYLE = 'STYLE=';           // STYLE=<que estilo se aplico y de donde>
  FR_WARNING = 'WARNING=';       // WARNING=<aviso> (repetible)
  FR_MS = 'MS=';                 // MS=<carga>,<pintado> en milisegundos
  FR_ERROR = 'ERROR=';           // ERROR=<motivo>; va con codigo de salida 1 (3 si fue el tiempo limite)
  FR_RC_OK = 0;
  FR_RC_ERROR = 1;
  FR_RC_USAGE = 2;
  FR_RC_TIMEOUT = 3;
