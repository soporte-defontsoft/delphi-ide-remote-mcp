{ El formato de la salida del conversor de estilos, en UN sitio: lo ESCRIBE
  DelphiStyleConvert y lo LEE el servidor (Lsp.Styles.CorreStyleConvert). Se
  incluye dentro de una seccion const, como FormRenderProtocolo.inc. Eran
  literales a mano en los dos lados, sin version (forma 6 del revisor del
  paisaje de la 1.26). }
  SC_PROTOCOL = 'PROTOCOL=';     // PROTOCOL=<SC_PROTOCOLO_VERSION>, lo primero que escribe: un conversor y un
                                 // servidor de versiones distintas no se entienden, y sin decirlo se leerian mal
  // Se sube al cambiar una clave de aqui o una orden del conversor (test_paisaje lo vigila)
  SC_PROTOCOLO_VERSION = 1;
  SC_IGNORED = 'IGNORED'#9;      // IGNORED<tab><mensaje del RTL, con clase y propiedad> (repetible, check)
  SC_ERROR = 'ERROR: ';          // ERROR: <clase>: <mensaje> de la excepcion que paro la orden, con SC_RC_ERROR
  SC_OK = 'OK';                  // la ultima linea de una orden que acabo bien
  // las ordenes; las rutas, relativas a la carpeta en la que corre (la etapa de la llamada)
  SC_TOBIN = 'tobin';            // tobin <entrada> <salida>: el texto a binario
  SC_TOTEXT = 'totext';          // totext <entrada> <salida>: a texto, como lo escribe FMX
  SC_DEFAULTS = 'defaults';      // defaults <salida>: el estilo de la plataforma (win10style) en texto
  SC_CHECK = 'check';            // check <entrada>: lo que FMX ignora al cargarla (SC_IGNORED)
  SC_RC_OK = 0;
  SC_RC_ERROR = 1;               // la orden lanzo: SC_ERROR dice que
  SC_RC_USO = 2;                 // una orden que no existe o sin sus argumentos
