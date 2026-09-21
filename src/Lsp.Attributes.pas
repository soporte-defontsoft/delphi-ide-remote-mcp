unit Lsp.Attributes;

{ EL DATO QUE FALTABA: que parametro de una tool es una ruta DE ESTE SERVIDOR.

  Los 200 parametros de las 38 tools los decidimos nosotros uno a uno, y nunca
  dejamos escrito lo mas basico de cada ruta: de quien es. En el esquema son
  todos un `string` igual, y la unica forma de distinguirlos era leerse la
  descripcion en prosa. Eso no lo puede hacer el servidor... y tampoco el
  agente, que ve `path` y `exe` sin nada que diga que una esta sujeta a la
  jaula y la otra no.

  Consecuencia medida el 2026-09-21: la decision de comprobar la jaula se
  tomaba a mano en ~60 sitios, de memoria y por quien escribiera la tool. De
  los cinco parametros de "destino que elige quien llama", tres comprobaban y
  dos no - y con el nodo de escritorio real, eso dejo que una llamada
  escribiera una captura del escritorio del operador FUERA de la jaula. No se
  le escapo a nadie: es que no habia donde declararlo.

  POR QUE UN SOLO MARCADOR Y NO UN ENUM. Lo midio David sobre el contrato
  vivo: de los 41 parametros que son rutas, 39 son NUESTRAS y solo DOS son de
  la maquina destino (delphi_paserver.exe y delphi_config.remotedir). El
  primer censo salio 37+2: delphi_config.path se quedo sin marca y sin
  comentario, y delphi_adb_linux.project llevaba una excepcion FALSA ("es
  un nombre") que su propia llamada a PathDenied desmiente. Los encontro
  la auditoria del 21-sep - exactamente la mina que la puerta central
  habria heredado. Con esa
  proporcion no hacen falta categorias: se marca lo nuestro, y lo que no lleva
  marca -las dos remotas, los nombres, el contenido- la puerta ni lo mira.

  Y POR QUE SE MARCA LO QUE SI ES (inclusion) Y NO LO QUE NO (exclusion): el
  21-sep se intento al reves, reconociendo las rutas por una lista de los
  parametros que llevan contenido. Tumbo un delphi_search con
  query="D:\Proyectos" - una consulta de busqueda que PARECE una ruta. Una
  lista de exclusion vale para REESCRIBIR, donde equivocarse es inocuo; para
  RECHAZAR hay que fallar abierto con lo que no conoces, y eso obliga a marcar
  lo que si.

  Que no se olvide de ponerla en un parametro nuevo lo vigila la bateria
  test_round45: si aparece un parametro cuya descripcion habla de una ruta y
  nadie lo ha clasificado, se pone en rojo. Vigila el contrato VIVO, asi
  que solo ve las tools que su settings.ini registra: por eso su workspace
  declara tambien un vault - sin el, las cinco vault_* (el unico registro
  condicional del repo) eran invisibles y sus 'path' quedaron sin
  clasificar hasta la auditoria del 21-sep. }

interface

type
  { Marca una propiedad de un *Params como una ruta del sistema de ficheros DE
    ESTE SERVIDOR, sujeta por tanto a la jaula del workspace.

    NO se marca: una ruta de la maquina destino (el target de PAServer), un
    NOMBRE que solo parece ruta, una mascara de ficheros, ni nada que lleve
    contenido. }
  RutaDelServidorAttribute = class(TCustomAttribute)
  end;

  { Azucar para escribirlo como los demas: [RutaDelServidor] }
  RutaDelServidor = RutaDelServidorAttribute;

implementation

end.
