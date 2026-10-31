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
  FR_IGNORED = 'IGNORED=';       // IGNORED=<de quien>|<error que se salto, EN PARTES> (repetible; FR_PARTES_SEP): <de quien> =
                                 // FR_ORIGEN_LECTOR si la excepcion era del lector (EFilerError, EParserError: el
                                 // fichero), o la clase de la excepcion si la lanzo el codigo de un componente al
                                 // crearlo o nombrarlo (IBX sin gds32.dll, un AV de un bpl: no es del fichero, que se
                                 // sepa; corpus 18-oct-2026). La de un SETTER llega envuelta en EReadError: del lector
  FR_ORIGEN_LECTOR = 'reader';   // el <de quien> de un IGNORED= del propio lector
  FR_NONVISUAL = 'NONVISUAL=';   // NONVISUAL=<n> iconos de no visuales dibujados (solo con --nonvisual on)
  FR_NONVISUALS = 'NONVISUALS='; // NONVISUALS=<Nombre:Clase,...> los no visuales de la raiz, se dibujen o no: el
                                 // agente necesita saber que existen aunque no los vea (David, 7-oct-2026)
  FR_RECT = 'RECT=';             // RECT=<Nombre>=<izq>,<arriba>,<ancho>,<alto> del componente pedido, en pixeles del png
  FR_STYLE = 'STYLE=';           // STYLE=<que estilo se aplico y de donde>
  FR_WARNING = 'WARNING=';       // WARNING=<aviso> (repetible)
  FR_PARTIAL = 'PARTIAL=';       // PARTIAL=<ancestro o fichero> sin el que se leyo el form (repetible): el
                                 // juez del orden no juzga un form a medias (revisor 6 del 3.11, A2)
  FR_READ = 'READ=';             // READ=<sha256>|<ruta> de un fichero que leyo para cargar el form - un
                                 // ancestro, un frame, el .pas de la cadena - (repetible): el servidor lo
                                 // vuelve a mirar antes de escribir lo juzgado (B5 rev6, 1.18.2)
  FR_WRITTEN = 'WRITTEN=';       // WRITTEN=<una linea del form como lo guarda el IDE> (repetible, con sus
                                 // blancos; --writeback on: el juez del orden, 3.11 de la 1.18.0)
  FR_ORDER = 'ORDER=';           // ORDER=<Nombre>=<prop>,<prop>,... con --writeback y --component: las
                                 // propiedades publicadas de SU clase en el orden en que las escribe TWriter
                                 // (GetPropInfos). El servidor coloca ahi lo que el escritor no puede dar:
                                 // lo de UNAPPLIED= y lo que su lector salto (1.22.1)
  FR_UNSTORED = 'UNSTORED=';     // UNSTORED=<Nombre>=<prop>,<prop>,... con --writeback y --component: las
                                 // publicadas que SU clase declara stored False (la constante, como la lee
                                 // TypInfo): TWriter no las escribe nunca por su nombre, y lo que el form
                                 // guarda de ellas va en otras (en FMX, Width y Height van en Size). El
                                 // servidor no las da por "el valor de la clase" (1.22.1)
  FR_UNAPPLIED = 'UNAPPLIED=';   // UNAPPLIED=<valor> (repetible): lo que el lector leyo y NO pudo aplicar, el
                                 // nombre del metodo de un evento (no hay codigo) o una referencia a un
                                 // componente que no resolvio en el form (la de otro modulo). El escritor no
                                 // lo escribe, y el servidor conserva esa linea (1.22.1)
  FR_BOX = 'BOX=';               // BOX=<ruta>|<clase>|<ruta del padre>|<x>,<y>,<ancho>,<alto>|<visible 0|1>|<contenido> (repetible;
                                 // --boxes): cada control, donde queda de verdad, en coordenadas del form (V74, V24);
                                 // <contenido>, x,y,ancho,alto de donde esta si no es su padre (un TTabItem), o vacio
  FR_UNREADABLE_CLASS = 'UNREADABLECLASS='; // UNREADABLECLASS=<clsid> (repetible; --unreadableclasses): una clase
                                 // COM cuya clave InprocServer32 no se deja leer desde el contenedor
  FR_MS = 'MS=';                 // MS=<carga>,<pintado> en milisegundos
  FR_ERROR = 'ERROR=';           // ERROR=<motivo>; va con codigo de salida 1 (3 si fue el tiempo limite)
  FR_NOT_LOADED = 'NOTLOADED=';  // NOTLOADED=<clase de la excepcion>|<su mensaje EN PARTES>, antes del ERROR=:
                                 // lo que fallo fue el LECTOR mientras cargaba el form (EFilerError o
                                 // EParserError, lo dice la jerarquia de la RTL): es el contenido del
                                 // fichero, no el ayudante ni un paquete al pintar (DSGN-061 de la 1.20).
                                 // Con --convert, lo que el conversor no convirtio: el contenido (V71)
  FR_LINE = 'LINE=';             // LINE=<n> con --convert, antes del NOTLOADED=: la linea que nombra el error
                                 // del parser, leida con SParseError de ESTE proceso (en su idioma, como
                                 // LecturaEnPartes); 0 si no nombra ninguna
  // un mensaje del lector EN PARTES: <Componente>|<Propiedad>|<Motivo>|<texto tal cual>, partido por el
  // ayudante con EL formato que lo compuso (SPropertyException, en el idioma de ese proceso: el RTL lo
  // traduce por el de Windows, medido el 18-oct-2026); '|||<texto>' si no tiene esa forma. Lo compone
  // FormRender.Comun.LecturaEnPartes y lo lee Lsp.FormRender.PartesDeLectura
  FR_PARTES_SEP = '|';
  FR_RC_OK = 0;
  FR_RC_ERROR = 1;
  FR_RC_USAGE = 2;
  FR_RC_TIMEOUT = 3;
