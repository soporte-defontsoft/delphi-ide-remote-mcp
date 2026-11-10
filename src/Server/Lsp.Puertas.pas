unit Lsp.Puertas;

{ LAS PUERTAS de leer y escribir texto (decisions/puertas-diseno-2026-10-09):
  los lugares (TLugarDeTexto) y sus preguntas, lo que se lee y se escribe por
  ellas, el cerrojo de escritura, la regla de ida y vuelta y la codificacion
  en que se escribe (con el origen de la llamada), la escritura atomica y la
  colocacion de un producto, y la carga y el guardado de un fichero que se
  edita (PatchLoadText / PatchSaveText). Vivia en Lsp.Patch (V94 de la
  depuracion de la 1.23, B6 de la 1.28): se mudo sin cambiar una linea. }

interface

uses
  System.Classes, // TStream: lo que AbreParaLeer entrega
  System.JSON,    // PonElVolcado: lo que se dice de un volcado escrito
  Lsp.Codificacion;

type
  { DONDE esta un fichero que pasa por las PUERTAS de leer y escribir texto, y
    por tanto que se comprueba (David, 9-oct-2026: "todo por la misma puerta
    con las comprobaciones que convengan"; decisions/puertas-diseno-2026-10-09):
      ltJaula     las raices del workspace (ReadPathDenied: tambien la zona de
                  biblioteca, para leer)
      ltIde       los lugares del IDE: su instalacion, su carpeta de datos del
                  usuario, la de sus SDK y el sysroot de cada SDK registrado,
                  en su SDK Manager (Lsp.Lugares.LugaresDelIde) o en un .sdk
                  de su carpeta de perfiles (lo que leen msbuild y paclient)
      ltCasa      las carpetas propias del servidor: caches, buzon e informes
                  (Lsp.Casa.CarpetasDeLaCasa; settings.ini NO)
      ltTemporal  el temporal propio del servidor (ServerTempDir)
      ltVault     el vault (VaultPath)
      ltBiblioteca  la zona de biblioteca del IDE (Lsp.Lugares.LibraryRoots: su
                  instalacion, sus catalogos de GetIt y su Library Search
                  Path), este o no encendida para los agentes - eso es la
                  jaula -. SOLO para leer: lo que el motor dice de un simbolo
                  de alli se ensena (P2). No es ltIde porque cargarla lee
                  rsvars.bat por la puerta con el IDE como lugar
      ltEntregables  la casa donde el servidor deja las capturas que hace para
                  devolverlas (Lsp.Capturas.EnCasaDeEntregables: su temporal, la
                  carpeta del workspace de quien llama), sin enlaces en el
                  camino. La juzga su nombrador y no la jaula: es trabajo
                  nuestro, no algo que el agente intente (1.18.2, 2b y 2af) }
  TLugarDeTexto = (ltJaula, ltIde, ltCasa, ltTemporal, ltVault, ltBiblioteca, ltEntregables);
  TLugaresDeTexto = set of TLugarDeTexto;

const
  { Lo que el MOTOR (DelphiLSP) puede ver y lo que se puede ensenar de lo que
    dice: lo que esta sesion puede leer, los lugares del IDE y su biblioteca
    (David, 9-oct-2026: "recortar y negar"). UNA definicion: la usan el juez
    de lo que se recorta de sus ajustes y de lo que sus tools niegan
    (Lsp.ConfigFabricator.MotorPuedeEnsenar) y lo que se le da a leer
    (Lsp.Client.LoadSourceText). }
  LUGARES_DEL_MOTOR: TLugaresDeTexto = [ltJaula, ltIde, ltBiblioteca];
  { Lo que el BUILD (msbuild y lo que lanza) puede leer de lo que nombra un
    proyecto: lo que esta sesion puede leer y la biblioteca del IDE, este o no
    encendida para los agentes (un proyecto compila contra ella). NO los
    lugares del IDE: su carpeta de datos del usuario guarda los .profile (la
    contrasena del PAServer) y dcc cita en sus errores lo que lee (A9 de la
    1.27, medido con un search path a $(APPDATA)\Embarcadero\BDS y un $I con
    nombre suelto).
    UNA definicion para lo que el build lee porque lo DICE el proyecto: sus
    valores, sus directivas, el in de un .dpr, los enlaces de su arbol y lo
    que nombra el .rc de un RcCompile (Lsp.Styles.RcLecturasDenegadas). Lo
    que el AGENTE nombra en una llamada (add-searchpath, add-deployfile) lo
    juzga la jaula, tambien en el suelo (Lsp.PuertaDeLaLlamada.ArgPathOutsideDenied): con
    la zona de biblioteca apagada, una carpeta de la biblioteca no la nombra
    el agente, aunque un proyecto que la lista compile. }
  LUGARES_DEL_BUILD: TLugaresDeTexto = [ltJaula, ltBiblioteca];
  { Donde se lee una CAPTURA: el out= que eligio el agente (la jaula) o la
    casa de los entregables, donde la deja el servidor sin out=. UNA lista
    para toda tool que capture (delphi_designer, delphi_desktop, delphi_adb)
    y para su entrega (Lsp.InlineImages.DeliverCapture). }
  LUGARES_DE_UNA_CAPTURA: TLugaresDeTexto = [ltJaula, ltEntregables];

{ LA PUERTA DE LEER, su pregunta: '' si APath esta en alguno de ALugares,
  por su ruta REAL (un enlace no saca a nadie de su sitio); si no, la
  negativa: la de la jaula cuando ltJaula esta entre ellos, y si no GUARD-034.
  Las lecturas que iban por su cuenta (TFile.ReadAllText: 41 en el inventario
  del 9-oct) no preguntaban nada: el escaner de peligros leia cualquier Import
  que nombrase un .dproj. }
function LugarDeLecturaDenegado(const APath: string; ALugares: TLugaresDeTexto): string;
{ ...y la lectura: los bytes de APath por EL detector (DetectEnc, el de
  delphi_read: BOM, UTF-8 estricto, la ANSI de la maquina; un form sin BOM,
  ANSI) si la puerta lo admite; si no, lanza su negativa (con su etiqueta: un
  llamador que la deje subir contesta DENIED). AEncName: la codificacion
  leida, para quien vaya a reescribirlo por PatchSaveText. }
function LeeTexto(const APath: string; ALugares: TLugaresDeTexto): string; overload;
function LeeTexto(const APath: string; ALugares: TLugaresDeTexto; out AEncName: string): string; overload;
{ EL decodificador de la puerta sobre unos BYTES ya leidos (DetectEnc +
  DecodeBytes, lo que hace la lectura con los del disco): quien compara unos
  bytes y parsea su texto lo saca de los MISMOS (el juez del orden del
  disenador, revisor 6 del 3.11, B1). }
function TextoDeBytes(const B: TArray<Byte>; AEsDesigner: Boolean; out AEncName: string): string;
{ ...y los BYTES, para quien los necesita enteros antes de decidir si son
  texto (lo que deja un test en su contenedor) o no lee texto (la version de
  la glibc de un sysroot): la misma pregunta y la misma negativa. }
function LeeBytes(const APath: string; ALugares: TLugaresDeTexto): TArray<Byte>;
{ ...y un TROZO de ellos, para lo que puede ser de gigas y solo se ensena en
  parte (la salida de un programa, V80 de la 1.23.1: remote-run la leia
  entera): hasta AMax bytes desde ADesde, los que haya; ATamano, el tamano
  del fichero entero. La misma pregunta y la misma negativa. }
function LeeTrozoDeBytes(const APath: string; ALugares: TLugaresDeTexto;
  ADesde: Int64; AMax: Integer; out ATamano: Int64): TArray<Byte>;
{ ...y el fichero ABIERTO para leerlo a trozos, para quien lo sirve sin tenerlo
  entero en memoria (/files, P8 de la 1.29: abria su TFileStream a pelo tras su
  ReadPathDenied) y para LeeTrozoDeBytes: la misma pregunta y la misma negativa,
  y abierto como TFile.ReadAllBytes (quien escribe no puede, quien lee si). Lo
  libera quien lo pide. }
function AbreParaLeer(const APath: string; ALugares: TLugaresDeTexto): TStream;
{ ...y las LINEAS de un tramo (ACuantos bytes desde ADesde; ACuantos < 0, hasta
  el final), como las cuenta delphi_read, leidas a trozos por esa puerta: lo
  que puede ser de gigas no se sube entero (el out= de remote-run lo leia
  entero y en UTF-16: R1 del revisor del paisaje del 10-nov-2026). La
  codificacion, por EL lector de un BOM; su BOM no es texto. }
function LineasDeUnTramo(const APath: string; ALugares: TLugaresDeTexto;
  ADesde, ACuantos: Int64): Int64;

{ LA PUERTA DE ESCRIBIR, su pregunta: '' si APath se puede escribir en el
  lugar ALugar; si no, su negativa. La jaula, lo que pregunta su escritor
  (AtomicWrite: la puerta sobre la ruta real, el modo de solo lectura y el
  +R); el vault y el IDE, dentro por la ruta real de la CARPETA (alli nacen
  el temporal y el renombre) y sin que APath sea el mismo un enlace; la casa
  y el temporal del servidor, dentro sin enlaces en el camino; las casas de
  los entregables, las de su nombrador y sin enlaces tampoco; solo rutas
  absolutas. Del IDE, su carpeta de datos del
  usuario, la de sus SDK y los sysroots que registra su SDK Manager - nunca
  su instalacion (David, 9-oct-2026), ni lo que solo nombra un .sdk -. Fuera
  de la jaula, tambien el +R de lo que ya esta.
  Y siempre la medida del escritor atomico. }
function LugarDeEscrituraDenegado(const APath: string; ALugar: TLugarDeTexto): string;
{ ...y la escritura: ABytes en APath ENTERO o nada (un temporal junto a el y
  el renombrado) si la puerta lo admite; si no, lanza su negativa. En la
  jaula es AtomicWrite. En el IDE, lo que se pisa se copia ANTES en la casa
  del servidor (Lsp.Casa.CopiaDelIde) y sin copia no se pisa: devuelve la
  ruta de esa copia, '' si no habia nada que pisar. Crear la carpeta es de
  quien llama. Lo que escribia cada uno por su cuenta (el vault, la casa,
  los temporales, el IDE: inventario del 9-oct) pasa por aqui. }
function EscribeBytes(const APath: string; const ABytes: TArray<Byte>;
  ALugar: TLugarDeTexto): string;
{ ...y un TEXTO que compone el servidor - no el de un fichero que se edita
  conservando su codificacion: ese es PatchSaveText -, en AK por EL
  codificador (EncodeText, con su ida y vuelta). AEstricto = False para una
  COPIA que solo se le pregunta a alguien (la propuesta que juzga el
  ayudante del disenador, como ParserDeForm): un sustituto suelto que ya
  estaba en el form no tumba la pregunta; lo nuevo lo niega el escritor de
  verdad (revisor propio de la 1.18.1). }
function EscribeTexto(const APath, ATexto: string; ALugar: TLugarDeTexto;
  AK: TEncKind; AEstricto: Boolean = True): string;
{ ...y BORRAR un fichero de un lugar FUERA de la jaula (en la jaula se borra
  a su papelera, y ltJaula se niega: GUARD-035): la misma pregunta, y en el
  IDE la copia antes en la casa (las mas viejas de ese fichero se purgan) -
  un borrado es la peor forma de pisar; remove-profile y remove-sdk borraban
  sin copia, irrecuperable (medida M3) -. Devuelve la ruta de la copia ('' si
  el lugar no la pide). Lanza la negativa. }
function BorraFichero(const APath: string; ALugar: TLugarDeTexto): string;

{ Un fichero de las caches del servidor (la configuracion fabricada para el
  motor, las tablas del disenador) por la puerta, con la casa como lugar, en
  UTF-8 con BOM. Si no se pudo (otro hilo la esta leyendo) y el fichero que
  esta ya dice ese mismo texto, vale el que esta; si no - otra cache, o
  la puerta que niega el sitio -, se lanza. Vivia en Lsp.Casa con su propia
  pregunta de "dentro". }
procedure EscribeEnCasaDelServidor(const AFichero, ATexto: string);

{ Un DOCUMENTO NUEVO en una carpeta de la casa (ADir), sin pisar nada: su
  nombre es <ABase>.md, o <ABase>-N.md (N = 2, 3...) si ya esta, y se RESERVA
  creandolo en exclusiva (CREATE_NEW: "existe? pues el siguiente" no basta,
  dos a la vez eligen el mismo - medido el 20-sep-2026 con ocho informes a la
  vez); luego el texto, por la puerta de escribir, entero o nada, en UTF-8
  con BOM (documentos para personas), y si no se pudo la reserva vacia no se
  queda. La puerta se pregunta ANTES con el nombre mas largo que se puede
  probar: la medida del escritor atomico es por longitud. Devuelve la ruta
  escrita; '' con AMotivo = la negativa de la puerta, o '' sin motivo si no
  quedo nombre libre. Lanza lo que lance la escritura. Los informes de
  delphi_report y la respuesta que no llego, al buzon (Lsp.Progreso, 1.29.1):
  estaba escrito en el primero. }
function EscribeDocumentoNuevo(const ADir, ABase, ATexto: string; out AMotivo: string): string;

{ El sello con que EMPIEZA el nombre de un documento de la casa (yyyymmdd-
  hhnnss): ordenados por nombre, salen por fecha. UNO para los que lo
  componen (delphi_report, la respuesta que no llego al buzon); estaba
  escrito a mano en los dos (hallazgo 10 del revisor de la 1.29.1). }
function SelloDeDocumento(AMomento: TDateTime): string;

{ Encoding-preserving load/save for other engines (scaffolder): text is
  decoded with the real encoding; save re-encodes with the SAME one, makes
  the pre-edit backup and writes atomically. AEncName as in delphi_read.
  PatchLoadText es la lectura de la JAULA que la tool ya comprobo a la
  entrada (la ruta llega de un parametro admitido); lo que se lee de OTRO
  sitio va por LeeTexto con su lugar. }
function PatchLoadText(const APath: string; out AEncName: string): string;
{ EL texto de un DESIGNER, binario o de texto, por la puerta de leer de la
  jaula (como PatchLoadText): el binario por su conversor
  (Lsp.DesignerBin.DesignerFileToText; AEncName vacio), el de texto con su
  codificacion. '' si bien; si no, el motivo (un binario danado). Lo hacian a
  mano cinco sitios, y el juicio de lo que alcanza una escritura
  (JuicioDeLoEscrito) leia un binario como texto y no juzgaba nada (W4 del
  revisor de cierre de la 1.18.2, medido: tras to-binary, quitar el campo del
  .pas no avisaba). }
function TextoDeDesigner(const APath: string; out ATexto, AEncName: string): string;
{ AEnsayo: todo lo que la escritura comprueba (la codificacion, la puerta y el
  +R que pregunta el escritor) sin copiar ni escribir; lanza lo que lanzaria.
  El preview de un changeset lo pide en vez de copiar las reglas del commit
  (decima revision). ANuevo: el texto es un fichero nuevo, y lo que haya en
  el disco no cuenta (el ensayo de un create tras un delete del mismo lote).
  Devuelve la nota de la copia diaria (la de BackupFile: su ruta si es nueva,
  que ya existia si no; '' sin copia), para quien la ensena: delphi_textedit
  decia "backup in __delphi-patch\" sin el fichero (test completo de Hermes,
  10-nov-2026). }
function PatchSaveText(const APath, AText, AEncName: string; AEnsayo: Boolean = False;
  ANuevo: Boolean = False): string;
{ LA REGLA DE IDA Y VUELTA de todo el que lee un fichero para reescribirlo
  (David, 9-oct-2026): '' si los bytes B de APath vuelven iguales al leerlos
  y escribirlos en su codificacion (K, la que dice EL detector); si no, la
  negativa (EDIT-038): reescribirlo cambiaria bytes que nadie toco. La
  preguntan los dos escritores de aqui (DoEdit y PatchSaveText) y el del
  vault: con el decodificador tolerante, sin esta pregunta, una nota con un
  BOM de UTF-8 y el cuerpo en ANSI volveria a disco con U+FFFD donde estan
  sus acentos, diciendo OK (revisor propio de la 4.1, 9-oct-2026). }
function ReescrituraDenegada(const APath: string; const B: TArray<Byte>;
  out K: TEncKind): string;
{ ...y su lado de la ESCRITURA: '' si los bytes que se van a escribir (AB,
  en AK) se leeran en AK; si no, la negativa EDIT-122. Una A con tilde y un
  superindice tres en ANSI (1252) son los bytes de una o con acento en UTF-8: un
  fichero cuyos bytes altos son todos asi lo leen como UTF-8 el detector y el
  IDE, con otros caracteres que los escritos (revisor propio de la 4.1,
  medido). Unos bytes sin byte alto no tienen codificacion que leer. La
  preguntan los dos escritores, la creacion de una unit y EncAlEscribir (que
  elige entonces UTF-8 con BOM para un fuente sin codificacion). }
function LecturaCambiada(const APath: string; const AB: TArray<Byte>; AK: TEncKind): string;
{ La codificacion en que se ESCRIBE un texto (4.1 de la 1.18.0, David
  9-oct-2026: "un fichero ASCII no tiene codificacion que respetar"). AK es
  la que se leyo; AAntes, los bytes que hay (AExiste = False: uno nuevo).
  Lo que ya tiene codificacion la conserva: un BOM o un byte alto la dicen.
  Un FUENTE (lo que lee dcc) que no tiene ninguna -solo ASCII- la elige con
  su primer caracter no ASCII, como el IDE al guardar (medido por David: una
  vocal acentuada va en ANSI -1252 en su maquina- sin BOM, sin preguntar; una
  letra griega, tras preguntar, en UTF-8 con BOM): ANSI (PaginaAnsi, la de la
  maquina) si cabe todo y se va a leer como ANSI, si no UTF-8 con BOM (una E
  acentuada y una comilla tipografica juntas son, en 1252, un caracter UTF-8
  valido: el IDE y el detector leerian el fichero como UTF-8). dcc lee un
  UTF-8 SIN BOM como ANSI: escribirlo asi era el fallo. Uno NUEVO va en la
  del IDE, y si esa es la ANSI y no cabe, en UTF-8 con BOM; nunca en UTF-8
  sin BOM (el IDE lo cura al guardar). Lo que ya tenia codificacion conserva
  la del ORIGEN.
  Un texto que no es un fuente ni un form y no tiene ninguna, la de uno NUEVO
  de su clase (EncDeFicheroNuevo: un .md, un .py o un .json en UTF-8, un
  proyecto del IDE con BOM): la preferencia del IDE con que se leyo su ASCII
  es de los fuentes, y con la ANSI un .md salia en 1252 (M4, V37 de la 1.23).
  Un form o un estilo, tal cual: los lee TParser, que sin BOM lee la ANSI
  (su regla). La preguntan los dos escritores (DoEdit,
  PatchSaveText), la creacion de una unit y el nombre de un componente
  (DSGN-111: en que codificacion quedara su unidad).
  Lo que cuenta es lo que el fichero tenia ANTES DE LA LLAMADA, no antes de
  cada escritura: una tanda con 'Accion' acentuado y luego una Omega se
  negaba -la primera entrada fijaba la ANSI- y al reves salia en UTF-8 con
  BOM, y el preview de un changeset decia que si y su commit que no (medido
  el 9-oct-2026). La primera escritura de la llamada apunta si el fichero
  existia y si tenia codificacion, y AtomicWrite la huella de lo que deja:
  si otro (un delete o un move del changeset) cambia la ruta entre medias, el
  origen se ancla de nuevo en lo que hay. OlvidaOrigenes vacia la lista al
  empezar y al acabar la llamada. }
function EncAlEscribir(const APath: string; AK: TEncKind;
  const AAntes: TArray<Byte>; AExiste: Boolean; const ATexto: string): TEncKind;
{ Nada de una llamada anterior en este hilo: los bytes de antes que apunto
  EncAlEscribir. AEnLlamada: empieza una (la puerta de cada llamada,
  Lsp.Host) o acaba (el filtro de salida), como los adjuntos de
  Lsp.InlineImages; fuera de una llamada no se apunta nada. }
procedure OlvidaOrigenes(AEnLlamada: Boolean);
{ Lo que la llamada acaba de dejar en APath: la huella que el origen espera
  encontrar la proxima vez. La llama AtomicWrite; publica para que la suite
  DUnitX pruebe la cadena de escrituras de una llamada sin tocar el disco. }
procedure ApuntaEscritoEnLaLlamada(const APath: string; const B: TArray<Byte>);
{ Lo que tenia APath antes de la primera escritura de la llamada en curso: si
  existia, si tenia codificacion y cual (el porque, en su cuerpo). Publica
  para el escritor de delphi_edit (DoEdit), que se queda en Lsp.Patch. }
procedure OrigenDeLaLlamada(const APath: string; const AAhora: TArray<Byte>;
  AExisteAhora: Boolean; out AExistia, ATeniaCodificacion: Boolean;
  out ACodificacion: TEncKind);
{ PatchSaveText para quien EDITA un texto insertando bloques compuestos con
  sLineBreak (los escritores del .dproj): lo que no toco se queda byte a
  byte y lo nuevo toma el salto dominante del fichero (ReescribeConSusSaltos).
  Un .dproj en LF quedaba mezclado (octava revision), y uno mixto tambien
  (V35 de la 1.23). No es para una copia, que va con los bytes de su origen. }
procedure PatchSaveConSuSalto(const APath, AText, AEncName: string);
{ Lo que el parser del IDE (MSXML 6, el que carga un proyecto) dice de un
  texto XML: '' si lo carga, o su error (linea y motivo) si no. EL juez de
  "esta bien formado" de lo que el servidor escribe de un fichero que el IDE
  carga como XML (EsXmlDelIde): PatchSaveText lo pregunta antes de escribir, y
  un proyecto que el IDE no abriese no se escribe (David, 21-oct-2026: las
  librerias XML de verdad, sin reinventar la rueda). }
function XmlMalFormadoSegunElIde(const AXml: string): string;

{ EL cerrojo de escritura del servidor, prestado a los otros motores.

  delphi_edit entero corre dentro de el desde siempre; el problema es que
  editar un fichero es leer-modificar-escribir y ESO no es atomico, asi que
  dos caminos distintos sobre el mismo fichero (delphi_textedit, registrar una
  unidad en el .dpr, el designer...) se pisaban entre si aunque cada escritura
  suelta fuese atomica. Medido 2026-09-20 con la bateria de concurrencia: de
  12 ediciones simultaneas al mismo fichero llegaban 6 al disco.

  Es recursivo (TCriticalSection lo es), asi que un motor puede tomarlo y
  llamar por dentro a ExecutePatch sin bloquearse. Las escrituras son raras y
  cortas: un cerrojo unico no cuesta nada, igual que en el vault. }
procedure EnterFileEdit;
procedure LeaveFileEdit;

{ Si ESTE hilo tiene el cerrojo de escritura (un EnterFileEdit sin su
  LeaveFileEdit). Lo pregunta el lint que corre tras escribir (LintDeForm):
  con el cerrojo cogido veda el motor (Lsp.Herencia.VedaElMotor), que
  arrancaba y paraba TODAS las escrituras del servidor (V173a de la 1.23.1,
  medido: un textedit de otro fichero espero 1,9 s de los 2,6 del edit de un
  .fmx con su base en otra unidad). La regla vivia en cada llamador
  (AConMotor, Lsp.DesignerMeta) y dos jueces del lint no la pasaban. }
function EnCerrojoDeEscritura: Boolean;

{ Lo escrito, releido del disco para el eco de verificacion. Si otro proceso
  lo coge justo despues y no se puede releer, la escritura YA se hizo: se
  devuelven los bytes escritos y ANota lo dice. Salia INTERNAL con el cambio
  aplicado, y quien obedece repetia una edicion ya hecha (verificacion de la
  tercera ronda, medido). Nunca lanza. }
function RelecturaDe(const APath: string; const AEscrito: TArray<Byte>;
  out ANota: string): TArray<Byte>;

{ Escritura atomica de bytes (temporal + MoveFileEx): la usa to-binary del
  disenador para dejar un .dfm binario como lo escribiria el IDE. }
procedure AtomicWrite(const APath: string; const B: TArray<Byte>); // = TBytes
{ Coloca un fichero YA HECHO (ALocal: una captura bajada, un zip, un
  volcado) en ADestino, el out= que eligio el agente: EL escritor de un
  producto, como AtomicWrite lo es de un contenido. Pregunta a la puerta en
  el momento de escribir, por la carpeta y por el fichero (la de la entrada
  pudo quedar atras: un logcat tarda hasta 55 s y un preview 75), sella lo
  que hubiera alli y lo sustituye de un solo gesto - un temporal junto al
  destino y el rename de AtomicWrite, con sus reintentos - bajo el cerrojo
  de escritura. ALocal no se queda nunca, se coloque o no. Lanza con el
  motivo si no se puede. Eran tres a mano: la captura (borrar y mover, sin
  reintento), el logcat (sin volver a preguntar a la puerta) y el zip de
  package (tampoco): P4 de la segunda revision de la 1.17.0.
  ALugar: donde cae. La jaula (el out= del agente) por defecto; una captura
  sin out= cae en la casa de las capturas (ltEntregables), trabajo nuestro
  que juzga su nombrador y no la jaula, con la pregunta de EscribeBytes
  (1.18.2, 2i: con la jaula, un agente confinado o sin raiz escribible
  recibia DESK-019). }
procedure ColocaProducto(const ALocal, ADestino: string; ALugar: TLugarDeTexto = ltJaula);
// y un CONTENIDO (el texto de un logcat, un recorte), con las mismas reglas
procedure ColocaContenido(const ADestino: string; const ABytes: TArray<Byte>;
  ALugar: TLugarDeTexto = ltJaula);
// ...y un TRAMO de un producto nuestro (ACuantos bytes desde ADesde de ALocal),
// copiado a trozos: lo que escribio un programa, sin las lineas de su lanzador
// (R1 del revisor del paisaje del 10-nov-2026: se leia entero en memoria)
procedure ColocaTramo(const ALocal: string; ADesde, ACuantos: Int64;
  const ADestino: string; ALugar: TLugarDeTexto = ltJaula);
{ LA pregunta de esos dos escritores, para quien la tiene que hacer ANTES de
  lo que tarda o de lanzar a otro: '' = se colocaria en ADestino; si no, la
  negativa que daria al colocar, y una CARPETA donde va el fichero (el
  renombre la tomaba por "otro proceso lo tiene" tras cinco reintentos). La
  hacia a mano delphi_adb antes del logcat (media: sin la carpeta) y
  delphi_styles build no la hacia: el conversor y brcc32 escribian el
  derivado ellos mismos (1.18.2, 2s). }
function ColocacionDenegada(const ADestino: string; ALugar: TLugarDeTexto = ltJaula): string;
{ ...y la de un VOLCADO de texto que el agente pide a un fichero suyo (el
  out= del logcat de delphi_adb, el de remote-run y output de
  delphi_paserver): la de ColocacionDenegada y que acabe en .txt o .log; si
  no, AExtension, el mensaje de la tool que lo pide. Estaba escrita a mano en
  delphi_adb y remote-run iba a ser la segunda (RUN-023, 1.29.1). }
function VolcadoDenegado(const ADestino, AExtension: string): string;
{ ...y lo que se dice de un volcado ya escrito en ese out=: logfile (su ruta),
  lines (como las cuenta delphi_read) y size (sus bytes), en AObj; la nota,
  cada tool la suya. Lo componian a mano el logcat de delphi_adb y
  remote-run/output (R8 del revisor del paisaje del 10-nov-2026). }
procedure PonElVolcado(AObj: TJSONObject; const ARuta: string; ALineas, ABytes: Int64);
{ EL nombre del temporal de una sustitucion junto a APath
  ('.<nombre>.<8 hex>.delphi-patch-tmp'): el de AtomicWrite, el de
  ColocaProducto y el del zip en proceso de package, que tenia uno propio
  (revisor de P4). Su lector, para que un recorrido salte los intermedios
  de CUALQUIER llamada, no solo el suyo. }
function TemporalDeSustitucion(const APath: string): string;
function EsTemporalDeSustitucion(const ANombre: string): Boolean;
{ ...y la purga de los que se quedaron: los intermedios de ADir (no de sus
  subcarpetas) con mas de una hora - de un escritor que murio a medias -, por
  la puerta de borrar de ALugar. La piden las casas del servidor que
  reescriben sus ficheros (las tablas del disenador, los ajustes del motor):
  sus purgas buscaban '.tmp', que ya no escribe nadie, o no los veian (lote 6
  del censo de jueces; V17 de la 1.23). Limpiar nunca tumba nada. }
procedure PurgaIntermediosViejos(const ADir: string; ALugar: TLugarDeTexto = ltCasa);
{ APath con el nombre de su ultimo trozo como lo tiene el DISCO (las
  mayusculas con que se creo); APath tal cual si no existe. Lo pregunta
  tambien la nota del par, que nombraba UFICHA.dfm (compuesto desde la unit)
  un UFicha.dfm del disco (26-oct-2026). }
function ComoEnDisco(const APath: string): string;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.SyncObjs,
  System.RegularExpressions,
  Winapi.Windows,
  Winapi.ActiveX, // CoInitializeEx: COM en el hilo de la llamada, como Lsp.Chm
  Winapi.msxml, // MSXML 6, el parser del IDE: el juez de lo que se escribe como XML
  Lsp.Guard,
  Lsp.Discovery,
  Lsp.Texts,
  Lsp.DesignerBin,
  Lsp.Rutas,
  Lsp.Lugares, // LugaresDelIde: lo que las puertas admiten del IDE
  Lsp.Casa,
  Lsp.Settings,
  Lsp.ShaCache, // Sha256DeBytes: la huella del origen de una llamada
  Lsp.Mascara,
  Lsp.Lineas,
  Lsp.Extensiones,
  Lsp.RegistroDelIde, // GuardaCopiaDelIde: la copia de un fichero del IDE antes de pisarlo
  Lsp.Papelera,       // BackupFile, GuardaContenidoActual: las copias de la jaula
  Lsp.Deteccion,      // DetectEnc, EncDeFicheroNuevo: EL detector de codificacion
  Lsp.Capturas,
  Lsp.NetDrives;

var
  GLock: TCriticalSection;

threadvar
  // cuantas veces tiene ESTE hilo el cerrojo (es recursivo): EnCerrojoDeEscritura
  TVecesEnCerrojo: Integer;

type
  { Lo que tenia una ruta antes de la PRIMERA escritura de la llamada, y lo
    que la llamada cree que hay en ella ahora. }
  TOrigenDeLlamada = record
    Ruta: string;
    Existia: Boolean;
    // tenia codificacion: un byte alto (un BOM tambien lleva). Solo eso y
    // cual se preguntan: guardar los bytes enteros de cada fuente tocado los
    // retenia hasta el final de la llamada (un rename de un arbol grande)
    TeniaCodificacion: Boolean;
    // ...y cual: la que leyo EL detector. Con el byte alto como unica marca,
    // una entrada que quitaba el ultimo acento dejaba el fichero en ASCII y la
    // siguiente lo leia en la preferencia del IDE: un ANSI acababa en UTF-8
    // sin BOM segun el orden (revisor propio de la 4.1, medido)
    Codificacion: TEncKind;
    // la huella (HuellaDeOrigen) de lo ultimo que se sabe de la ruta: lo que
    // habia, o lo que dejo AtomicWrite
    Esperado: string;
  end;

threadvar
  // Por hilo, como los adjuntos de Lsp.InlineImages: las tools son singletons
  // y el servidor HTTP atiende varias llamadas a la vez. Un hilo que no paso
  // por la puerta (GEnLlamada en falso) no apunta nada: decide escritura a
  // escritura, como antes
  GOrigenes: TArray<TOrigenDeLlamada>;
  GEnLlamada: Boolean;

procedure OlvidaOrigenes(AEnLlamada: Boolean);
begin
  GOrigenes := nil;
  GEnLlamada := AEnLlamada;
  // ...y las copias que hizo la llamada: empiezan y acaban con ella, por la
  // misma puerta (R6 del revisor del paisaje del 10-nov-2026)
  OlvidaCopiasDeLaLlamada(AEnLlamada);
end;

{ La huella de un contenido para el origen: '' = el fichero no existe (uno
  vacio tiene la suya). Con el sha de la casa (Lsp.ShaCache.Sha256DeBytes). }
function HuellaDeOrigen(AExiste: Boolean; const B: TArray<Byte>): string;
begin
  if AExiste then
    Result := Sha256DeBytes(B)
  else
    Result := '';
end;

{ Lo que tenia APath antes de la primera escritura de la llamada en curso:
  si existia, si tenia codificacion y cual. La primera vez que se pregunta por una
  ruta se apunta lo que hay AHORA (AAhora, AExisteAhora); las siguientes
  devuelven lo apuntado MIENTRAS en la ruta siga lo que la llamada dejo
  (AtomicWrite apunta su huella). Si hay otra cosa -un delete, un move o un
  deshacer del changeset, o un proceso de fuera, la cambiaron entre dos
  escrituras- lo apuntado ya no es el origen de ESE fichero, y se ancla de
  nuevo en lo de ahora: un changeset que editaba P, lo borraba y movia a P un
  fichero en UTF-8 con BOM lo dejaba en ANSI (revisor propio de la 4.1,
  medido). Fuera de una llamada, lo de ahora. }
procedure OrigenDeLaLlamada(const APath: string; const AAhora: TArray<Byte>;
  AExisteAhora: Boolean; out AExistia, ATeniaCodificacion: Boolean;
  out ACodificacion: TEncKind);
var
  I: Integer;
  Ahora: string;
  Nuevo: TOrigenDeLlamada;
begin
  AExistia := AExisteAhora;
  ATeniaCodificacion := HayByteAlto(AAhora);
  ACodificacion := DetectEnc(AAhora, EsRutaDeDesigner(APath));
  if not GEnLlamada then
    Exit;
  Ahora := HuellaDeOrigen(AExisteAhora, AAhora);
  for I := 0 to High(GOrigenes) do
    if SameFileName(GOrigenes[I].Ruta, APath) then
    begin
      if GOrigenes[I].Esperado <> Ahora then
      begin
        GOrigenes[I].Existia := AExisteAhora;
        GOrigenes[I].TeniaCodificacion := ATeniaCodificacion;
        GOrigenes[I].Codificacion := ACodificacion;
        GOrigenes[I].Esperado := Ahora;
      end;
      AExistia := GOrigenes[I].Existia;
      ATeniaCodificacion := GOrigenes[I].TeniaCodificacion;
      ACodificacion := GOrigenes[I].Codificacion;
      Exit;
    end;
  Nuevo.Ruta := APath;
  Nuevo.Existia := AExisteAhora;
  Nuevo.TeniaCodificacion := ATeniaCodificacion;
  Nuevo.Codificacion := ACodificacion;
  Nuevo.Esperado := Ahora;
  GOrigenes := GOrigenes + [Nuevo];
end;

{ Lo que la llamada acaba de dejar en APath: la huella que el origen espera
  encontrar la proxima vez. La llama AtomicWrite, por donde pasan todos los
  escritores de texto; solo cuenta para una ruta ya apuntada. }
procedure ApuntaEscritoEnLaLlamada(const APath: string; const B: TArray<Byte>);
var
  I: Integer;
begin
  if not GEnLlamada then
    Exit;
  for I := 0 to High(GOrigenes) do
    if SameFileName(GOrigenes[I].Ruta, APath) then
    begin
      GOrigenes[I].Esperado := HuellaDeOrigen(True, B);
      Break; // una entrada por ruta
    end;
end;

function EncAlEscribir(const APath: string; AK: TEncKind;
  const AAntes: TArray<Byte>; AExiste: Boolean; const ATexto: string): TEncKind;
var
  Existia, TeniaCodificacion: Boolean;
  Codificacion: TEncKind;

  // ANSI si cabe Y se va a leer como ANSI (LecturaCambiada, la ida y vuelta
  // del lado de la escritura): una E acentuada seguida de una comilla
  // tipografica son, en 1252, un caracter UTF-8 valido, y el IDE y el
  // detector leerian el fichero como UTF-8. Entonces UTF-8 con BOM, que no es
  // ambiguo para nadie (revisor propio de la 4.1)
  function AnsiSinAmbiguedad: Boolean;
  begin
    Result := CabeEnAnsi(ATexto) and
      (LecturaCambiada(APath, EncodeText(ATexto, ekAnsi), ekAnsi) = '');
  end;

begin
  Result := AK;
  if not EsRutaDeFuente(APath) then
  begin
    // M4: sin codificacion (ni BOM ni byte alto) y con su primer caracter no
    // ASCII, la de uno nuevo de su clase; un form o un estilo, que lee
    // TParser (sin BOM, en ANSI), se quedan en la suya
    if not EsRutaDeDesigner(APath) and not EsRutaDeEstilo(APath) and not HayByteAlto(AAntes) and
       not IsAscii(ATexto) then
      Result := EncKindOf(EncDeFicheroNuevo(APath));
    Exit;
  end;
  // lo de antes de la LLAMADA, apuntado tambien cuando este texto es ASCII:
  // la entrada siguiente de la tanda puede no serlo
  OrigenDeLaLlamada(APath, AAntes, AExiste, Existia, TeniaCodificacion, Codificacion);
  // un texto ASCII no elige nada: el fichero se queda con la del origen (una
  // tanda que ponia una Omega y luego la quitaba dejaba el BOM de en medio en
  // un fichero ASCII al empezar y al acabar; revisor propio de la 4.1)
  if IsAscii(ATexto) then
  begin
    if Existia then
      Result := Codificacion;
    Exit;
  end;
  if Existia then
  begin
    // la que tenia: la del ORIGEN, no la que se lee ahora (si una entrada
    // anterior quito su ultimo acento, ahora parece ASCII)
    if TeniaCodificacion then
      Exit(Codificacion);
    if AnsiSinAmbiguedad then
      Result := ekAnsi
    else
      Result := ekUtf8Bom;
  end
  // uno que nace en esta llamada: la del IDE (AK, la que se leyo de lo que
  // escribio su creacion) - la ANSI si cabe sin ambiguedad, si no UTF-8 con
  // BOM; y UTF-8 siempre CON BOM: el IDE no guarda un fuente UTF-8 sin el
  // (medido el 9-oct-2026: lo cura al guardar), y dcc lo leeria como ANSI
  else if (AK = ekUtf8) or ((AK = ekAnsi) and not AnsiSinAmbiguedad) then
    Result := ekUtf8Bom;
end;

procedure EnterFileEdit;
begin
  GLock.Enter;
  Inc(TVecesEnCerrojo);
end;

procedure LeaveFileEdit;
begin
  Dec(TVecesEnCerrojo);
  GLock.Leave;
end;

function EnCerrojoDeEscritura: Boolean;
begin
  Result := TVecesEnCerrojo > 0;
end;

function RelecturaDe(const APath: string; const AEscrito: TArray<Byte>;
  out ANota: string): TArray<Byte>;
begin
  ANota := '';
  try
    Result := TFile.ReadAllBytes(APath);
  except
    on E: Exception do
    begin
      Result := AEscrito;
      // E.Message lleva la ruta REAL (EFOpenError) y esta nota va dentro de
      // un EXITO de delphi_edit/textedit, que el filtro de salida deja tal
      // cual: lo que la tool compone, enmascarado a mano (Lsp.Mascara,
      // MaskDriveText; revision de paisaje del 4-oct-2026)
      ANota := MsgFmt(SN_EDIT_RELECTURA_FALLIDA_FMT, [MaskDriveText('', E.Message)]);
    end;
  end;
end;

const
  TEMPORAL_DE_SUSTITUCION_EXT = '.delphi-patch-tmp';

{ El temporal de una sustitucion, junto a APath (el rename es de un solo
  gesto solo en la misma carpeta). Lleva un fragmento GUID: con nombre fijo,
  dos escrituras del MISMO fichero por caminos distintos compartian el
  intermedio - una se llevaba los bytes de la otra al renombrar y la
  segunda moria con "rename atomico fallido" (medido 2026-09-20). El cerrojo
  ya las serializa; esto protege ademas a quien escriba sin pasar por el. }
function TemporalDeSustitucion(const APath: string): string;
begin
  Result := TPath.Combine(TPath.GetDirectoryName(APath),
    '.' + TPath.GetFileName(APath) + '.' +
    FragmentoUnico + TEMPORAL_DE_SUSTITUCION_EXT);
end;

function EsTemporalDeSustitucion(const ANombre: string): Boolean;
begin
  Result := TRegEx.IsMatch(ANombre, '^\..+\.' + FRAGMENTO_UNICO_PATRON +
    TRegEx.Escape(TEMPORAL_DE_SUSTITUCION_EXT) + '$', [roIgnoreCase]);
end;

procedure PurgaIntermediosViejos(const ADir: string; ALugar: TLugarDeTexto);
const
  EDAD_MINIMA = 1 / 24; // una hora: un escritor vivo acaba en segundos
var
  Edad: TDateTime;
begin
  try
    for var F in EntradasDeCarpeta(ADir) do
      if EsTemporalDeSustitucion(TPath.GetFileName(F)) and FileAge(F, Edad) and
         (Now - Edad > EDAD_MINIMA) then
        try
          BorraFichero(F, ALugar);
        except
          // lo que no se deja borrar se queda
        end;
  except
    // limpiar nunca tumba nada
  end;
end;

{ APath sustituido por ATmp de un solo gesto (MoveFileEx con REPLACE); si no
  se puede, ATmp se borra y se lanza con la causa. El final de AtomicWrite y
  de ColocaProducto. }
// MotivoDeRenombre (la causa de un rename que Windows nego) vive en Lsp.Guard
// desde la 1.23 (V19): la usan tambien el move y la mezcla

{ La fecha de creacion de APath, un fichero que la operacion acaba de dejar;
  nunca lanza (si no se puede, se queda la que tiene) y no sigue un enlace. }
procedure PonFechaDeCreacion(const APath: string; const AFecha: TFileTime);
var
  H: THandle;
begin
  H := CreateFile(PChar(APath), FILE_WRITE_ATTRIBUTES, FILE_SHARE_READ or
    FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_EXISTING,
    FILE_FLAG_OPEN_REPARSE_POINT, 0);
  if H = INVALID_HANDLE_VALUE then
    Exit;
  try
    SetFileTime(H, @AFecha, nil, nil);
  finally
    CloseHandle(H);
  end;
end;

{ APath con el nombre de su ultimo trozo como lo tiene el DISCO (las
  mayusculas con que se creo); APath tal cual si no existe. }
function ComoEnDisco(const APath: string): string;
var
  FD: TWin32FindData;
  H: THandle;
begin
  Result := APath;
  H := FindFirstFile(PChar(APath), FD);
  if H = INVALID_HANDLE_VALUE then
    Exit;
  Winapi.Windows.FindClose(H);
  Result := TPath.Combine(TPath.GetDirectoryName(APath), FD.cFileName);
end;

procedure SustituyePorRenombre(const ATmp, APath: string);
var
  Antes: TWin32FileAttributeData;
  Destino: string;
begin
  // con el nombre como esta en el DISCO: MoveFileEx deja el que se le da, y
  // escribir Mcp.Tools.ADB.pas renombraba Mcp.Tools.Adb.pas (medido el
  // 23-oct-2026 con un delphi_edit; git, que no distingue, no lo ensena)
  Destino := ComoEnDisco(APath);
  // la fecha de CREACION de lo que se sustituye se conserva: el renombre deja
  // la del temporal (medido por el revisor de P3: no hay tunneling), y el
  // vault (file.ctime de Obsidian y Dataview) o quien ordene por ella veia
  // el fichero recien nacido en cada escritura
  var TeniaFecha := GetFileAttributesEx(PChar(APath), GetFileExInfoStandard, @Antes);
  // Un lector de un instante (el preview de un changeset, una busqueda, el
  // antivirus) tiene el fichero abierto sin compartir el borrado y el rename
  // rebota: RenombraConReintentos (Lsp.Guard; tambien el de la caja de paquetes
  // del render) insiste unos instantes antes de decir que algo lo tiene
  // (verificacion de la tercera ronda: cuatro EDIT-106 con varias sesiones,
  // todos del propio servidor; reintentar funcionaba). El codigo de Windows,
  // ANTES de borrar el temporal (despues salia 0)
  var Codigo: Cardinal := 0;
  if not RenombraConReintentos(ATmp, Destino, MOVEFILE_REPLACE_EXISTING, Codigo) then
  begin
    // un temporal que no se deja borrar no cambia la causa que se dice
    try
      TFile.Delete(ATmp);
    except
    end;
    raise Exception.Create(MotivoDeRenombre(APath, Codigo));
  end;
  if TeniaFecha then
    PonFechaDeCreacion(APath, Antes.ftCreationTime);
end;

{ APath sustituido por los bytes B: el temporal junto a el, escrito, y el
  renombre de un solo gesto. A medias no se queda: un temporal suelto no lo
  ve nadie para borrarlo (salia en delphi_list y git add se lo llevaba).
  Eran dos copias, y la de AtomicWrite - el escritor de casi toda la jaula -
  no lo borraba si la escritura fallaba (disco lleno; revisor del paisaje de
  la 1.28, J8). }
procedure SustituyePorBytes(const APath: string; const B: TBytes);
var
  Tmp: string;
begin
  Tmp := TemporalDeSustitucion(APath);
  try
    TFile.WriteAllBytes(Tmp, B);
  except
    System.SysUtils.DeleteFile(Tmp);
    raise;
  end;
  SustituyePorRenombre(Tmp, APath); // si no puede, borra el temporal y lanza
end;

procedure AtomicWrite(const APath: string; const B: TBytes);
var
  Motivo: string;
begin
  // EL escritor pregunta el mismo (Lsp.Guard.EscrituraDenegada): quien lo
  // llama puede haberse olvidado, o escribir un fichero que no le pasaron
  // sino que saco de un .dpr (auditoria 25-sep-2026).
  // ...y un fichero con el atributo de solo lectura no se sustituye: se
  // dice ANTES, que el rename lo tomaba por "otro proceso lo tiene"
  Motivo := SustitucionDenegada(APath);
  // ...y la medida de este escritor: el temporal de abajo anade 27
  // caracteres, y de 233 a 259 moria como SYS-009 (GUARD-028, la misma
  // pregunta que WriteTargetDenied hace a la entrada)
  if Motivo = '' then
    Motivo := RutaLargaDenegada(APath);
  if Motivo <> '' then
    raise Exception.Create(Motivo);
  SustituyePorBytes(APath, B);
  ApuntaEscritoEnLaLlamada(APath, B); // lo que el origen espera encontrar
end;

function ColocacionDenegada(const ADestino: string; ALugar: TLugarDeTexto): string;
begin
  Result := CarpetaEnVezDeFichero(ADestino);
  if Result <> '' then
    Exit;
  // la jaula: la carpeta y el fichero. Otro lugar (la casa de los
  // entregables), la pregunta de SU puerta, la de EscribeBytes (2i)
  if ALugar = ltJaula then
  begin
    Result := EscrituraDenegada(TPath.GetDirectoryName(ADestino));
    // el destino que nombra el agente: su puerta (solo lectura incluida),
    // las carpetas muertas y la medida del escritor (V6 de la 1.23: las
    // muertas las sumaba cada llamador a su modo, y el logcat no)
    if Result = '' then
      Result := WriteTargetDenied(ADestino);
    if Result = '' then
      Result := SustitucionDenegada(ADestino);
    // lo que se sustituye se copia antes (GuardaContenidoActual): es leerlo,
    // y quien pregunta antes de lanzar nada (styles build) lo sabe aqui
    if Result = '' then
      Result := EnlaceDuroIlegible(ADestino);
  end
  else
    Result := LugarDeEscrituraDenegado(ADestino, ALugar);
end;

function VolcadoDenegado(const ADestino, AExtension: string): string;
begin
  Result := ColocacionDenegada(ADestino);
  // la extension como la compara el disco (TieneExtension; E12 de la 1.28)
  if (Result = '') and not TieneExtension(ADestino, ['.txt', '.log']) then
    Result := AExtension;
end;

procedure PonElVolcado(AObj: TJSONObject; const ARuta: string; ALineas, ABytes: Int64);
begin
  AObj.AddPair('logfile', ARuta);
  AObj.AddPair('lines', TJSONNumber.Create(ALineas));
  AObj.AddPair('size', TJSONNumber.Create(ABytes));
end;

function EnLugarDeTexto(const APath: string; ALugar: TLugarDeTexto;
  AParaEscribir: Boolean): Boolean; forward;
type
  { Lo que el destino ya dice frente a lo que se va a colocar en el }
  TFrenteAlDestino = (fdDistinto, fdIgual, fdCrece);

{ El destino frente a lo que se va a colocar: el producto ALocal (ACuantos < 0:
  entero; si no, su tramo de ACuantos bytes desde ADesde) o los bytes ABytes.
  fdIgual: ya dice EXACTAMENTE eso, y ni se reescribe ni se copia (A4 de la
  1.18.4, I5 de la 1.28). fdCrece: es su PRINCIPIO y lo nuevo solo anade:
  sustituirlo no pierde nada (un output con out= sobre un programa vivo sellaba
  en la papelera una copia entera de lo anterior en CADA llamada: R7 del
  revisor del paisaje del 10-nov-2026). A trozos, sin subir ninguno entero (se
  leian los dos enteros: R1). Lo que no se puede leer es distinto. }
function FrenteAlDestino(const ADestino, ALocal: string; ADesde, ACuantos: Int64;
  const ABytes: TBytes; ALugar: TLugarDeTexto): TFrenteAlDestino;
const
  TROZO = 1 shl 20;
var
  D, L: TStream;
  BD, BL: TBytes;
  TamD, TamNuevo, Hecho: Int64;
  N: Integer;
begin
  Result := fdDistinto;
  if not TFile.Exists(ADestino) then
    Exit;
  D := nil;
  L := nil;
  try
    try
      D := AbreParaLeer(ADestino, [ALugar]);
      if ALocal = '' then
      begin
        L := TBytesStream.Create(ABytes);
        ADesde := 0;
        TamNuevo := Length(ABytes);
      end
      else
      begin
        L := AbreParaLeer(ALocal, [ltTemporal, ALugar]);
        if ADesde < 0 then
          ADesde := 0;
        if ADesde > L.Size then
          ADesde := L.Size;
        TamNuevo := L.Size - ADesde;
        if (ACuantos >= 0) and (ACuantos < TamNuevo) then
          TamNuevo := ACuantos;
      end;
      TamD := D.Size;
      // mas largo que lo nuevo: ni igual ni su principio (y no se lee nada)
      if TamD > TamNuevo then
        Exit;
      L.Position := ADesde;
      SetLength(BD, TROZO);
      SetLength(BL, TROZO);
      Hecho := 0;
      while Hecho < TamD do
      begin
        N := TROZO;
        if TamD - Hecho < N then
          N := TamD - Hecho;
        D.ReadBuffer(BD[0], N);
        L.ReadBuffer(BL[0], N);
        if not CompareMem(@BD[0], @BL[0], N) then
          Exit;
        Inc(Hecho, N);
      end;
      if TamD = TamNuevo then
        Result := fdIgual
      else
        Result := fdCrece;
    except
      Result := fdDistinto;
    end;
  finally
    L.Free;
    D.Free;
  end;
end;

{ El nucleo de ColocaProducto, ColocaContenido y ColocaTramo: ALocal <> '' y
  ACuantos < 0 mueve ese fichero; ALocal <> '' y ACuantos >= 0 copia su tramo
  (ACuantos bytes desde ADesde) a trozos; si no, escribe ABytes. }
procedure Coloca(const ADestino, ALocal: string; ADesde, ACuantos: Int64;
  const ABytes: TBytes; ALugar: TLugarDeTexto);
var
  Motivo, Dir, DirLocal, Tmp, Copia, Ancestro: string;
  Nuestro, Colocado: Boolean;
  Frente: TFrenteAlDestino;
begin
  Dir := TPath.GetDirectoryName(ADestino);
  // sin ALocal (ColocaContenido) no hay carpeta de origen: GetDirectoryName('')
  // LANZA "File name is empty" (System.IOUtils, medido) y ColocaContenido no
  // colocaba nada desde que nacio - el logcat con out= de delphi_adb
  DirLocal := '';
  if ALocal <> '' then
    DirLocal := TPath.GetDirectoryName(ALocal);
  Tmp := '';
  Ancestro := '';
  Colocado := False;
  // el producto se MUEVE y se borra: solo uno nuestro - de la temporal del
  // servidor o de la carpeta del destino (la que aprueba la puerta). Una
  // carpeta de descarga DENTRO del destino ya no: delphi_desktop baja
  // siempre a la casa de capturas desde la 1.18.2 (2z/2af)
  // (nuestro temporal por SU lugar, ServerTempDir con la casa de capturas
  // dentro: EnTemporal era cualquier carpeta llamada __delphi-temp, en
  // cualquier sitio; revisor del paisaje de la 1.27)
  Nuestro := (ALocal = '') or EnLugarDeTexto(ALocal, ltTemporal, False) or SameFileName(DirLocal, Dir);
  if not Nuestro then
    raise Exception.Create(MsgFmt(SR_COLOCA_PRODUCTO_AJENO_FMT, [ALocal, ADestino]));
  // Todo, bajo el cerrojo, de la puerta al rename: un delphi_move (que escribe
  // con el) no puede cambiar la carpeta del destino por un enlace entre la
  // pregunta y la escritura (revisor de P4: se preguntaba fuera). Lo que
  // tarda - empaquetar, bajar, el logcat - queda fuera: aqui solo se coloca.
  EnterFileEdit;
  try
  try
    Motivo := ColocacionDenegada(ADestino, ALugar);
    if Motivo <> '' then
      raise Exception.Create(Motivo);
    // lo que ya dice ESO no se reescribe ni se copia: la regla de EscribeBytes
    // (MismosBytes, A4 de la 1.18.4), aqui para los productos y los derivados.
    // Un styles build repetido sellaba en la papelera una copia IDENTICA de
    // cada .bin.style en CADA llamada (medido el 6-nov, mismo SHA-256: I5 del
    // cierre de la 1.28). El producto se borra igual (el finally)
    Frente := FrenteAlDestino(ADestino, ALocal, ADesde, ACuantos, ABytes, ALugar);
    if Frente = fdIgual then
    begin
      Colocado := True;
      Exit;
    end;
    // lo que se cree para colocarlo se quita si al final no se coloca
    Ancestro := PrimerAncestroQueExiste(Dir);
    CrearCarpeta(Dir);
    if SameFileName(DirLocal, Dir) and (ACuantos < 0) then
      Tmp := ALocal // ya junto al destino (el zip en proceso): un solo rename, con sus reintentos
    else
    begin
      Tmp := TemporalDeSustitucion(ADestino);
      if ALocal = '' then
        TFile.WriteAllBytes(Tmp, ABytes)
      // un tramo, a trozos: lo que escribio un programa puede ser de gigas y
      // se subia entero en memoria (R1 del revisor del paisaje del 10-nov)
      else if ACuantos >= 0 then
      begin
        var Origen := AbreParaLeer(ALocal, [ltTemporal, ALugar]);
        try
          var Escrito := TFileStream.Create(Tmp, fmCreate);
          try
            Origen.Position := ADesde;
            // CopyFrom con 0 copia el flujo ENTERO: un tramo vacio no copia nada
            if ACuantos > 0 then
              Escrito.CopyFrom(Origen, ACuantos);
          finally
            Escrito.Free;
          end;
        finally
          Origen.Free;
        end;
      end
      // de la temporal: puede ser otro volumen, tambien con la misma letra
      // (un punto de montaje); MoveFileEx copia cuando hace falta y no lo
      // decide por el TEXTO de la raiz, como TFile.Move
      else if not MoveFileEx(PChar(ALocal), PChar(Tmp), MOVEFILE_COPY_ALLOWED) then
        raise Exception.Create(MotivoDeRenombre(ADestino, GetLastError));
    end;
    // la copia sellada de lo que habia y el rename, sin que otro escritor se
    // cuele entre los dos (dos empaquetados al mismo out= sellaban la misma
    // copia y el zip de en medio se perdia: sexta revision). Lo que solo
    // CRECE no pierde nada y no se copia (FrenteAlDestino, R7)
    Copia := '';
    if Frente <> fdCrece then
      Copia := GuardaContenidoActual(ADestino);
    try
      SustituyePorRenombre(Tmp, ADestino); // si falla, borra el temporal
    except
      // la copia sellada de algo que no se sustituyo no se queda (EL
      // quitador de Lsp.Guard, con su marca; H7 de Fable)
      QuitaCopiaDeSeguridad(Copia, '');
      raise;
    end;
    Tmp := '';
    Colocado := True;
  finally
    // ni el producto ni el intermedio se quedan nunca, ni las carpetas que
    // se crearon para nada
    if (ALocal <> '') and TFile.Exists(ALocal) then
      try
        TFile.Delete(ALocal);
      except
      end;
    if (Tmp <> '') and TFile.Exists(Tmp) then
      try
        TFile.Delete(Tmp);
      except
      end;
    // con la puerta del LUGAR de la colocacion: la casa de capturas esta
    // fuera de la jaula y con la de la jaula se quedaban (2aa de la 1.18.2)
    if not Colocado and (Ancestro <> '') then
      QuitaCarpetasCreadas(Dir, Ancestro,
        function(const ARuta: string): string
        begin
          Result := LugarDeEscrituraDenegado(ARuta, ALugar);
        end);
  end;
  finally
    LeaveFileEdit;
  end;
end;

procedure ColocaProducto(const ALocal, ADestino: string; ALugar: TLugarDeTexto);
begin
  Coloca(ADestino, ALocal, 0, -1, nil, ALugar);
end;

procedure ColocaTramo(const ALocal: string; ADesde, ACuantos: Int64;
  const ADestino: string; ALugar: TLugarDeTexto);
begin
  if ACuantos < 0 then
    ACuantos := 0; // un tramo dice cuanto: nunca "todo" (eso es ColocaProducto)
  Coloca(ADestino, ALocal, ADesde, ACuantos, nil, ALugar);
end;

procedure ColocaContenido(const ADestino: string; const ABytes: TBytes;
  ALugar: TLugarDeTexto);
begin
  Coloca(ADestino, '', 0, -1, ABytes, ALugar);
end;

function ReescrituraDenegada(const APath: string; const B: TArray<Byte>;
  out K: TEncKind): string;
begin
  K := DetectEnc(B, EsRutaDeDesigner(APath));
  // "esto no es texto" (LooksBinaryBytes, la regla de delphi_read y de
  // delphi_edit) tambien aqui, donde reescriben TODOS: adduses edito un .pas
  // con bytes NUL que old/new negaba con TEXT-008 (EH4 del revisor del paisaje
  // de la 1.29, medido en vivo el 7-nov-2026). Un form binario es otra cosa,
  // con su camino propio (to-text)
  if LooksBinaryBytes(B) and not (EsRutaDeDesigner(APath) and IsBinaryDesignerBytes(B)) then
    Exit(MsgFmt(SR_TEXT_PARECE_BINARIO_FMT, [TPath.GetFileName(APath)]));
  if BytesVuelvenIgual(B, K) then
    Result := ''
  else
    Result := MsgFmt(SR_EDIT_BYTES_NO_VUELVEN_FMT, [TPath.GetFileName(APath), EncName(K)]);
end;

function LecturaCambiada(const APath: string; const AB: TArray<Byte>; AK: TEncKind): string;
var
  KLeida: TEncKind;
begin
  Result := '';
  if not HayByteAlto(AB) then
    Exit;
  KLeida := DetectEnc(AB, EsRutaDeDesigner(APath));
  if KLeida <> AK then
    Result := MsgFmt(SR_EDIT_SE_LEERIA_DISTINTO_FMT,
      [TPath.GetFileName(APath), EncName(AK), EncName(KLeida), EncName(AK)]);
end;

{ Los bytes de APath como texto, por EL detector: lo que leen las dos puertas
  de lectura (LeeTexto y PatchLoadText), una sola vez escrito. }
function TextoDeBytes(const B: TArray<Byte>; AEsDesigner: Boolean; out AEncName: string): string;
var
  K: TEncKind;
begin
  K := DetectEnc(B, AEsDesigner);
  AEncName := EncName(K);
  Result := DecodeBytes(B, K);
end;

function TextoDeFichero(const APath: string; out AEncName: string): string;
begin
  Result := TextoDeBytes(TFile.ReadAllBytes(APath), EsRutaDeDesigner(APath), AEncName);
end;

// EnAlgunLugar, la comparacion de los lugares, vive en Lsp.Rutas: la jaula
// tambien la pregunta (la zona de biblioteca, M1 de la 1.18.0)

{ Los sysroots que nombran los .sdk de la carpeta de perfiles del IDE: los
  que usan msbuild y paclient, tenga o no el SDK su asiento en el registro
  (un .sdk sin asiento es un estado que profiles diagnostica; test_sdk).
  Saberlos pide LEER, asi que no estan en LugaresDelIde, que no lee nada:
  cada .sdk se lee solo si su ruta REAL cae en esos lugares. Por la puerta
  entera se preguntaria a si misma, y un .sdk que fuese un enlace hacia fuera
  la haria girar sin fin. }
function SysrootsDeLosSdk: TArray<string>;
var
  Info: TRadStudioInfo;
  Enc, S: string;
begin
  Result := nil;
  Info := DiscoverRadStudio;
  if not Info.Found then
    Exit;
  for var F in SdksDelIde(Info.Version) do // EL lector de la lista
    try
      if not EnAlgunLugar(RealPath(F), LugaresDelIde) then
        Continue;
      S := SysrootDeSdk(Info.Version, TextoDeFichero(F, Enc));
      if (S.Trim <> '') and not S.Contains('$(') then
        Result := Result + [S];
    except
      // un .sdk que no se deja leer no nombra nada
    end;
end;

{ APath esta en el lugar ALugar - uno que no es la jaula: esa tiene sus
  puertas (ReadPathDenied, SustitucionDenegada) -. UNA pregunta para leer y
  para escribir; AParaEscribir quita del IDE su instalacion. }
function EnLugarDeTexto(const APath: string; ALugar: TLugarDeTexto;
  AParaEscribir: Boolean): Boolean;

  // la ruta REAL que se juzga en los lugares POR ruta real (IDE, vault). Para
  // leer, la de APath: la lectura lee lo de detras de un enlace. Para
  // escribir o borrar, la de su CARPETA con el nombre (RutaDelEnlace): alli
  // nacen el temporal y el renombre, y RealPath(APath) sigue tambien al
  // ULTIMO enlace - una carpeta de fuera con un enlace que volvia dentro
  // pasaba la puerta y el temporal nacia fuera (revisor de P3, medido con
  // uniones) -; y un APath que es el mismo un enlace no se escribe ni se
  // borra: lo de detras no es de la operacion. '' = no es de ningun lugar.
  function Real: string;
  begin
    if not AParaEscribir then
      Result := RealPath(APath)
    else if EsEnlace(APath) then
      Result := ''
    else
      Result := RutaDelEnlace(APath);
  end;

  // los sitios de ALugar POR TEXTO, para un UNC: la casa, el temporal y los
  // entregables son carpetas locales del servidor (ninguno)
  function SitiosDeTexto: TArray<string>;
  begin
    case ALugar of
      ltIde: Result := [InstalacionDelIde] + LugaresDelIde(AParaEscribir) + SysrootsDeLosSdk;
      ltVault: Result := [VaultPath];
      ltBiblioteca: Result := LugaresDeLaBiblioteca;
    else
      Result := [];
    end;
  end;

var
  R: string;
begin
  Result := False;
  // solo lo absoluto: una relativa se resolveria contra la carpeta de
  // trabajo del proceso (System32 en el servicio)
  if not EsRutaAbsoluta(APath.Trim) then
    Exit;
  // un UNC solo se resuelve en disco (RealPath) si por TEXTO cae en un sitio de
  // ese lugar: resolverlo conecta por SMB, con la cuenta del servicio, con el
  // host que nombre el agente (un $I, el search path de un .dproj), ANTES de
  // negar - la jaula ya lo niega asi, por texto (UncFueraDeLugares). P1 del
  // revisor del paisaje de la 1.29, medido: 23 s con \\192.0.2.1 en un search
  // path, contra 2 s con una ruta local que no existe
  if EsUnc(ConBarrasDeWindows(APath.Trim)) then
  begin
    var PorTexto := False;
    for var S in SitiosDeTexto do
      if EnLugar(ConBarrasDeWindows(APath.Trim), ConBarrasDeWindows(S.Trim), False) then
        PorTexto := True;
    if not PorTexto then
      Exit;
  end;
  case ALugar of
    // del IDE: primero lo que se mide sin leer; los sysroots de sus .sdk (que
    // piden leerlos) solo si no cae ahi
    ltIde:
      begin
        R := Real;
        // los que nombra un .sdk, solo para LEER: un .sdk no decide donde
        // escribe el servidor (medida M3: la libX.so iba a lo que listase).
        // La instalacion, la primera y sin LugaresDelIde: saber la carpeta de
        // los SDK pide la tabla del IDE, que lee rsvars.bat de la instalacion
        // por esta puerta, y se preguntaba a si misma hasta reventar la pila
        // (A5 de la 1.27; con una redefinicion con macros ya pasaba)
        Result := (R <> '') and ((not AParaEscribir and EnAlgunLugar(R, [InstalacionDelIde])) or
          EnAlgunLugar(R, LugaresDelIde(AParaEscribir)) or
          (not AParaEscribir and EnAlgunLugar(R, SysrootsDeLosSdk)));
      end;
    // los lugares del SERVIDOR (su casa y su temporal), por su forma larga y
    // sin enlaces en el camino, no por la ruta real: la virtualizacion MSIX
    // los parte en dos bajo AppData (Lsp.Guard.EnLugarSinEnlaces, medido)
    ltCasa:
      for var C in CarpetasDeLaCasa do
        if EnLugarSinEnlaces(APath, C) then
          Exit(True);
    ltTemporal:
      Result := EnLugarSinEnlaces(APath, ServerTempDir);
    ltVault:
      begin
        R := Real;
        Result := (R <> '') and EnAlgunLugar(R, [VaultPath]);
      end;
    // solo se lee: nada se escribe en la biblioteca del IDE
    ltBiblioteca:
      Result := not AParaEscribir and EnAlgunLugar(RealPath(APath), LugaresDeLaBiblioteca);
    // las capturas de un agente: lo dice su nombrador, sin enlaces en el
    // camino, para leer y para escribir
    ltEntregables:
      Result := EnCasaDeEntregables(APath);
  end;
end;

{ Como se nombra un lugar en la negativa GUARD-034. }
function NombreDeLugar(ALugar: TLugarDeTexto; AParaEscribir: Boolean): string;
begin
  case ALugar of
    ltIde:
      if AParaEscribir then
        Result := MsgText(SF_LUGAR_IDE_ESCRIBIR)
      else
        Result := MsgText(SF_LUGAR_IDE);
    ltCasa: Result := MsgText(SF_LUGAR_CASA);
    ltTemporal: Result := MsgText(SF_LUGAR_TEMPORAL);
    ltVault: Result := MsgText(SF_LUGAR_VAULT);
    ltBiblioteca: Result := MsgText(SF_LUGAR_BIBLIOTECA);
    ltEntregables: Result := MsgText(SF_LUGAR_ENTREGABLES);
  else
    Result := '';
  end;
end;

function LugarDeLecturaDenegado(const APath: string; ALugares: TLugaresDeTexto): string;
var
  Lugares: string;
begin
  Result := '';
  // la jaula primero: su negativa es la que mejor se explica
  if ltJaula in ALugares then
  begin
    Result := ReadPathDenied(APath);
    if Result = '' then
      Exit;
  end;
  for var L in ALugares - [ltJaula] do
    if EnLugarDeTexto(APath, L, False) then
      Exit('');
  if Result <> '' then
    Exit;
  Lugares := '';
  for var L in ALugares - [ltJaula] do
  begin
    if Lugares <> '' then
      Lugares := Lugares + ', ';
    Lugares := Lugares + NombreDeLugar(L, False);
  end;
  Result := MsgFmt(SR_GUARD_FUERA_DE_LUGARES_FMT, [APath, Lugares]);
end;

function LugarDeEscrituraDenegado(const APath: string; ALugar: TLugarDeTexto): string;
begin
  // la medida del escritor atomico (el temporal de al lado anade 27)
  Result := RutaLargaDenegada(APath);
  if Result <> '' then
    Exit;
  // la jaula: lo que pregunta su escritor (la puerta sobre la ruta real, el
  // modo de solo lectura y el +R)
  if ALugar = ltJaula then
    Exit(SustitucionDenegada(APath));
  if not EnLugarDeTexto(APath, ALugar, True) then
    Exit(MsgFmt(SR_GUARD_FUERA_DE_LUGARES_FMT, [APath, NombreDeLugar(ALugar, True)]));
  Result := SoloLecturaDenegado(APath);
end;

{ La negativa de la puerta como excepcion: lo que comparten LeeTexto y
  LeeBytes. }
procedure ExigeLugarDeLectura(const APath: string; ALugares: TLugaresDeTexto);
var
  Motivo: string;
begin
  Motivo := LugarDeLecturaDenegado(APath, ALugares);
  if Motivo <> '' then
    raise Exception.Create(Motivo);
end;

function LeeTexto(const APath: string; ALugares: TLugaresDeTexto; out AEncName: string): string;
begin
  ExigeLugarDeLectura(APath, ALugares);
  Result := TextoDeFichero(APath, AEncName);
end;

function LeeBytes(const APath: string; ALugares: TLugaresDeTexto): TArray<Byte>;
begin
  ExigeLugarDeLectura(APath, ALugares);
  Result := TFile.ReadAllBytes(APath);
end;

function AbreParaLeer(const APath: string; ALugares: TLugaresDeTexto): TStream;
begin
  ExigeLugarDeLectura(APath, ALugares);
  // como TFile.ReadAllBytes: quien escribe no puede, quien lee si
  Result := TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite);
end;

function LeeTrozoDeBytes(const APath: string; ALugares: TLugaresDeTexto;
  ADesde: Int64; AMax: Integer; out ATamano: Int64): TArray<Byte>;
var
  F: TStream;
  N: Int64;
begin
  F := AbreParaLeer(APath, ALugares);
  try
    ATamano := F.Size;
    if ADesde < 0 then
      ADesde := 0;
    if ADesde > ATamano then
      ADesde := ATamano;
    N := ATamano - ADesde;
    if N > AMax then
      N := AMax;
    if N < 0 then
      N := 0;
    SetLength(Result, N);
    F.Position := ADesde;
    if N > 0 then
      F.ReadBuffer(Result[0], N);
  finally
    F.Free;
  end;
end;

function LineasDeUnTramo(const APath: string; ALugares: TLugaresDeTexto;
  ADesde, ACuantos: Int64): Int64;
const
  TROZO = 1 shl 20; // multiplo de 4: un trozo no parte una unidad de UTF-32
var
  F: TStream;
  B: TArray<Byte>;
  K: TEncKind;
  Cuenta: TCuentaDeLineas;
  Bom, N: Integer;
begin
  F := AbreParaLeer(APath, ALugares);
  try
    if ADesde < 0 then
      ADesde := 0;
    if ADesde > F.Size then
      ADesde := F.Size;
    if (ACuantos < 0) or (ACuantos > F.Size - ADesde) then
      ACuantos := F.Size - ADesde;
    F.Position := ADesde;
    // su codificacion, por EL lector de un BOM: el ancho de una unidad y si
    // va al reves; el BOM no es texto (sin el, un byte: UTF-8 o ANSI)
    SetLength(B, 4);
    N := 4;
    if ACuantos < N then
      N := ACuantos;
    N := F.Read(B[0], N);
    SetLength(B, N);
    Bom := 0;
    if KindDeBom(B, K) then
      Bom := PreambleLen(K)
    else
      K := ekUtf8;
    case K of
      ekUtf16LE: Cuenta.Empieza(2, False);
      ekUtf16BE: Cuenta.Empieza(2, True);
      ekUtf32LE: Cuenta.Empieza(4, False);
      ekUtf32BE: Cuenta.Empieza(4, True);
    else
      Cuenta.Empieza(1, False);
    end;
    F.Position := ADesde + Bom;
    Dec(ACuantos, Bom);
    SetLength(B, TROZO);
    while ACuantos > 0 do
    begin
      N := TROZO;
      if ACuantos < N then
        N := ACuantos;
      N := F.Read(B[0], N);
      if N <= 0 then
        Break;
      Cuenta.Suma(B, N);
      Dec(ACuantos, N);
    end;
    Result := Cuenta.Lineas;
  finally
    F.Free;
  end;
end;

function LeeTexto(const APath: string; ALugares: TLugaresDeTexto): string;
var
  Enc: string;
begin
  Result := LeeTexto(APath, ALugares, Enc);
end;

{ La copia de un fichero del IDE en la casa del servidor ANTES de pisarlo o
  borrarlo (CopiaDelIde); lanza si no se puede: sin copia no se toca. }
function CopiaAntesDePisar(const APath: string): string;
begin
  Result := GuardaCopiaDelIde(APath,
    procedure(ACopia: string)
    begin
      TFile.Copy(APath, ACopia);
    end);
end;

function BorraFichero(const APath: string; ALugar: TLugarDeTexto): string;
var
  Motivo: string;
begin
  Result := '';
  // la jaula borra a SU papelera (delphi_delete), nunca por aqui
  if ALugar = ltJaula then
    raise Exception.Create(MsgFmt(SR_BORRA_JAULA_FMT, [APath]));
  Motivo := LugarDeEscrituraDenegado(APath, ALugar);
  if Motivo <> '' then
    raise Exception.Create(Motivo);
  if ALugar = ltIde then
    Result := CopiaAntesDePisar(APath);
  TFile.Delete(APath);
end;

{ El fichero esta y dice EXACTAMENTE esos bytes (por el lector de su lugar;
  lo que no se puede leer no es igual). }
function MismosBytes(const APath: string; const ABytes: TArray<Byte>;
  ALugar: TLugarDeTexto): Boolean;
begin
  Result := False;
  if not TFile.Exists(APath) then
    Exit;
  try
    Result := BytesIguales(LeeBytes(APath, [ALugar]), ABytes);
  except
    Result := False;
  end;
end;

function EscribeBytes(const APath: string; const ABytes: TArray<Byte>;
  ALugar: TLugarDeTexto): string;
var
  Motivo: string;
begin
  Result := '';
  // la jaula tiene SU escritor, que pregunta lo mismo y apunta lo escrito
  // para la codificacion de origen de la llamada (EncAlEscribir), y SU
  // cerrojo: el de sus otros escritores, de la pregunta al renombre (iba sin
  // el: P4-b de la 1.18.0; reentrante, por si quien llama ya lo tiene)
  if ALugar = ltJaula then
  begin
    EnterFileEdit;
    try
      AtomicWrite(APath, ABytes);
    finally
      LeaveFileEdit;
    end;
    Exit;
  end;
  Motivo := LugarDeEscrituraDenegado(APath, ALugar);
  if Motivo <> '' then
    raise Exception.Create(Motivo);
  // Lo que ya dice ESO no se reescribe ni se copia: la regla de las
  // ediciones (SN_EDIT_SIN_CAMBIOS), aqui para los ficheros que se escriben
  // enteros. Repetir get-sdk escribia el mismo .sdk y dejaba una copia en la
  // casa en CADA llamada (Hermes 13-oct, informe 105226; A4 de la 1.18.4).
  // Y la casa ya tenia su gemela a medias (EscribeEnCasaDelServidor: "si el
  // que esta dice lo mismo, vale"), solo como salida de un fallo
  if MismosBytes(APath, ABytes, ALugar) then
    Exit;
  // en el IDE, lo que se pisa se copia ANTES en la casa; sin copia no se pisa
  if (ALugar = ltIde) and TFile.Exists(APath) then
    Result := CopiaAntesDePisar(APath);
  SustituyePorBytes(APath, ABytes);
end;

function EscribeTexto(const APath, ATexto: string; ALugar: TLugarDeTexto;
  AK: TEncKind; AEstricto: Boolean): string;
begin
  Result := EscribeBytes(APath, EncodeText(ATexto, AK, AEstricto), ALugar);
end;

const
  // absurdo pasar de ahi, pero nunca un bucle sin fin
  MAX_INTENTOS_DOCUMENTO = 500;

function NombreDeDocumento(const ABase: string; AIntento: Integer): string;
begin
  if AIntento > 1 then
    Result := Format('%s-%d.md', [ABase, AIntento])
  else
    Result := ABase + '.md';
end;

{ Reserva el nombre creando el fichero VACIO en exclusiva: si ya existe (o lo
  acaba de crear otro hilo en este mismo instante) devuelve False. CREATE_NEW
  es atomico en el sistema de ficheros. }
function ReservaNombreDeDocumento(const APath: string): Boolean;
var
  H: THandle;
begin
  H := CreateFile(PChar(APath), GENERIC_WRITE, 0, nil, CREATE_NEW,
    FILE_ATTRIBUTE_NORMAL, 0);
  Result := H <> INVALID_HANDLE_VALUE;
  if Result then
    CloseHandle(H);
end;

function EscribeDocumentoNuevo(const ADir, ABase, ATexto: string; out AMotivo: string): string;
var
  I: Integer;
begin
  Result := '';
  AMotivo := LugarDeEscrituraDenegado(TPath.Combine(ADir,
    NombreDeDocumento(ABase, MAX_INTENTOS_DOCUMENTO)), ltCasa);
  if AMotivo <> '' then
    Exit;
  CrearCarpeta(ADir);
  I := 1;
  while not ReservaNombreDeDocumento(TPath.Combine(ADir, NombreDeDocumento(ABase, I))) do
  begin
    Inc(I);
    if I > MAX_INTENTOS_DOCUMENTO then
      Exit;
  end;
  Result := TPath.Combine(ADir, NombreDeDocumento(ABase, I));
  try
    EscribeTexto(Result, ATexto, ltCasa, ekUtf8Bom);
  except
    // la reserva vacia no se queda: un documento sin cuerpo no es de nadie
    try
      BorraFichero(Result, ltCasa);
    except
    end;
    raise;
  end;
end;

function SelloDeDocumento(AMomento: TDateTime): string;
begin
  Result := FormatDateTime('yyyymmdd-hhnnss', AMomento);
end;

procedure EscribeEnCasaDelServidor(const AFichero, ATexto: string);
begin
  // una cache que ya dice eso mismo no se toca: lo decide el escritor
  // (EscribeBytes, para todos los lugares), que antes solo lo miraba aqui y
  // como salida de un fallo. Una cache VIEJA no vale: lo que no se pudo
  // escribir lanza (un disco lleno daba una configuracion antigua sin decir
  // nada; revisor de P3)
  EscribeTexto(AFichero, ATexto, ltCasa, ekUtf8Bom);
end;

function PatchLoadText(const APath: string; out AEncName: string): string;
begin
  // la lectura de la JAULA pregunta ELLA a la jaula (P2 de las puertas): se
  // fiaba de que la tool hubiese comprobado la ruta a la entrada, y algunas
  // no la daba la tool sino el motor o el .dpr (medida M1: la cadena de
  // declaration, la mudanza de delphi_move) o un recorrido que cruzaba una
  // union. Lo de fuera de la jaula se lee por LeeTexto con su lugar
  ExigeLugarDeLectura(APath, [ltJaula]);
  Result := TextoDeFichero(APath, AEncName);
end;

function TextoDeDesigner(const APath: string; out ATexto, AEncName: string): string;
begin
  ATexto := '';
  AEncName := '';
  // la puerta tambien para el binario: su conversor lee el disco a secas
  ExigeLugarDeLectura(APath, [ltJaula]);
  if IsBinaryDesignerFile(APath) then
    Exit(DesignerFileToText(APath, ATexto));
  Result := '';
  ATexto := PatchLoadText(APath, AEncName);
end;

function PatchSaveText(const APath, AText, AEncName: string; AEnsayo: Boolean = False;
  ANuevo: Boolean = False): string;
var
  K: TEncKind;
  B, Antes: TBytes;
  Existe: Boolean;
  TextoAntes: string;
begin
  Result := '';
  K := EncKindOf(AEncName);
  // LA puerta del escritor ANTES de mirar nada: la ida y vuelta leia los bytes
  // de una ruta sin juzgar (un llamador que escribe un fichero que encontro en
  // un .dpr, un UNC) - E/S hacia donde dijera, y EDIT-038 contaba que existia y
  // en que codificacion (revisor de version de la 1.18.0)
  var Puerta := SustitucionDenegada(APath);
  if Puerta <> '' then
    raise Exception.Create(Puerta);
  // ANuevo: el texto es un fichero NUEVO (un create del changeset), y lo que
  // haya en el disco no cuenta: en el ensayo puede seguir ahi hasta que corra
  // el delete anterior del mismo lote, y la ida y vuelta y el origen de ESE
  // fichero negaban o decidian por el viejo (revisor propio de la 4.1)
  Existe := TFile.Exists(APath) and not ANuevo;
  Antes := nil;
  if Existe then
  begin
    Antes := TFile.ReadAllBytes(APath);
    // la regla de ida y vuelta, la de DoEdit, en el otro escritor (David,
    // 9-oct-2026): el disenador, el changeset, el rename, delphi_textedit...
    // lo reescribian con U+FFFD donde habia bytes que su codificacion no
    // guarda. Con su etiqueta, la excepcion es una negativa (DENIED)
    var KAntes: TEncKind;
    var NoVuelve := ReescrituraDenegada(APath, Antes, KAntes);
    if NoVuelve <> '' then
      raise Exception.Create(NoVuelve);
    // lo que sustituye: un sustituto suelto que ya estaba se escribe como
    // estaba (EncodeText; revisor de version de la 1.18.1)
    TextoAntes := DecodeBytes(Antes, KAntes);
  end;
  // el primer caracter no ASCII de un fuente sin codificacion (4.1)
  K := EncAlEscribir(APath, K, Antes, Existe, AText);
  B := EncodeText(AText, K, True, TextoAntes); // lanza ECaracterNoCabe: en el ensayo tambien
  // ...y lo que se escribe tiene que leerse igual (EDIT-122): en el ensayo tambien
  var Cambia := LecturaCambiada(APath, B, K);
  if Cambia <> '' then
    raise Exception.Create(Cambia);
  // ...y un fichero que el IDE carga como XML, juzgado por SU parser antes de
  // escribirlo, en el ensayo tambien. Lo preguntaba PatchSaveConSuSalto, y
  // cinco escritores guardaban sin el: el grupo (add/remove-project), la
  // mudanza que re-apunta un .dproj o un .groupproj, el .dproj de
  // delphi_create y el create de un changeset (revisor Opus de la 1.22.0, H5)
  if EsXmlDelIde(APath) then
  begin
    var Mal := XmlMalFormadoSegunElIde(AText);
    if Mal <> '' then
      raise Exception.Create(MsgFmt(SR_PATCH_XML_MAL_FORMADO_FMT, [TPath.GetFileName(APath), Mal]));
  end;
  if AEnsayo then
  begin
    var Motivo := SustitucionDenegada(APath); // lo que preguntara el escritor
    if Motivo = '' then
      Motivo := RutaLargaDenegada(APath); // ...y su medida (GUARD-028)
    if Motivo <> '' then
      raise Exception.Create(Motivo);
    Exit;
  end;
  if TFile.Exists(APath) then
    Result := BackupFile(APath); // new files have nothing to back up
  AtomicWrite(APath, B);
end;

function XmlMalFormadoSegunElIde(const AXml: string): string;

  // en una rutina APARTE: los temporales de interfaz que deja una expresion
  // (el parseError) se sueltan al salir de la rutina, no de la sentencia, y
  // sueltos despues de CoUninitialize llaman a codigo ya descargado (AV en la
  // suite, medida el 22-oct-2026)
  function Juzga(const ATexto: string): string;
  var
    Doc: IXMLDOMDocument2;
    Error: IXMLDOMParseError;
  begin
    Result := '';
    Doc := CoDOMDocument60.Create;
    Doc.async := False;
    Doc.validateOnParse := False;
    Doc.resolveExternals := False;
    if not Doc.loadXML(ATexto) then
    begin
      Error := Doc.parseError;
      Result := MsgFmt(SF_XML_ERROR_DEL_PARSER_FMT, [Error.line, Trim(string(Error.reason))]);
    end;
  end;

var
  ComPropio: Boolean;
  Texto: string;
begin
  // COM en ESTE hilo, el de la llamada, como Lsp.Chm (S_FALSE = ya estaba,
  // tambien se deshace; RPC_E_CHANGED_MODE = ya estaba en otro modo, no es
  // nuestro)
  ComPropio := Succeeded(CoInitializeEx(nil, COINIT_MULTITHREADED));
  try
    // el BOM, si el texto lo trae, no es XML para un parser que recibe texto
    Texto := AXml;
    if (Texto <> '') and (Texto[1] = #$FEFF) then
      Texto := Texto.Substring(1);
    Result := Juzga(Texto);
  finally
    if ComPropio then
      CoUninitialize;
  end;
end;

procedure PatchSaveConSuSalto(const APath, AText, AEncName: string);
var
  Enc, Texto: string;
begin
  // lo que el escritor no toco, con su salto; lo nuevo, con el del fichero
  // (ReescribeConSusSaltos: la regla de quien cambia lineas)
  Texto := AText;
  if TFile.Exists(APath) then
    Texto := ReescribeConSusSaltos(PatchLoadText(APath, Enc), Texto);
  // (el parser del IDE sobre lo compuesto, la segunda barrera del escaner, lo
  // pregunta el escritor de abajo: PatchSaveText, para todo fichero de XML del IDE)
  PatchSaveText(APath, Texto, AEncName);
end;

initialization
  GLock := TCriticalSection.Create;

finalization
  GLock.Free;

end.
