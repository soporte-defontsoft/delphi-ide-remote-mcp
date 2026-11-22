{ El formato de la salida del conversor de estilos, en UN sitio: lo ESCRIBE
  DelphiStyleConvert y lo LEE el servidor (Lsp.Styles.CorreStyleConvert). Se
  incluye dentro de una seccion const, como FormRenderProtocolo.inc. Eran
  literales a mano en los dos lados, sin version (forma 6 del revisor del
  paisaje de la 1.26). }
  SC_PROTOCOL = 'PROTOCOL=';     // PROTOCOL=<SC_PROTOCOLO_VERSION>, lo primero que escribe: un conversor y un
                                 // servidor de versiones distintas no se entienden, y sin decirlo se leerian mal
  // Se sube al cambiar una clave de aqui o una orden del conversor (test_paisaje lo vigila)
  // la 2: SC_IGNORED en partes y SC_CLASE_SEP (DH6 de la 1.29)
  // la 3: SC_SHADOWED en check (D9 de la 1.29.3)
  // la 4: SC_CAMPOS_SEP, y SC_SHADOWED solo si gana uno interno o un rol: un
  // duplicado de primer nivel ya es duplicatedStyleNames (revisor del paisaje de la 1.29.3)
  SC_PROTOCOLO_VERSION = 4;
  SC_CAMPOS_SEP = #9;            // entre los campos de SC_IGNORED y SC_SHADOWED (estaba a mano en los dos lados)
  SC_IGNORED = 'IGNORED' + SC_CAMPOS_SEP; // IGNORED<tab><mensaje del RTL EN PARTES: LecturaEnPartes (FormRender.Partes), su lector
                                 // PartesDeLectura (Lsp.FormRender)> (repetible, check)
  SC_SHADOWED = 'SHADOWED' + SC_CAMPOS_SEP; // SHADOWED<tab><StyleName de primer nivel><tab><clase del que gana><tab><su ruta por
                                 // StyleName, padre.nombre>: el objeto que FMX DEVUELVE por ese nombre
                                 // (FindStyleResource, su TStyleIndexer) no es el estilo: lo pisa uno interno o un
                                 // rol, y el control sale vacio sin error (repetible, check; D9 de la 1.29.3). Otro
                                 // de PRIMER nivel con el mismo nombre no sale aqui: es un duplicado
  SC_ERROR = 'ERROR: ';          // ERROR: <clase>: <mensaje> de la excepcion que paro la orden, con SC_RC_ERROR
  SC_CLASE_SEP = ': ';           // entre la <clase> y el <mensaje> de SC_ERROR (lo leia a mano Mcp.Tools.Styles, DH6 de la 1.29)
  SC_OK = 'OK';                  // la ultima linea de una orden que acabo bien
  // las ordenes; las rutas, relativas a la carpeta en la que corre (la etapa de la llamada)
  SC_TOBIN = 'tobin';            // tobin <entrada> <salida>: el texto a binario
  SC_TOTEXT = 'totext';          // totext <entrada> <salida>: a texto, como lo escribe FMX
  SC_DEFAULTS = 'defaults';      // defaults <salida>: el estilo de la plataforma (win10style) en texto
  SC_CHECK = 'check';            // check <entrada>: lo que FMX ignora al cargarla (SC_IGNORED) y los estilos que
                                 // su indice no devuelve (SC_SHADOWED)
  SC_RC_OK = 0;
  SC_RC_ERROR = 1;               // la orden lanzo: SC_ERROR dice que
  SC_RC_USO = 2;                 // una orden que no existe o sin sus argumentos
