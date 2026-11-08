unit Lsp.Guard;

{ Access control: the security unit. Four layers, all configured in
  settings.ini next to the exe (env vars take precedence):

  1. Workspace jail - [Workspace] Roots / DELPHI_MCP_ROOTS. With roots
     configured, EVERY tool that touches the disk must stay inside them;
     paths are canonicalized so ..\ tricks and prefix cousins do not escape.
     No roots = unrestricted (local trusted mode).

  2. Credentials - SOLO tokens por workspace ([Workspace.<nombre>] Token= /
     ReadOnlyToken=). Sin coincidencia, 401: no hay anonimo ni modo abierto
     (v0.98). Enforced by the HTTP transport; Lsp.Settings reads and caches them.

  3. Read-only gate - ToolCallDenied is THE single entry gate, consulted by
     the tools dispatcher before ANY tool executes. The read/write
     classification of every tool lives with it, in Lsp.PuertaDeLaLlamada,
     and nowhere else (git, which decides by its arguments, is asked
     through GitCommandIsQuery, in Lsp.Args).

  4. Reference projects - [Workspace.<name>] ReadOnlyRoots (David,
     2026-09-25): folders OUTSIDE Roots that this workspace may READ as if
     they were its own and NEVER write. This is the door through which
     remote agents will see the house's REAL projects as code references,
     so the contract is spelled out:
       - One list, its own (WorkspaceReadOnlyRoots), parsed by the same
         reader as Roots. One locator (ReadOnlyRootOf) answers "is this
         path in a reference?" for the gate, the temp folders and
         delphi_projects. Nobody re-derives it.
       - JaulaDenegada (the READ question) lets a reference through like a
         root: the vault, path anomalies and a junction that leaves the
         reference are still refused, with the same RealPath check the
         roots get (a link planted inside a reference opens nothing).
       - PathDenied (the WRITE question) asks JaulaDenegada first and then
         checks the reference list BEFORE the roots, so a reference WINS:
         a folder declared in both lists, or a root that lies inside a
         reference, is read-only. Until 1.7.3 this was one gate with a
         table of pardons by reason (mvReferencia); since 1.7.4 there is
         no pardon to get right.
       - Every tool that WRITES goes through PathDenied and therefore
         refuses a reference: edit, textedit, create, changeset, move (also
         copy=true, both ends), delete, upload, build, test run, package,
         deploy, remote-run, designer to-text/to-binary, styles build,
         config (everything but view), rename apply, desktop out=.
       - Every tool that READS goes through ReadPathDenied and therefore
         enters: read, list, search, fetch and the /files route, symbols,
         definition, references, hover, signature, completion, diagnostics
         (the LSP config is cached under LOCALAPPDATA, never next to the
         project), designer tree/get/lint/check-binding/layout, config
         view, test discover, rename preview, and the QUERY half of git
         (GitCommandIsQuery - the one classification, shared with the
         read-only credential).
       - Temp files (AgentTempDir) never land in a reference, its drive
         letters are served (srvX:) like the roots', and the [RutaDelServidor]
         floor (ArgPathOutsideDenied, Lsp.PuertaDeLaLlamada) uses the read
         gate, so it lets them in.
       - What it does NOT do: subtract. Everything under a reference root is
         readable, secrets included - point it at clean project folders.
     Measured by tests/test_readonly_roots.py (two servers).

  DONDE ESTA LO QUE ESTABA AQUI (la limpieza de la 1.18.0, 8-oct-2026: de
  8.207 lineas a unas 3.700, todo movido sin cambiar una linea de logica).
  Aqui se queda la jaula: las dos preguntas (JaulaDenegada para leer,
  PathDenied para escribir) y sus envoltorios (ReadPathDenied,
  EscrituraDenegada, WriteTargetDenied), los
  recorredores que no cruzan un enlace (BorraArbol, CopiaArbol, MueveArbol)
  y lo que se hace CON las carpetas de la casa pasando por las puertas (la
  papelera y los desechables). Lo demas, de abajo arriba:
    - Lsp.Rutas: las formas canonicas (LongCanonical, RealPath, FormaLarga,
      EnLugar) y la forma de una ruta (EsUnc, EsPrefijoDeDispositivo,
      EsRutaAbsoluta).
    - Lsp.Json: ReescribeCadenas, el recorrido de los argumentos que
      comparten la jaula y las unidades virtuales.
    - Lsp.Casa: los nombradores de la casa del servidor (ServerDir, la
      temporal, las caches, los nombres unicos, los mutex) y su escritor.
    - Lsp.Settings: el lector de la configuracion y las credenciales, y el
      juez de los hosts que se sondean (ProbeHostDenied).
    - Lsp.Discovery: las macros del IDE (IdeMacroVars).
    - Lsp.Identidad: quien llama y el registro de las sesiones.
    - Lsp.Args: las puertas de git y de los lanzadores y GitCommandIsQuery
      (el troceador TrocearArgs y su inversa EnComillas, desde el 9-oct en
      Lsp.ProcessLaunch, con el lanzador).
    - Lsp.Lugares: el mapa de los lugares declarados y sus formas.
    - Lsp.Mascara: las unidades virtuales srvX:, de ida y de vuelta.
    - Lsp.TodoONada: la foto y el deshacer de todo o nada (va ENCIMA de la
      jaula: usa sus puertas y sus escritores).
    - Lsp.Capturas (6-nov-2026, B6 de la 1.28, como las dos de abajo): las
      capturas que el servidor hace para devolverlas, su nombrador y su
      entrega.
    - Lsp.JuecesDeArgumentos: los jueces de los argumentos que no son rutas
      (el perfil, lo que viaja a paclient, adb, build y paserver).
    - Lsp.PuertaDeLaLlamada: la puerta de entrada (ToolCallDenied), la tabla
      de accesos (la credencial de solo lectura y lo que anuncia tools/list),
      las marcas de los parametros con el suelo de la jaula, y las tools
      ocultas. Va ENCIMA de la jaula: le hace sus preguntas.
    - Lsp.PurgaDelArranque: la purga de la casa al arrancar y la presencia
      de cada instancia (la primera, la unica viva de su casa).
  Lo que "era de Guard" se busca primero en esta lista. }

interface

uses
  System.Classes,
  System.JSON;

const
  { Lo mas larga que Windows abre a este proceso, que no declara longPathAware:
    MAX_PATH (260) menos su NUL. Medido el 8-nov-2026 con LongPathsEnabled=1 en
    la maquina: 259 se lee, 260 contesta "no existe" con el fichero en el disco
    (A24 de la 1.29). Atada a MAX_PATH al compilar (Lsp.Guard). }
  RUTA_MAX_DE_WINDOWS = 259;
  { Lo mas larga que puede ser una ruta que se ESCRIBE: esa menos el sufijo
    temporal del escritor atomico (27). Leer llega hasta RUTA_MAX_DE_WINDOWS. }
  RUTA_ESCRIBIBLE_MAX = RUTA_MAX_DE_WINDOWS - 27;

{ La medida del escritor atomico (GUARD-028): '' si cabe. La preguntan
  WriteTargetDenied (el DESTINO que nombra el agente, antes de crear
  carpetas) y el propio escritor (AtomicWrite y su ensayo). NUNCA en
  PathDenied: alli se perdonaba al leer y abria la jaula a la lectura de
  toda ruta larga, y median tambien las copias de la papelera, que
  TFile.Copy escribe hasta MAX_PATH entero (1.7.2; undecima revision). }
function RutaLargaDenegada(const APath: string): string;

{ El comando efectivo de delphi_test: sin command, "project" (y sin path)
  significa run y lo demas discover. LA regla de la tool, aqui para que la
  puerta de solo lectura la aplique igual: '' + project llegaba al
  constructor y lo paraba el escritor (undecima revision, r11c). }
function ComandoDeTest(const ACmd, AProject, APath: string): string;

{ LA PREGUNTA DE LECTURA: "esta ruta cae dentro de lo que esta sesion puede
  LEER?" - las raices, las referencias (ReadOnlyRoots) y la zona de
  biblioteca (RTL/VCL y componentes registrados, si esta abierta), sin un
  enlace que salga, sin el vault y sin anomalias de nombre. Sin motivos ni
  perdones: lo que aqui se niega no lo perdona nadie, y aqui NO se anade
  nunca una regla de escritura. Hasta la 1.7.3 era "PathDenied menos una
  tabla de perdones por motivo": cada regla nueva tenia que caer en el sitio
  correcto respecto a esa tabla, y el tope de rutas largas de la 1.7.2 cayo
  antes de la jaula con un perdon y abrio la lectura de toda ruta larga
  (undecima revision; David: "dos preguntas, dos helpers"). }
function JaulaDenegada(const APath: string; APermiteGit: Boolean = False): string; overload;

{ '' = allowed; otherwise the rejection message to return to the agent.
  This is the WRITE jail: only the configured workspace roots. }
{ LA PREGUNTA DE ESCRITURA: la jaula (JaulaDenegada) y DESPUES lo que solo
  importa al escribir - una referencia se lee y no se toca, un ReadOnlyPaths
  igual, la zona de biblioteca nunca se escribe, el confinamiento por
  agente. Las reglas de escritura se anaden aqui, y da igual en que orden:
  la jaula ya paso, una regla mal puesta niega de mas y nunca abre. Los
  escritores preguntan por EscrituraDenegada (suma el modo solo lectura) y
  WriteTargetDenied (suma temporales, papelera y la medida del escritor). }
function PathDenied(const APath: string; APermiteGit: Boolean = False): string;

{ La puerta de las tools que LEEN (read/search/list/fetch/LSP): la jaula tal
  cual, mas la pista de la zona de biblioteca en la negativa de fuera. }
function ReadPathDenied(const APath: string; APermiteGit: Boolean = False): string;

{ LA pregunta "existe ARuta?" de quien no la va a escribir: la puerta de
  leer PRIMERO y, solo si esta sesion la lee, si existe (un fichero; con
  ACarpeta, tambien una carpeta). Lo que la jaula no deja leer ni se
  pregunta: contestar distinto segun existiera diria a quien no lo lee si
  esta (medido el 25-oct-2026 en la nota de una mudanza: un $I y una
  propiedad que salian de la raiz se contaban solo si lo de fuera existia;
  la pregunta estaba escrita a mano en seis sitios, en dos con la puerta). }
function ExisteYSeLee(const ARuta: string; ACarpeta: Boolean = False): Boolean;

{ LA causa de un rename o un movimiento que Windows nego con ACodigo, con el
  NOMBRE de lo que no se movio, por la regla de todas (MotivoDelSistema:
  ocupado SYS-027, acceso denegado SYS-028); otro codigo, con el texto de
  Windows. Se decia "otro proceso lo tiene" de CUALQUIER codigo (septima
  revision). Era de Lsp.Patch; el move y la mezcla lanzaban RaiseLastOSError
  y el SYS-027 de un comodin no decia cual estaba cogido (25-oct-2026). }
function MotivoDeRenombre(const APath: string; ACodigo: Cardinal): string;

{ MoveFileEx que aguanta a un lector de un instante (el preview de un changeset,
  una busqueda, el antivirus): un fichero -o uno DENTRO de una carpeta- que otro
  tiene abierto hace rebotar el renombre con 5, 32 o 33, y unos instantes
  despues pasa. Medido el 31-oct-2026: una carpeta con un fichero abierto dentro
  da 5 aunque el otro comparta lectura, escritura y borrado; un destino que ya
  existe da 183, y ese no se reintenta. True si renombro; si no, ACodigo trae el
  de Windows del ultimo intento. Era el bucle de SustituyePorRenombre (cuatro
  EDIT-106 de la tercera ronda, todos del propio servidor: reintentar
  funcionaba); la caja de paquetes del render, que renombra una carpeta recien
  llena de copias, es el segundo sitio (test_http_auth 2ab, una vez, con el IDE
  arrancando). }
function RenombraConReintentos(const AOrigen, ADestino: string; AFlags: Cardinal;
  out ACodigo: Cardinal): Boolean;

{ LA de quitar una carpeta VACIA (RemoveDirectory: con algo dentro no se va, y
  de un enlace quita el enlace, nunca lo de detras), con LA politica de
  reintentos (ConReintentos): un lector de un instante - el indexador, un
  antivirus, un clone que acaba de soltarla - la hace rebotar con 32 y se
  quedaba (V45 de la 1.27, medido). Estaba asi en un sitio y a pelo en seis
  (C30 de la 1.28: el borrado de una carpeta vacia de delphi_delete contestaba
  que no se dejaba, la mezcla y el borrador de arboles lanzaban). True si la
  quito; si no, ACodigo trae el de Windows del ultimo intento. Solo sobre una
  ruta que la puerta acaba de aprobar. }
function QuitaCarpetaConReintentos(const ACarpeta: string; out ACodigo: Cardinal): Boolean;

{ La pregunta de la puerta de leer sobre los OTROS nombres de un fichero (un
  enlace duro: GUARD-041/042), para quien lee sus BYTES por su cuenta - las
  copias de la papelera, la de un move, la de una carpeta -. ReadPathDenied
  la hace al final. '' si no es un enlace duro, si todos sus nombres se leen
  o si no hay jaula. }
function EnlaceDuroIlegible(const APath: string): string;

{ Para quien escribe DENTRO del fichero en vez de poner uno nuevo con un
  renombre (AtomicWrite): con mas de un nombre los bytes cambian bajo todos,
  y alguno puede estar fuera de las raices (GUARD-043). Solo delphi_upload
  escribe asi: sus trozos se anaden al mismo fichero. '' si tiene un nombre
  o si no hay jaula. }
function EscrituraEnElFicheroDenegada(const APath: string): string;

{ La raiz de referencia que contiene APath ('' = ninguna). EL sitio que sabe
  si una ruta es de referencia: lo usan la guarda, los temporales y
  delphi_projects. }
function ReadOnlyRootOf(const APath: string): string;


{ Por que el servidor no llega AHORA a una raiz o referencia del workspace,
  sin salir a la red: '' si llega - o si saberlo pediria salir -; si no, el
  motivo. Dos casos: su LETRA no esta conectada en este proceso (la tabla de
  unidades, ClaseDeLetra de Lsp.NetDrives) o, en una unidad LOCAL, su carpeta
  no existe. En una letra de red conectada no se mira la carpeta: un recurso
  que no contesta tarda lo que Windows quiera. Lo listan delphi_workspace y
  delphi_projects (Hermes, 5-oct-2026: una referencia en una letra sin montar
  salia listada como si estuviera). }
function MotivoRaizNoDisponible(const ARaiz: string): string;

{ Las de ASitios a las que el servidor no llega AHORA, cada una una vez y sin
  su barra final, con su motivo (MotivoRaizNoDisponible); las que estan no
  salen. Lo que recorria a mano delphi_workspace (unavailableRoots), y lo que
  dicen las notas de arranque (David, 10-oct-2026: una raiz que no existia y
  el arranque no lo dijo). }
type
  TRaizNoDisponible = record
    Raiz, Motivo: string;
  end;
function RaicesNoDisponibles(const ASitios: TArray<string>): TArray<TRaizNoDisponible>;

{ La negativa de una ruta que cae en una raiz o referencia cuya LETRA no esta
  conectada en este proceso (WS-022); '' si no es el caso. Sin disco ni red:
  va en la puerta de cada llamada (ArgPathOutsideDenied). }
function RaizEnLetraNoConectada(const APath: string): string;

{ La negativa de una ruta mas larga de lo que Windows abre a este proceso
  (RUTA_MAX_DE_WINDOWS); '' si cabe. Ninguna tool la lee ni la escribe, y cada
  una decia "no existe" con el fichero alli (A24 de la 1.29): va en la puerta de
  cada llamada (ArgPathOutsideDenied), sobre lo que nombra el agente. }
function RutaQueWindowsNoAbre(const APath: string): string;

{ TRES CLASES DE ESCRITURA, y lo que las separa es QUIEN COMPONE LA RUTA
  (David, 28-sep-2026):
  1. LA CASA DEL SERVIDOR (ServerDir: reports, el buzon, los logs, los jobs
     de remote-run, el mensaje de un commit, node.ver, las capturas que
     devolvemos) y las otras casas que
     no son del workspace (los perfiles y las fichas de SDK del IDE, las
     caches de %LOCALAPPDATA%, el vault con su propia puerta VaultWritable).
     La ruta la compone el servidor con su nombrador y el agente nunca la
     nombra: lo que aporta (un titulo, un nombre de agente o de perfil, el
     nombre de un proyecto para su cache) pasa por Slug, una regex o queda
     acotado a UN tramo sin separadores. A la puerta de escritura NO se le
     pregunta: responde "puede ESTA SESION escribir aqui?", y la casa no es
     de la sesion ni del workspace. El unico lector de "es la casa?" es el
     de las capturas (EnCasaDeEntregables), porque una se ENTREGA y se
     CONSUME a peticion: hay que saber que es nuestra.
  2. LO QUE NOMBRA EL AGENTE, y lo que el servidor deriva de ello (el .dproj
     de la unit, los gemelos, la copia recuperable): la puerta a la entrada
     (PathDenied y sus dos sumas, WriteTargetDenied y EscrituraDenegada).
     Los escritores atomicos vuelven a preguntar por su cuenta (AtomicWrite,
     BackupFile); un primitivo crudo corre solo sobre la ruta que la puerta
     acaba de aprobar.
  3. LA PAPELERA y las marcas de dueno, lo unico nuestro DENTRO del
     workspace: es del agente (restaura desde ella) y pasan por la puerta
     del escritor como cualquier escritura (una referencia no recibe
     papelera). Las CAPTURAS que hacemos para devolverlas fueron de esta
     clase hasta la 1.18.2 (el __delphi-temp de la primera raiz escribible)
     y son de la 1: viven en la casa del servidor (Lsp.Casa.CasaDeCapturas)
     y las juzga su nombrador al escribirlas, entregarlas y consumirlas.
  El error a no repetir: un solo if que mezcle la pregunta del agente (la
  puerta) con la del servidor (su nombrador). Cada pregunta, a su lector:
  lo que el agente INTENTA pasa los filtros; lo que el servidor hace para
  servirlo, no (David, 12-oct-2026). }

{ Borra un arbol entero SIN CRUZAR ENLACES: un junction/symlink que haya
  dentro se elimina como ENTRADA (cae el enlace, jamas su destino). El
  TDirectory.Delete recursivo de la RTL entra en cualquier cosa con el bit
  de directorio sin mirar el de reparse (System.IOUtils,
  WalkThroughDirectory) y borra los ficheros DEL DESTINO: un junction
  plantado en la jaula apuntando fuera convertia cualquier borrado
  recursivo en un borrado FUERA de la jaula (auditoria 2026-09-21). Habia
  SEIS borrados recursivos sueltos por el codigo; este es ahora el unico,
  y quien necesite tirar un arbol pasa por aqui. Limpia atributos
  (solo-lectura) como hacia la RTL - los objetos de un .git vienen asi.
  Lanza si no puede: que cada llamador decida si tragarselo.

  Y desde el 25-sep-2026 LANZA TAMBIEN SI NO DEBE: antes de tocar nada pasa
  por BorradoDenegado (abajo). No hay otra forma de borrar un arbol. }
procedure BorraArbol(const ADir: string);

{ Reclama, SOLO dentro de la casa del servidor (ServerTempDir, su nombrador),
  cada carpeta de ADir que esta sesion no puede LISTAR: le da -como UN objeto y
  SIN propagar- una DACL protegida con UNA sola ACE para el dueno (el servidor),
  con SetFileSecurity, para recuperar el acceso. Nunca cruza un enlace: el
  recorredor no entra en uno y el reclamo no recorre el arbol (SetNamedSecurityInfo
  si lo haria, y su recorrido podria tocar lo de detras de uno). Para el barrido de la casa cuando un test
  dejo una carpeta nacida cerrada (V9): despues, BorraArbol la borra. Lo que ni
  asi se reclama (un ACE OWNER_RIGHTS que le quita el WRITE_DAC al dueno) se
  queda y BorraArbol lo dice, como hoy. Fuera de la casa no hace nada. }
procedure ReclamaArbol(const ADir: string);

{ Tira las carpetas de dia caducadas (RETENTION_DAYS) de UNA papelera. Coste
  medido cuando no hay nada que tirar, que es casi siempre: 0,012 ms - leer
  una carpeta de tres entradas y comparar nombres. Nunca lanza.

  Se exporta porque la purga solo salia de BackupFile: una carpeta que se
  deja de EDITAR conservaba sus copias para siempre (lo vio David). Recorrer
  las raices al arrancar se midio y se descarto - 5,9 s en un arbol de 8.869
  carpetas, y una jaula puede ser un disco entero -; un hilo que lo haga
  cada hora tampoco hace falta: el recorredor de delphi_list / search /
  projects YA pasa por delante de cada papelera, asi que purga al pasar
  (PurgaAlPasar). Trabajo proporcional a la actividad, cero recorridos
  nuevos. Llega de Lsp.Patch el 9-oct-2026 (2.1f de la 1.18.0) con
  PurgaAlPasar: las dos usan la jaula (PathDenied, BorraArbol) y la jaula
  las usa a ellas, asi que viven con ella y Lsp.Guard ya no usa Lsp.Patch. }
procedure PurgeOldBackups(const ADir: string);

{ La purga oportunista, con sus dos frenos: una credencial de solo lectura
  no borra nada (un listado no tiene efectos), y PathDenied decide si esa
  papelera es NUESTRA para escribir - lo que deja fuera las ReadOnlyPaths,
  el subarbol confinado de otro agente y, sobre todo, una "papelera" que
  sea un junction hacia fuera de la jaula. }
procedure PurgaAlPasar(const ATrashDir: string);

{ LAS carpetas desechables del servidor, por nombre de segmento: lo UNICO
  dentro de lo que BorraArbol borra (hoy la temporal y la papelera). Una
  lista: si manana nace otra (una cache, un spool), se anade AQUI y el guard
  la conoce, sin tocar la logica (David, 25-sep-2026). Todas empiezan por
  __: es la tercera barrera de BorradoDenegado. }
function CarpetasDesechables: TArray<string>;
{ ANombre (el de UNA entrada, sin su carpeta) es el de una de ellas, como NTFS
  compara dos nombres (RutaEnLista). La copia de delphi_test lo preguntaba con
  MatchText, que pliega con el locale: '__delphi' + U+FE63 + 'temp', otra
  carpeta para NTFS, se quedaba sin copiar (medido; forma 9 de la 1.26). }
function EsCarpetaDesechable(const ANombre: string): Boolean;


{ LOS sitios que un borrado o una mudanza nunca pueden SER ni CONTENER: toda
  raiz de workspace (de escritura y de referencia, de cualquier workspace, y
  las del modo local) y sus carpetas de solo lectura (ReadOnlyPaths), el
  vault, la carpeta del servidor, Windows, Archivos de programa y la carpeta
  del usuario. Una lista: un sitio sagrado nuevo se anade AQUI. }
function LugaresProtegidos: TArray<string>;

{ La decision de BorraArbol, sola: '' = ADir se puede borrar entero; si no,
  el motivo. (1) LISTA BLANCA: tiene que estar DENTRO de una carpeta
  desechable (nunca la carpeta misma) o ser/estar en una carpeta de
  descarga. (2) LISTA NEGRA: no puede ser ni contener un lugar protegido, ni
  ser una unidad o un recurso compartido entero. Se evalua sobre la ruta
  REAL del padre + el nombre: un junction en el camino no hace pasar por
  temporal lo que no lo es, y quitar un enlace (que nunca toca lo de detras)
  se juzga por donde esta el enlace. Un repositorio ENTERO se borra como se
  mueve (el arbol con su .git, sin que sus enlaces salgan de la jaula); lo que
  se BORRA nunca es un .git ni un camino por dentro de el. }
function BorradoDenegado(const ADir: string): string;

{ Vacia una carpeta DESECHABLE (temporal o papelera: CarpetasDesechables) sin
  borrarla, por el borrador con guard. Nunca una que sea un enlace (seria
  vaciar lo de detras) ni una de otro nombre. Nunca lanza. EL vaciador: la
  purga del arranque y la copia de carpetas (que no se lleva la papelera del
  origen) pasan por aqui (25-sep-2026). Su corte por horas (1.9.0) era de la
  purga de una raiz de red, y se fue con ella (V31 de la 1.23). }
procedure VaciaDesechable(const ADir: string);

type
  { Lo que el copiador NO copia, lo dice quien llama: True = fuera (un
    fichero o una carpeta, por su ruta de origen). Se pregunta LO ULTIMO,
    por lo que se va a copiar de verdad (la regla de enlaces ya ha dicho
    que si): quien cuenta lo copiado lo cuenta aqui, y puede lanzar para
    cortar la copia entera - un tope de tamano. }
  TOmiteAlCopiar = reference to function(const APath: string): Boolean;
  { Lo que el copiador COPIARIA, sin escribir nada (AAlListar de CopiaArbol):
    cada entrada con su destino, por las MISMAS reglas (enlaces, papelera,
    vault, AOmite, bucles); ADetrasDeEnlace = se llega a ella por un enlace
    que la copia sigue. Para una carpeta, False = no bajar. Lo usa quien mira
    ANTES de copiar (la copia de un repo, V19): un recorredor, no dos. }
  TListaCopia = reference to function(const AOrigen, ADestino: string;
    AEsCarpeta, ADetrasDeEnlace: Boolean): Boolean;

{ EL copiador de arboles: copia AOrigen en ADestino SIN FUGAS DE LECTURA. Un
  enlace (junction o symlink, de carpeta o de fichero) se sigue SOLO si su
  destino real pasa la puerta de lectura de la sesion (ReadPathDenied): sus
  raices, sus ReadOnlyRoots, la zona de biblioteca. Si no, no se copia y va
  a ANoSeguidos. TDirectory.Copy de la RTL seguia cualquier junction: uno
  plantado en una carpeta (un git clone con enlaces lo mete sin consola)
  copiaba DENTRO de la jaula lo que la jaula no deja leer (25-sep-2026;
  David: 'solo se puede escribir en tu workspace, incluye copiar', y leer
  fuera es lo que el operador declara, 'ReadOnlyRoots es para eso').
  Una papelera (__delphi-patch) de dentro no se copia nunca: no es contenido,
  y la de seguridad de un move la duplicaba (viaja con la carpeta en el
  renombre; V21). AConservaAtributos: la copia de seguridad de un move los
  conserva; la del agente (copy=true) va sin el +R heredado. Un bucle de
  enlaces se corta por la ruta real ya visitada. Lanza si
  no puede copiar. ASigueEnlaces=False: un enlace de DENTRO no se sigue (va
  a ANoSeguidos): la copia de seguridad de un move, que los lleva como
  enlaces; una junction a la raiz dentro de la carpeta metia la copia en su
  propia papelera y el move fallaba (novena revision). AOmite (opcional):
  lo que quien llama deja fuera - delphi_test no se lleva los .dcu a la
  carpeta de su contenedor. AAlListar (opcional): no escribe NADA, dice lo
  que copiaria (TListaCopia). Un parametro del copiador, no otro copiador. }
procedure CopiaArbol(const AOrigen, ADestino: string; AConservaAtributos: Boolean;
  out ANoSeguidos: TArray<string>; ASigueEnlaces: Boolean = True;
  const AOmite: TOmiteAlCopiar = nil; const AAlListar: TListaCopia = nil);

{ La decision de copy=true, sola: '' = se puede copiar AOrigen en ADestino.
  No, si ADestino cae DENTRO de AOrigen (se copiaria sin fin), si AOrigen es
  metadato de git, ni si un repo de dentro tiene su git FUERA de lo que se
  copia (GitDeLaCopiaDenegado). Un proyecto se copia como cualquier carpeta
  (V19 de la 1.23; David, 17-oct-2026: "copiar, mover, borrar carpetas y su
  contenido o ficheros, punto, como haria el operador"; era MOVE-004, "un
  proyecto nunca vive en dos sitios", del flujo de promocion). Y ADestino no
  puede SER ni CONTENER un lugar protegido (ProtegidoDenegado con
  AComoDestino): lo copiado llega alli entero (1.18.2, 2r). }
function CopiaDenegada(const AOrigen, ADestino: string): string;

{ P es un enlace (junction o symlink, de carpeta o de fichero; un marcador de
  OneDrive no lo es). LA comprobacion, la de Lsp.Reparse: estaba escrita cuatro
  veces en esta unidad. }
function EsEnlace(const P: string): Boolean;
{ APath ES ALugar o esta DENTRO por su forma larga, y NINGUN tramo entre
  ALugar (sin el) y APath es un enlace: lo de detras de un enlace no es de
  ese lugar. Para un lugar cuya ruta REAL no sirve para compararlo: la casa
  del servidor bajo LOCALAPPDATA, que la virtualizacion MSIX parte en dos -
  una subcarpeta NUEVA de una carpeta real resuelve a ...\Packages\<app>\
  LocalCache\Local\... (medido el 4 y el 9-oct-2026 desde la app de
  escritorio) -, y eso no es un punto de reparse; una union si. No abre
  nada: atributos. }
function EnLugarSinEnlaces(const APath, ALugar: string): Boolean;
{ La ruta de un enlace se juzga por DONDE ESTA: la ruta REAL del padre + el
  nombre. Para quien tiene que saber donde esta DE VERDAD lo que le nombran
  (la purga de la papelera: un fichero nombrado a traves de un enlace que
  esta en la papelera es el vivo de detras). }
function RutaDelEnlace(const AFull: string): string;

type
  TVisitaRuta = reference to procedure(const APath: string);

{ Visita cada fichero y carpeta DEBAJO de ADir (no ADir) sin cruzar NUNCA un
  enlace: un enlace ni se visita ni se entra - tocarlo seria tocar lo de
  detras (SetFileSecurity sobre un junction etiqueta su destino). EL
  recorrido de quien tiene que tocar cada entrada de un arbol y no es borrar
  ni copiar (esos son BorraArbol y CopiaArbol): el etiquetado de integridad
  de delphi_test cruzaba un junction con soAllDirectories y bajaba la
  etiqueta de un fichero de FUERA de la jaula (medido en vivo, 25-sep-2026).
  Una rama ilegible se salta; con AFallaSiIlegible, lanza (GUARD-040: lo
  que no se puede revisar no se da por revisado).

  AAlEnlace (opcional) recibe cada enlace que se encuentra, sin entrar
  en el: para quien necesita SABER que hay uno antes de hacer algo que
  si lo cruzaria (quitar un worktree: git lo atraviesa, medido el
  26-sep-2026). Un parametro del recorredor, no otro recorredor.

  AAlIlegible (opcional): ante una carpeta que no se deja listar, se llama con
  ella y se reintenta el listado UNA vez - para quien, en SU casa, puede
  reclamarla antes de seguir (ReclamaArbol, V9). Sin el, nada cambia: se salta
  o lanza segun AFallaSiIlegible. }
procedure RecorreSinEnlaces(const ADir: string; const AVisita: TVisitaRuta;
  const AAlEnlace: TVisitaRuta = nil; const AOmite: TOmiteAlCopiar = nil;
  AFallaSiIlegible: Boolean = False; const AAlIlegible: TVisitaRuta = nil);

{ LAS entradas de una carpeta (un nivel), o la negativa si Windows no deja
  listarla (GUARD-040, lanzada). TDirectory.GetFileSystemEntries devuelve
  VACIO cuando FindFirst falla (System.IOUtils, WalkThroughDirectory): una
  carpeta sin permiso de listar parecia vacia, la puerta de los metadatos la
  pasaba sin mirar, la copia la copiaba vacia contestando COPIED y la purga
  borraba a medias (2g de la 1.18.x, medido el 14-oct). El juez es Windows:
  el error de FindFirstFile. }
function EntradasDeCarpeta(const ADir: string): TArray<string>;
{ La carpeta existe y no tiene nada. False si no se deja listar: lo que no
  se sabe vacio no se trata como vacio. }
function CarpetaVacia(const ADir: string): Boolean;

{ LA regla de enlaces de quien RECORRE un arbol: se sigue solo si lo de
  detras se puede LEER en esta sesion. La usan el copiador, la decision de
  la copia y el recorredor de ficheros (delphi_search, delphi_list,
  delphi_projects, el zip de delphi_package): lo que se ensena, se busca o
  se empaqueta es lo que se podia leer. }
function EnlaceLegible(const P: string): Boolean;

{ EL enlace del arbol de ADir que esta sesion no puede seguir, o '' si no
  hay ninguno: para LEER, uno cuyo destino no pasa la puerta de lectura
  (EnlaceLegible, la regla de arriba); con AEscribe, uno cuyo destino REAL
  no pasa la puerta del escritor (EscrituraDenegada). Mira a cualquier
  profundidad y tambien DETRAS de cada enlace admitido -un enlace a una
  carpeta de las raices que a su vez tiene uno hacia fuera-, con los ciclos
  cortados por la ruta real; una carpeta que no se deja listar lanza
  (GUARD-040: lo que no se revisa no se da por revisado). AOmite salta lo
  que no es del arbol (los metadatos de git). Para quien va a dejar que
  OTRO programa recorra o reescriba el arbol entero: git atraviesa un
  junction como una carpeta -add mete lo de detras en el indice; switch,
  merge, pull y stash lo reescriben o lo borran- y la puerta del repo solo
  mira sus tres carpetas (medido el 14-oct-2026 contra la 1.18.3+, revision
  A del cierre de la 1.19.0). }
function EnlaceAjenoEn(const ADir: string; AEscribe: Boolean;
  const AOmite: TOmiteAlCopiar = nil): string;

{ Recorrido de lectura compartido: solo enlaces legibles, ciclos cortados y
  carpetas ilegibles toleradas. Las tools deciden sus filtros de artefactos
  (el de un arbol de codigo es WalkBajoLaRaiz, Lsp.References).
  AAlEntrar, si va: cada carpeta del paseo, al ENTRAR en ella y antes de
  listarla (quien sella lo que vio - el proyecto de una unidad, FindDproj -
  sella antes de mirar: lo que cambie despues mueve el sello).
  AOmite, si va: una carpeta de debajo por la que diga True no se recorre (ni
  se lista ni se entra en ella, ni se sella); una papelera se purga al pasar
  igual. Un parametro del recorredor, como el de CopiaArbol. }
function WalkFiles(const ADir: string; const AMasks: TArray<string>;
  AConPapelera: Boolean = False; ARecursivo: Boolean = True;
  const AAlEntrar: TVisitaRuta = nil;
  AIncluyeEnlacesFuera: Boolean = False;
  const AOmite: TOmiteAlCopiar = nil): TArray<string>; overload;
function WalkFiles(const ADir, AMask: string;
  AConPapelera: Boolean = False): TArray<string>; overload;

{ EL mudador de carpetas: AOrigen pasa a ser ADestino RENOMBRANDOLA (MoveFile
  en la misma unidad) o NADA. No abre la carpeta ni toca sus ficheros: un
  junction de dentro viaja como enlace y lo de detras ni se mira; si algo
  de dentro esta abierto, falla entera y la carpeta sigue intacta. Lo que
  hacia TDirectory.Move de la RTL cuando no podia renombrar - copiar y
  borrar fichero a fichero ENTRANDO en los junctions - se trajo a la jaula
  y BORRO de su sitio el contenido de una carpeta de fuera (reproducido en
  vivo el 25-sep-2026, presente desde v0.16). Antes de tocar nada pasa por
  MovidoDenegado. No hay otra forma de mover un arbol: delphi_move y la
  papelera de delphi_delete pasan por aqui. Lanza si no debe o no puede. }
procedure MueveArbol(const AOrigen, ADestino: string);

type
  { Un paso hecho de una mezcla (MezclaArbol): De se renombro a A o, con A
    vacio, la carpeta De se quito. Para deshacerla al reves. }
  TPasoDeMezcla = record
    De, A: string;
  end;

{ EL mezclador: mete el contenido de AOrigen en la carpeta ADestino, que YA
  existe, entrada a entrada (V19 de la 1.23; David, 25-oct-2026: "carpeta
  vacia o no da igual; lo que no queremos es sobrescribir ficheros"). Un
  fichero o un enlace se renombra (el enlace viaja como enlace: MoveFile
  renombra la entrada y lo de detras ni se mira); una carpeta, entera si en el
  destino no esta y mezclada si esta; AOrigen, vacia al final, se quita. Quien
  llama ya miro que ningun fichero se pisa (MoveFile sin reemplazar falla
  igual si alguno aparece entre medias). Antes de tocar nada, MovidoDenegado,
  como MueveArbol. Cada paso hecho va a AHechos; lanza al primer fallo, y
  quien llama deshace (DeshazMezcla). }
procedure MezclaArbol(const AOrigen, ADestino: string; var AHechos: TArray<TPasoDeMezcla>);

{ Deshace una mezcla al reves (las carpetas quitadas vuelven, cada entrada a su
  sitio). '' si todo volvio; si no, lo que no, una linea por entrada. }
function DeshazMezcla(const AHechos: TArray<TPasoDeMezcla>): string;

const
  { Lo que se deja LIBRE en el disco al copiar o al mover (con su copia de
    seguridad): una POLITICA con nombre, sin juez (David, 17-oct-2026:
    "comprobar si tenemos espacio suficiente y con margen"), para no llenar el
    disco de todos: el servicio, msbuild, el IDE; el NAS es compartido. }
  MARGEN_DISCO_LIBRE = Int64(512) * 1024 * 1024;

{ Si ABytes caben en el disco de ACarpeta (o de su primer ancestro que existe)
  dejando MARGEN_DISCO_LIBRE, lo que Windows da como libre PARA ESTA CUENTA
  (GetDiskFreeSpaceEx: con cuotas y recursos de red). '' si caben o si Windows
  no lo dice (lo dira la escritura); si no, GUARD-044. }
function EspacioDenegado(const ACarpeta: string; ABytes: Int64): string;

{ Lo que ESTE SERVIDOR tiene abierto bajo una carpeta se suelta antes de
  mudarla. El mudador no sabe quien lo tiene. Hoy, los motores DelphiLSP, uno
  por proyecto: al cargar la configuracion del proyecto el motor cambia SU
  directorio de trabajo a la carpeta del proyecto, y Windows no deja renombrar
  ni borrar el directorio de trabajo de un proceso vivo (medido con el motor
  lanzado a mano: libre tras initialize, retenida tras
  workspace/didChangeConfiguration). Quien tenga algo se
  apunta aqui con su soltador y los DOS que quitan una carpeta de su sitio
  (MueveArbol y BorraArbol) los llaman a todos, pasado el guard y antes de
  tocar nada. Medido el 29-sep-2026 (Hermes, en campo): tras UN hover, borrar
  la carpeta del proyecto daba FILE-036 y moverla SYS-027, y el agente no
  tenia como cerrar un proceso que era nuestro; la purga y git worktree
  remove eran peores: el contenido se iba y quedaba el cascaron. Un soltador
  nunca lanza: lo que no se suelte deja fallar la operacion como antes. Se
  apunta al arrancar (initialization), nunca con peticiones en marcha.

  Son DOS avisos, y van en pareja: "se va a quitar" (AEmpieza) y "ya esta".
  Entre uno y otro la carpeta esta SALIENDO y quien tenia algo no vuelve a
  cogerlo: soltar y quitar no era una sola cosa, y un motor que arrancaba en
  medio (el primer hover de otro agente) volvia a retener la carpeta. El
  segundo aviso va SIEMPRE, en un finally: sin el, la carpeta se quedaria
  saliendo. }
type
  TSoltadorDeCarpeta = procedure(const ACarpeta: string; AEmpieza: Boolean);

procedure RegistraSoltadorDeCarpeta(ASoltador: TSoltadorDeCarpeta);

{ Los dos avisos. MueveArbol y BorraArbol los dan solos; estan en la
  interface para quien quita una carpeta por OTRO camino que los del guard
  (la rama de carpeta vacia de delphi_delete; git, que borra el mismo).
  Nunca lanzan. }
procedure SueltaLoNuestroBajo(const ACarpeta: string);
procedure YaNoSeQuita(const ACarpeta: string);

{ ADestino cae DENTRO de AOrigen (o es el), por las rutas REALES (la nota
  larga, en la implementacion). En la interface desde el 29-sep-2026: la
  sesion LSP pregunta con ella que clientes viven bajo la carpeta que se va a
  mudar. UN lector de "esto cae dentro de aquello": no se escribe otro. Lanza
  si una ruta no se puede resolver. }
function DentroDeSiMismo(const AOrigen, ADestino: string;
  AOrigenEsElEnlace: Boolean = False): Boolean;

{ ADestino es AOrigen MISMO con otra grafia (otras mayusculas): la misma
  entrada del disco, mirada donde ESTA cada una (un enlace, el enlace). Un move
  a ella es un RENOMBRADO de las mayusculas, que Windows hace de un golpe, y no
  "dentro de si mismo" (MOVE-009) ni algo que ya esta (FILE-025, la mezcla):
  medido el 25-oct-2026, r1222ce lo negaba con FILE-025 y V19 con MOVE-009
  (punto 4 de Fable). Nunca lanza: lo que no se resuelve no es la misma. }
function MismaEntrada(const AOrigen, ADestino: string): Boolean;

{ Las dos mitades de DentroDeSiMismo, para quien tiene que comparar con un
  cerrojo cogido: RutaParaComparar RESUELVE (pregunta al disco; con
  AEsElEnlace, la ruta por donde ESTA y no por adonde apunta) y CaeDentro
  COMPARA dos rutas ya resueltas: texto, y nada mas. DentroDeSiMismo es las
  dos seguidas: sigue habiendo UN lector. }
function RutaParaComparar(const ARuta: string; AEsElEnlace: Boolean = False): string;
function CaeDentro(const AOrigenResuelto, ADestinoResuelto: string): Boolean;

{ La decision de MueveArbol, sola: '' = se puede. Las dos rutas pasan la
  puerta de escritura (PathDenied), el origen ni ES ni CONTIENE un lugar
  protegido (ProtegidoDenegado), el destino tampoco (lo de dentro llega
  alli: ProtegidoDenegado con AComoDestino) y las dos estan en la misma unidad: entre
  unidades no hay renombrado, y copiar y borrar es justo lo prohibido.
  Quien quiera rechazar ANTES de preparar nada (la copia de seguridad de
  delphi_move) la llama primero; MueveArbol la repite igualmente. }
function MovidoDenegado(const AOrigen, ADestino: string): string;

{ '' salvo que la carpeta ADir SEA o CONTENGA un lugar protegido
  (LugaresProtegidos). PathDenied mira la ruta que le pasan, y mover o
  tirar a la papelera una carpeta se lleva TODO lo de dentro: un proyecto
  de referencia declarado DENTRO de una raiz de escritura, o la raiz de
  otro workspace, se iban con su padre (David, 25-sep-2026: 'ese agujero
  es grave'). El lugar se NOMBRA solo si la sesion ya lo puede leer: la
  raiz de otro workspace, el vault o la carpeta del servidor no se
  revelan, se dice un sitio protegido.

  Con AComoDestino, ADir es adonde VA una carpeta (mover o copiar), y la
  misma pregunta vale al reves: lo que lleva dentro llega alli sin que
  nadie pregunte por ello, y una entrada de ReadOnlyPaths que nombre lo que
  llegaria se escribia (1.18.2, 2r: el segundo emisor del gemelo .dfm). Que
  el destino ESTE dentro de un lugar protegido ya lo dice la puerta de
  escritura; esto es que lo CONTENGA. Solo cambia el mensaje (MOVE-020). }
function ProtegidoDenegado(const ADir: string; AComoDestino: Boolean = False): string;

{ El lugar protegido que hay DENTRO de ADir, sin contar ADir mismo, ya
  nombrado como lo nombra ProtegidoDenegado (solo si la sesion lo puede
  leer); '' si ninguno. Sin recorrer el arbol: compara con la lista de los
  lugares (LugarProtegidoEn) y no busca .git. La pregunta "hay algo que
  proteger aqui dentro?" de quien reescribe un arbol entero sin decir que
  ficheros: el juez de delphi_git (GitReescribeProtegido, 2x de la 1.18.2). }
function ProtegidoDentroDe(const ADir: string): string;

{ LA pregunta de todo escritor: '' = esta sesion puede escribir APath;
  si no, el motivo. Es la puerta de escritura (PathDenied, sobre la ruta
  REAL) mas el modo de solo lectura. La hacen los ESCRITORES mismos
  (AtomicWrite, BackupFile), no solo quien los llama: renombrar una unit
  reescribia cada fichero que listaba el .dpr, y el .dpr puede listar
  uno de fuera o de una referencia (medido en vivo contra 1.3.1,
  25-sep-2026). Un llamador que se olvide de preguntar ya no abre
  nada: el escritor lanza. }
function EscrituraDenegada(const APath: string): string;

{ EL programa que el servidor lanza por su NOMBRE: su ruta completa en las
  carpetas de APath (ProgramaEnPath: el PATH de un entorno, nunca la carpeta
  actual ni la del exe) Y en una carpeta donde esta sesion NO escribe (la
  puerta del escritor sobre su carpeta: fuera de las raices, una referencia,
  un sitio de solo lectura) ni otro agente (la raiz de otro workspace: C31 de
  la 1.28). '' si no esta, o si esta donde el agente
  escribe: un git.exe o un msbuild.exe que el agente pueda dejar en una
  carpeta del PATH es el suyo, no el del operador (la regla del 13-oct: el
  programa por su ruta, encontrada donde el agente no escribe; B1 del cierre
  de la 1.19.0). Lo llaman delphi_git (RutaDeGit) y el build (msbuild). }
function ProgramaDelOperador(const APrograma, APath: string): string;
{ ...y la mitad de esa pregunta para un programa tomado de una RUTA escrita (el
  SDKAdbPath de un .sdk, el paclient de la instalacion o de
  DELPHI_MCP_PACLIENT): ARuta, o '' si esta en una carpeta donde esta sesion
  u otro agente escribe - un adb.exe que el agente deje ahi correria como el
  servicio (revisor del paisaje de la 1.27; el de otro workspace, C31 de la
  1.28). }
function ProgramaFueraDelAgente(const ARuta: string): string;

{ Una CARPETA donde la tool pide un FICHERO: '' si no lo es; si lo es, "es
  una CARPETA, no un fichero" (INVALID_PARAM), el mismo texto que ya daba
  delphi_read. Un sitio para las tools que piden un fichero: siete
  contestaban "no existe" o un INTERNAL del sistema ante una carpeta
  (segunda revision, 27-sep-2026). }
function CarpetaEnVezDeFichero(const APath: string): string;

{ Un FICHERO que no esta: si en su sitio hay una CARPETA lo dice (el texto de
  CarpetaEnVezDeFichero, INVALID_PARAM); si no, devuelve AMsgNoExiste, el "no
  existe" de quien pregunta. Para el "if not TFile.Exists" de las tools que
  piden un fichero: una carpeta decia "no existe" (NOT_FOUND) en build,
  diagnostics, designer, add-unit y delphi_edit (tercera revision, 27-sep-2026). }
function NoEsFichero(const APath, AMsgNoExiste: string): string;

{ Un UNC (\\host\...) que no cae BAJO ningun sitio declarado - raices,
  referencias, ReadOnlyPaths, el vault, la zona de librerias -, comparado por
  TEXTO, sin tocar el disco. Resolverlo (RealPath abre un handle,
  GetLongPathName lo recorre) ya es abrir SMB hacia el host que diga el
  agente ANTES de saber que esta fuera: 21 s medidos por llamada, y la cuenta
  del servicio se autentica si el host contesta (septima revision). Sin
  jaula configurada, False: no hay nada que proteger. }
function UncFueraDeLugares(const APath: string): Boolean;
{ Una ruta que un fichero NOMBRA (un .dpr, un .groupproj) y que nadie
  resuelve en el disco: un UNC de ningun sitio declarado o un prefijo de
  dispositivo. La E/S sobre ella iria a un host que eligio el fichero, no
  el operador. UNA pregunta para NormPath y para quien abre los ficheros que
  lista un proyecto (el rename hacia TFile.Exists sobre \\?\UNC\: 21 s de
  SMB; novena revision). }
function RutaSinTocarElDisco(const APath: string): Boolean;

{ La primera carpeta que YA existe por encima de ARuta (ARuta incluida): lo
  que una operacion cree debajo es suyo, y QuitaCarpetasCreadas lo quita si
  queda vacio. UNA regla para la foto (un create en a\b\c.txt) y para el
  clone (que en n1\n2\n3 fallido dejaba n1\n2; septima revision). }
function PrimerAncestroQueExiste(const ARuta: string): string;
type
  { El juez de "puedo quitar esta carpeta": '' = si. }
  TJuezDeCarpeta = reference to function(const ARuta: string): string;

{ Quita ADesde y sus padres, hasta AAncestro (sin el), mientras esten VACIOS,
  por la puerta de escritura - la de la JAULA, o la de AJuez: quien creo las
  carpetas en otro lugar (la casa de capturas, fuera de la jaula desde el 2af)
  las quita con la puerta de ESE lugar; con la de la jaula se quedaban (2aa de
  la 1.18.2). Nunca lanza: lo que no se puede, se queda. }
procedure QuitaCarpetasCreadas(const ADesde, AAncestro: string;
  const AJuez: TJuezDeCarpeta = nil);

{ El PARAMETRO que no va con un modo (el comando de delphi_config, el kind
  de delphi_create, el modo de delphi_edit...), '' si todos van. ATabla:
  pares (modo, 'sus parametros separados por espacio'); AEnviados: ternas
  (nombre, valor, valor por defecto que publica su esquema): uno vacio, o
  con su valor por defecto, no se ha "enviado" - un cliente que rellena los
  defaults no tropieza (CFG-110 rechazaba section=summary). ASuyos, los del
  modo, para el mensaje. Un modo que no esta en la tabla no se mira: lo
  dice su propia negativa. UNA regla para las tools de varios modos: cada
  una escribia la suya o ignoraba en silencio (septima revision). AVaCon,
  con que modos SI va, de la MISMA tabla, para detras del mensaje: todo lo
  enviado, si algun modo lo toma entero (path y maxdepth sin command: tree);
  si no, el parametro que sobra; '' si no va con ninguno. Un modelo pequeno
  olvidaba el command y leia "path no va con info" (DSGN-047 de la 1.20,
  medido en Hermes: 4 de 10). }
function ParametroQueNoVa(const AModo: string; const ATabla, AEnviados: array of string;
  out ASuyos, AVaCon: string): string;

{ '' salvo que APath sea un FICHERO con el atributo de solo lectura: su
  negativa (SYS-029). Para quien SUSTITUYE el contenido de un fichero
  (AtomicWrite, delphi_upload): renombrarlo o borrarlo si se puede con el
  atributo puesto, asi que no va en la puerta de escritura. Se decia "otro
  proceso lo tiene, cierralo y repite" y el agente repetia para siempre
  (sexta revision). }
function SoloLecturaDenegado(const APath: string): string;

{ "Puedo SUSTITUIR este fichero?": la puerta de escritura sobre la ruta real
  y el atributo de solo lectura, en ese orden - lo que pregunta el escritor
  (AtomicWrite) y lo que tiene que preguntar quien COPIA antes de que el
  escritor se niegue (BackupFile): SYS-029 decia "nothing was written" con
  la copia diaria ya hecha (decima revision). '' = se puede. }
function SustitucionDenegada(const APath: string): string;
{ "Puedo QUITAR o PONER esta entrada en su carpeta?" (borrarla, moverla de o
  a ahi): la puerta de escritura sobre la ruta real y la carpeta REAL que la
  contiene + su nombre (RutaDelEnlace) escribible de verdad. EscrituraDenegada
  sola sigue tambien al ULTIMO enlace: una carpeta de la jaula que es una
  union afuera con un enlace de vuelta dentro pasaba, y el borrado o el
  renombre se hacian en la carpeta de FUERA (revisor 4.8 de la 1.18.0, M2:
  delete y move de un changeset; delphi_delete y delphi_move tenian la
  misma forma). Sin el +R: mover o mandar a la papelera un fichero de solo
  lectura se puede. '' = se puede. }
function EntradaDenegada(const APath: string): string;

{ Quita el atributo de solo lectura a un FICHERO; una carpeta o un enlace
  no se tocan (lo de detras no es de la operacion), ni un enlace duro: su
  atributo es el del otro nombre, quiza fuera de las raices (11-oct-2026).
  Nunca lanza. Estaba a mano en BorraDeVerdad y hacia falta en cada deshacer
  (decima revision). }
procedure QuitaSoloLectura(const APath: string);

{ Borra un fichero que ESTA operacion acaba de dejar: la copia de algo que
  al final no se hizo, lo que un deshacer quita. Una copia hereda el +R del
  original, y TFile.Delete fallaba y la dejaba (decima revision: dos copias
  +R en la papelera, la copia=true que se quedaba). Lanza como
  TFile.Delete; quien llama ya paso la puerta de escritura. }
procedure BorraLoNuestro(const APath: string);

{ Quita la marca de dueno (.by) de una copia de la papelera, si la tiene.
  Nunca lanza: una marca que se queda es inofensiva. UNO: estaba a mano en
  cuatro sitios (novena revision). }
procedure QuitaMarcaDeDueno(const ACopia: string);

{ La copia en la papelera de algo que al final no se hizo (un move que
  fallo, el producto que no se sustituyo), fuera: es nuestra y recien hecha,
  y dejarla sumaba una copia por reintento; con su marca de dueno y las
  carpetas que se crearon para ella hasta AAncestro ('' = ninguna; octava
  revision). Nunca lanza. UNA: vivia en Mcp.Tools.FileOps y Lsp.Patch
  (ColocaProducto) la escribia a mano, sin las carpetas (H7 de la revision del
  paisaje de Fable, 26-oct-2026). }
procedure QuitaCopiaDeSeguridad(const ACopia, AAncestro: string);

{ Copia un fichero PARA el agente (copy=true de una unit, de su designer o
  de una carpeta): la copia es suya y no hereda el atributo de solo lectura
  del original - heredado, la reescritura de la cabecera caia en SYS-029 y
  la copia salia +R (decima revision). Las copias de la papelera NO pasan
  por aqui: conservan el atributo. Lanza como TFile.Copy. }
procedure CopiaNuestra(const AOrigen, ADestino: string);

{ Pega una NOTA a una respuesta sin romperla: si es un objeto JSON, va
  dentro como un campo mas (AClave); si es prosa, detras (ASeparador + la
  nota). Un JSON con una linea de prosa detras dejaba de parsear (lo midio
  el buzon, 2026-08-25). Estaba escrito dos veces (Lsp.Host.WithMailboxNote
  y Mcp.Tools.Designer.ConNotaBinario) y delphi_styles iba a ser la tercera. }
function ConNota(const AText, AClave, ANota: string;
  const ASeparador: string = #10): string;

{ Una ruta que NO es absoluta (<letra>:\ o UNC, la regla de EsRutaAbsoluta):
  la negativa GUARD-021 (INVALID_PARAM); '' si es absoluta o esta vacia. La
  usa PathDenied (y por ella la segunda pasada de la puerta de entrada,
  ArgPathOutsideDenied) y delphi_create para un proyecto nuevo - una regla. }
function RutaRelativaDenegada(const APath: string): string;

{ Whether APath is inside the knowledge vault. The vault belongs to the
  vault_* tools alone, so the code tools skip it in their walks even when it
  sits inside a workspace root - a listing that showed the notes would invite
  an agent to edit them behind the vault's back. }
function InVault(const APath: string): Boolean;
{ ...por su texto o por su ruta REAL (V192 de la 1.23.1): detras de un enlace
  el texto no nombra el vault. ARutaReal, la ruta real con su barra si se
  calculo (hay vaults y el texto no basto), si no ''. LA regla del vault para
  la puerta (JaulaDecide) y para los recorredores (CopiaArbol, WalkFiles). }
function EnUnVault(const APath: string; out ARutaReal: string): Boolean; overload;
function EnUnVault(const APath: string): Boolean; overload;

{ THE Windows name rule, in one place: a path segment ending in a dot or a
  space, or carrying an Alternate Data Stream (":"), is refused - Windows
  normalizes those away when opening, so what a check sees and what gets
  written are different files. Used by the workspace jail AND by the vault
  resolver: the same trick defeated both (delphi_textedit in an early round,
  the vault governance files in round 9), so the rule lives here once instead
  of being re-derived per toolset. '' = the name is fine. }
function PathAnomaly(const APath: string): string;

{ EL juez del comodin de una ruta (V19 de la 1.23, [ComodinEnNombre]): si su
  NOMBRE, el ultimo tramo, lleva * o ?. Lo preguntan la entrada (el suelo y la
  forma larga) y delphi_move / delphi_delete. }
function TieneComodin(const APath: string): Boolean;
{ ...y LA carpeta de esa ruta, la que se juzga en su lugar y donde se busca lo
  que case. }
function CarpetaDelComodin(const APath: string): string;

{ Dead copies are not a scratchpad. The recoverable trash, and the IDE's own
  __history/__recovery, hold the LAST GOOD version of somebody's work - the
  whole reason every write here is safe. Writing into them destroys exactly
  what they exist to preserve, and it does not even need a purge: overwrite
  the copy and the original is gone for good.

  Measured 2026-08-25 by a probe agent: delphi_edit refused the trash, so the
  agent went through delphi_textedit (which handles NON-Delphi text and had no
  such rule) and (a) rewrote another agent's recoverable copy, and (b) edited
  the ".by" owner marker of a copy that was not its own, from "bob" to its own
  name, and then purged it legitimately. A guard one tool wide is not a guard.

  Reading a dead copy is fine (that is how you decide whether to restore it);
  moving one OUT is the restore itself. Only writing IN is refused. }
function DeadCopyWriteDenied(const APath: string): string;

{ APath ES una carpeta de temporales del servidor (__delphi-temp) o esta
  DENTRO de una - sobre la ruta canonica larga, asi que un alias 8.3 es la
  misma carpeta. AEsLaCarpeta: es la carpeta misma, no algo de dentro. EL
  lector de esa pregunta: la puerta de escritura, el reconocedor de
  capturas y delphi_package la hacian cada uno a mano, y delphi_delete iba
  a ser el cuarto (26-sep-2026). }
function EnTemporal(const APath: string): Boolean; overload;
function EnTemporal(const APath: string; out AEsLaCarpeta: Boolean): Boolean; overload;

{ La misma pregunta para la PAPELERA (__delphi-patch, TrashFolderName de
  Lsp.Casa). La hacian a mano cinco sitios con dos formas: la puerta de
  escritura y delphi_edit sobre la ruta canonica larga, y delphi_delete /
  delphi_move / el recorredor de includetrash sobre el texto tal cual - un
  alias 8.3 (__DELP~1) era la papelera para unos y no para otros. }
function EnPapelera(const APath: string): Boolean; overload;
function EnPapelera(const APath: string; out AEsLaCarpeta: Boolean): Boolean; overload;

{ La misma pregunta para las copias muertas del IDE: lo que hay DENTRO de su
  __history (las versiones viejas de cada fichero) o de su __recovery (lo que
  guarda cuando se cae). Sus nombres son del IDE; aqui, UNA vez: la puerta de
  escribir, la segunda barrera de delphi_edit y el buscador de las fuentes de
  una unit los escribian a mano con tres formas, y el ultimo saltaba ademas
  toda carpeta cuya ruta llevase '\backup' (A10 de la 1.23). El filtro de los
  listados (SkipReason) y el .gitignore de un proyecto nuevo los toman de
  aqui. }
const
  CARPETA_HISTORIA_DEL_IDE = '__history';
  CARPETA_RECUPERACION_DEL_IDE = '__recovery';

function EnCopiaDelIde(const APath: string): Boolean;

{ EL gate de DESTINO de escritura: la puerta de escribir con el modo de solo
  lectura (EscrituraDenegada), las carpetas muertas (DeadCopyWriteDenied) y
  la medida del escritor, en ese orden. Todo escritor que cree o reescriba un
  fichero en una ruta que elige el agente pasa por aqui. Hasta el 25-sep-2026
  cada escritor escribia el par a mano (cuatro copias) y dos no lo hacian: el
  out= de las capturas (90 capturas, 66 MB acumulados en una __delphi-temp
  anidada que la purga no alcanza) y el destino de delphi_move. El proximo
  escritor llama a esta y ya esta. El modo de solo lectura, desde el
  25-oct-2026 (V6 de la 1.23): las tools mixtas (capturas, git worktree) lo
  sumaban a mano delante, y la pre-comprobacion de delphi_desktop no lo
  preguntaba. El out= del logcat ya no queda fuera: su excepcion (David,
  25-sep-2026: su sitio natural era un temporal) es de cuando la temporal era
  la del agente en su raiz; desde el 2af de la 1.18.2 es un resto que todo
  escritor niega. }
function WriteTargetDenied(const APath: string): string;

{ Crea una carpeta (y sus padres) TOLERANDO que otro hilo la este creando a la
  vez. TDirectory.CreateDirectory mira si existe y LUEGO crea: dos hilos
  entran juntos, los dos contestan "no existe", los dos crean, y el que pierde
  se lleva un EInOutError "no se puede crear un archivo que ya existe".

  Es la misma carrera que delphi_report ya resolvia para el NOMBRE del fichero
  con CREATE_NEW... doce lineas mas abajo de donde la dejaba abierta para la
  CARPETA. Medido el 2026-09-20 por la bateria de concurrencia, que falla de
  higos a brevas justo por esto: de 8 informes simultaneos llegaban 7.

  Y estaba en las 32 llamadas del servidor, no en una: con dos agentes
  trabajando a la vez, cualquiera podia perder. Por eso se arregla aqui y no
  alli - si el resultado es que la carpeta esta, da igual quien la creo. }
procedure CrearCarpeta(const ADir: string);

{ '' when APath (a .dproj) may be deployed to and run on a target, else a
  refusal. La lista es la del workspace ACTIVO (RemoteRunProjects= en su
  seccion), sin herencia, y VACIA significa NADA ejecutable: fallar abierto
  aqui era la excepcion de todo el servidor y se retiro el 19-sep-2026 (v0.98:
  nada global, ni seccion global). Field 2026-08-24: an agent working on
  project A could run the deployed binary of project B. Una entrada es la
  RUTA de un .dproj (su .dpr, o sin extension, es el mismo) o el comodin; un
  NOMBRE a secas no autoriza nada y RUN-022 dice que ruta escribir: casaba con
  cualquier proyecto de ese nombre, y un homonimo de otra carpeta desplegaba
  encima del permitido (Fable, revision de la 1.22.2). }
function RemoteRunProjectDenied(const APath: string): string;

{ La negativa del modo de solo lectura (READ-002) con lo que se pedia: la da
  EscrituraDenegada y la da la puerta de la llamada (LecturaDenegada, en
  Lsp.PuertaDeLaLlamada). }
function WriteDenied(const AWhat: string): string;
{ LA negativa de un UNC que no es de ningun sitio declarado, la de la jaula y
  la de la pasada de los UNC de la entrada (UncAjenoEnArgumentos, en
  Lsp.PuertaDeLaLlamada). }
function NegativaDeUnc(const APath: string; out AEsFormaDeRed: Boolean): string;

{ INVERSION DE DEPENDENCIA (9.A, metadatos de git). La puerta de ESCRITURA
  vive aqui -la unidad de seguridad, baja- y no puede llamar a git -alto-.
  Mcp.Tools.Git le pone este gancho en su initialization. Dada una CARPETA
  QUE EXISTE, deja en AGitDir/AComun lo que contesta git (rev-parse
  --absolute-git-dir --git-common-dir), en forma de Windows; False si no es un
  repo o git no contesta. Cacheado por carpeta en quien lo pone. Sin asignar
  (una herramienta sin git, un contexto de prueba) el atajo del segmento .git
  sigue siendo la unica puerta de metadatos. }
var
  DameGitDirDeCarpeta: function(const ACarpeta: string;
    out AGitDir, AComun: string): Boolean;
  { ...y la MISMA pregunta SIN cache y con la raiz del arbol de trabajo
    (ARaiz: '' en un repo bare), para una decision que un "no es repo" de
    antes de un init no puede contestar: la copia de un arbol con su git
    dentro (V19). La pone Mcp.Tools.Git (DondeViveElRepo). }
  DameRepoDeCarpeta: function(const ACarpeta: string;
    out AGitDir, AComun, ARaiz: string): Boolean;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.StrUtils,
  System.IOUtils,
  System.Generics.Collections,
  Lsp.Dproj,            // CanonicalPlatform: the platform whitelist already exists
  Lsp.NetDrives,        // las letras de red de los sitios declarados
  Lsp.Sandbox,          // SidDelProceso
  Lsp.Texts,
  Lsp.Json,
  Lsp.Rutas,
  Lsp.Reparse,
  Lsp.Casa,
  Lsp.Settings,
  Lsp.Identidad,
  Lsp.ProcessLaunch, // TrocearArgs y EnComillas: la linea de una orden
  Lsp.Lugares,
  Lsp.Mascara,
  Lsp.Pascal, // SinMayusculas: EL pliegue de lo que no es una ruta
  MCPServer.Logger, // el aviso de un dia de la papelera que se queda
  Lsp.Listas,
  System.Character,
  Lsp.Papelera;

// el tope es el de Windows: si su MAX_PATH no es el de aqui, no compila
{$IF RUTA_MAX_DE_WINDOWS <> MAX_PATH - 1}
  {$MESSAGE ERROR 'RUTA_MAX_DE_WINDOWS no es MAX_PATH - 1'}
{$IFEND}

var
  // los dias de la papelera que ya dijeron en el log que se quedan: UNA vez
  // por dia mientras viva el servidor (la purga corre en cada copia)
  GDiasQueSeQuedan: TDictionary<string, Boolean>;

function RutaQueWindowsNoAbre(const APath: string): string;
begin
  Result := '';
  if Length(APath) > RUTA_MAX_DE_WINDOWS then
    Result := MsgFmt(SR_GUARD_RUTA_QUE_WINDOWS_NO_ABRE_FMT, [Length(APath), RUTA_MAX_DE_WINDOWS]);
end;

function RutaLargaDenegada(const APath: string): string;
begin
  Result := '';
  if Length(APath) > RUTA_ESCRIBIBLE_MAX then
    Result := MsgFmt(SR_GUARD_RUTA_LARGA_FMT, [Length(APath), RUTA_ESCRIBIBLE_MAX]);
end;

function ComandoDeTest(const ACmd, AProject, APath: string): string;
begin
  Result := SinMayusculas(ACmd.Trim);
  // "project" only exists for run. Falling back to discover and then
  // complaining that discover needs "path" cost a call, and the call after it
  // was delphi_help (field round 11).
  if (Result = '') and (AProject.Trim <> '') and (APath.Trim = '') then
    Result := 'run';
  if Result = '' then
    Result := 'discover';
end;

function WriteTargetDenied(const APath: string): string;
begin
  Result := EscrituraDenegada(APath);
  if Result = '' then
    Result := DeadCopyWriteDenied(APath);
  // ...y la medida del escritor atomico (GUARD-028), sobre el destino que
  // el agente nombra y antes de que nadie cree carpetas por el camino
  if Result = '' then
    Result := RutaLargaDenegada(APath);
end;

{ APath ES la carpeta ANombre o esta dentro de una, sobre la ruta canonica
  larga. Las dos carpetas del servidor que se reconocen por su nombre -la
  temporal y la papelera- preguntan aqui; la siguiente, tambien. }
function EnCarpetaLlamada(const APath, ANombre: string;
  out AEsLaCarpeta: Boolean): Boolean;
var
  P, T: string;
begin
  // por la clave del disco (ClaveDeRuta), no por .ToLower: con el turco
  // __DELPHI-PATCH no era la papelera, y con la I con punto una carpeta que
  // NTFS separa lo era (V105 de la 1.23.1)
  P := ClaveDeRuta(SinBarraFinal(LongCanonical(APath)));
  T := '\' + ClaveDeRuta(ANombre);
  AEsLaCarpeta := P.EndsWith(T);
  Result := AEsLaCarpeta or P.Contains(T + '\');
end;

function EnTemporal(const APath: string; out AEsLaCarpeta: Boolean): Boolean;
begin
  Result := EnCarpetaLlamada(APath, TempFolderName, AEsLaCarpeta);
end;

function EnTemporal(const APath: string): Boolean;
var
  EsLaCarpeta: Boolean;
begin
  Result := EnTemporal(APath, EsLaCarpeta);
end;

function EnPapelera(const APath: string; out AEsLaCarpeta: Boolean): Boolean;
begin
  Result := EnCarpetaLlamada(APath, TrashFolderName, AEsLaCarpeta);
end;

function EnPapelera(const APath: string): Boolean;
var
  EsLaCarpeta: Boolean;
begin
  Result := EnPapelera(APath, EsLaCarpeta);
end;

function EnCopiaDelIde(const APath: string): Boolean;
var
  Carpeta: string;
  EsLaCarpeta: Boolean;
begin
  // DENTRO de una: la carpeta del fichero es una de ellas o esta dentro (la
  // carpeta misma se crea y se quita: no pisa ninguna copia)
  Carpeta := ExtractFileDir(ConBarrasDeWindows(APath));
  Result := (Carpeta <> '') and
    (EnCarpetaLlamada(Carpeta, CARPETA_HISTORIA_DEL_IDE, EsLaCarpeta) or
     EnCarpetaLlamada(Carpeta, CARPETA_RECUPERACION_DEL_IDE, EsLaCarpeta));
end;

function DeadCopyWriteDenied(const APath: string): string;

  function DeUnaForma(const ARuta: string): string;
  var
    P: string;
  begin
    Result := '';
    // Pascal has no string escapes: '\' here would be TWO literal backslashes
    // and no path on earth contains them. Written that way once (a Python habit
    // leaking into Delphi) and the whole guard matched nothing while looking
    // perfectly correct - the ".by" rule passed only because it has no slash.
    // canonical first: an 8.3 alias like __DELP~1 IS the trash
    P := LongCanonical(ARuta);
    if EsMarcaDeDueno(P) then // la marca de dueno (Lsp.Casa)
      Exit(MsgText(SR_GUARD_OWNER_MARKER));
    if EnPapelera(ARuta) then
      Exit(MsgText(SR_GUARD_DEAD_TRASH));
    // La carpeta de temporales del servidor, por el mismo motivo y uno propio:
    // se puede borrar entera en cualquier momento, asi que escribir ahi es
    // escribir en algo que no tiene por que seguir estando. Esta es la puerta
    // de ESCRIBIR (lo que hay en la de una raiz es de versiones viejas: las
    // capturas viven en la casa del servidor desde la 1.18.2).
    if EnTemporal(ARuta) then
      Exit(MsgText(SR_GUARD_DEAD_TEMP));
    if EnCopiaDelIde(ARuta) then
      Exit(MsgText(SR_GUARD_DEAD_IDE));
  end;

var
  Real: string;
begin
  // el texto Y la ruta REAL, como los metadatos de git: una union a
  // __delphi-patch\<dia> dejaba plantar ahi una "copia del dia" que restore
  // traeria (V112 de la 1.23.1, medido). Una real que no se resuelve la niega
  // la jaula (EscribibleDeVerdad), que va antes
  Result := DeUnaForma(APath);
  if Result <> '' then
    Exit;
  try
    Real := RealPath(APath);
  except
    Real := '';
  end;
  if (Real <> '') and not EsPrefijoDeDispositivo(Real) then
    Result := DeUnaForma(Real);
end;

procedure CrearCarpeta(const ADir: string);
var
  D: string;
begin
  if ADir = '' then
    Exit;
  try
    TDirectory.CreateDirectory(ADir);
  except
    // Si despues del intento la carpeta esta, alguien gano la carrera y es
    // exactamente lo que queriamos. Si no esta, el fallo es de verdad.
    if not TDirectory.Exists(ADir) then
    begin
      // Un FICHERO en el camino (U.pas\sub) es una ruta equivocada, no un
      // fallo del servidor: salia EInOutError como INTERNAL en cinco tools
      // (tercera revision, 27-sep-2026)
      for D in Ancestros(SinBarraFinal(ADir)) do
      begin
        if TFile.Exists(D) then
          // la papelera o los temporales del SERVIDOR tapados por un fichero:
          // la ruta del agente era buena, estorba algo (DENIED, no INVALID)
          if DeadCopyWriteDenied(D) <> '' then
            raise Exception.Create(MsgFmt(SR_GUARD_FICHERO_EN_CARPETA_SERVIDOR_FMT, [D]))
          else
            raise Exception.Create(MsgFmt(SR_GUARD_FICHERO_EN_RUTA_FMT, [ADir, D]));
      end;
      raise;
    end;
  end;
end;

function RemoteRunProjectDenied(const APath: string): string;
var
  Lista: TArray<string>;
  E, Full, Name, Ruta: string;
begin
  // La lista del workspace ACTIVO, sin herencia. Y desde el 19-sep-2026 la
  // lista vacia ya no significa "cualquiera de la jaula" sino NADA: era el
  // unico permiso que fallaba abierto, al reves que todo el resto del
  // servidor. Lo que no se declara no existe.
  // Y lo que autoriza es un PROYECTO: la comparacion de abajo es sin
  // extension, y un hermano X.txt casaba con X.dproj (quinta ronda de Fable)
  if not EsProyectoOSuFuente(APath) then
    Exit(MsgFmt(SR_UNIT_PROJECT_EXT_FMT, [TPath.GetFileName(APath)]));
  Lista := RemoteProjectsNow;
  if Length(Lista) = 0 then
    Exit(MsgText(SR_REMOTERUN_NOPROJLIST));
  Result := '';
  // Comodin EXPLICITO del operador (EsComodinDeLista, el de las cuatro
  // listas): cualquier proyecto de la jaula. Declararlo sigue siendo su
  // decision.
  for E in Lista do
    if EsComodinDeLista(E) then
      Exit;
  try
    Full := TPath.GetFullPath(APath);
  except
    Full := APath;
  end;
  Name := TPath.GetFileNameWithoutExtension(Full);
  // la RUTA, por la forma LARGA de los dos lados: una entrada del operador
  // escrita en 8.3 no casaba nunca (fallaba cerrado; septima revision). Su
  // .dpr, o sin extension, es el mismo proyecto: se comparan sin la extension
  // del .dproj (el .dpr pasa por DprojDe, como en las tools)
  for E in Lista do
    if EsRutaAbsoluta(E.Trim) then
    begin
      Ruta := DprojDe(E.Trim);
      if SameText(TPath.GetExtension(Ruta), '.dproj') then
        Ruta := ChangeFileExt(Ruta, '');
      if SameFileName(FormaLarga(Ruta), FormaLarga(ChangeFileExt(Full, ''))) then
        Exit;
    end;
  // un NOMBRE a secas que es el de este proyecto: el operador queria este o
  // un homonimo de otra carpeta, y eso solo lo dice una ruta
  for E in Lista do
    if not EsRutaAbsoluta(E.Trim) and SameFileName(E.Trim, Name) then
      Exit(MsgFmt(SR_REMOTERUN_ENTRADA_A_SECAS_FMT, [E.Trim, Full]));
  Result := MsgFmt(SR_REMOTERUN_PROJECT_DENIED_FMT,
    [Name, string.Join(', ', Lista)]);
end;

function InVault(const APath: string): Boolean;
var
  Vault: string;
begin
  Result := False;
  // el vault de CUALQUIER workspace, no solo el del activo (TodosLosVaults)
  for Vault in TodosLosVaults do
    if EnLugar(APath, Vault) then // la forma larga: KNOWLE~1 es el vault
      Exit(True);
end;

function EnUnVault(const APath: string; out ARutaReal: string): Boolean;
begin
  ARutaReal := '';
  if InVault(APath) then
    Exit(True);
  if not HayVaults then
    Exit(False);
  ARutaReal := IncludeTrailingPathDelimiter(RealPath(APath));
  Result := InVault(ARutaReal);
end;

function EnUnVault(const APath: string): Boolean;
var
  Real: string;
begin
  Result := EnUnVault(APath, Real);
end;

function WriteDenied(const AWhat: string): string;
begin
  Result := MsgFmt(SR_READ_ONLY_FMT, [AWhat]);
end;

function EscrituraDenegada(const APath: string): string;
begin
  if IsReadOnlyNow then
    Exit(WriteDenied(MsgFmt(SF_GUARD_ESCRIBIR_FMT, [TPath.GetFileName(SinBarraFinal(APath))])));
  Result := PathDenied(APath);
end;

function ProgramaDelOperador(const APrograma, APath: string): string;
begin
  Result := ProgramaFueraDelAgente(ProgramaEnPath(APrograma, APath));
end;

function ProgramaFueraDelAgente(const ARuta: string): string;
begin
  Result := ARuta;
  // Donde el agente escribe no esta el programa del operador. La pregunta es
  // la jaula de ESCRITURA (PathDenied) sin el juez de los metadatos de git
  // (APermiteGit): ese juez lanza git para contestar, y git se resuelve
  // AQUI (medido el 14-oct-2026: la bateria de git por ruta se quedo
  // colgada en la recursion). El modo de solo lectura no cuenta: el
  // programa del operador lo es con la sesion abierta o cerrada. SIN raices
  // no hay carpeta del agente: PathDenied contesta '' ("sin jaula, sin
  // reglas de escritura") y eso negaba el git de verdad a un stdio de solo
  // lectura (medido el 14-oct-2026 por el release_check: test_git_worktree,
  // "solo lectura: list" con GIT-050)
  if (Result <> '') and HayJaula and
     (PathDenied(ExtractFileDir(Result), True) = '') then
    Result := '';
  // ...ni donde escribe OTRO agente: la jaula de arriba es la de quien llama,
  // y un git.exe en la raiz de otro workspace no era "de este agente" - se
  // lanzaba con la cuenta del servicio, plantado por el de alli (C31 de la
  // 1.28, medido: test_git_otro_workspace_128). Las raices de ESCRITURA de
  // todo lo declarado; dentro por el texto (quien escribe la raiz cambia lo
  // que haya en ella, una union tambien) o de verdad (una union de fuera que
  // lleva dentro)
  if (Result <> '') and EnRaizDeAlgunAgente(ExtractFileDir(Result)) then
    Result := '';
end;

function CarpetaEnVezDeFichero(const APath: string): string;
begin
  Result := '';
  if APath.Trim = '' then
    Exit;
  // un nombre que acaba en separador nombra una CARPETA, exista o no:
  // textedit create y upload creaban una carpeta con el nombre del
  // fichero (septima revision)
  if APath.Trim.EndsWith('\') or APath.Trim.EndsWith('/') then
    Exit(MsgFmt(SR_GUARD_BARRA_FINAL_FMT, [APath]));
  if TDirectory.Exists(APath) then
    Result := MsgFmt(SR_LSP_IS_FOLDER_FMT, [APath]);
end;

function NoEsFichero(const APath, AMsgNoExiste: string): string;
begin
  Result := CarpetaEnVezDeFichero(APath);
  if Result = '' then
    Result := AMsgNoExiste;
end;

function ConNota(const AText, AClave, ANota: string;
  const ASeparador: string): string;
var
  O: TJSONObject;
  T: string;
begin
  Result := AText;
  if ANota = '' then
    Exit;
  T := AText.TrimRight;
  if T.StartsWith('{') and T.EndsWith('}') then
  begin
    O := ObjetoJson(T); // EL lector (Lsp.Json): estaba su cuerpo aqui
    if O <> nil then
      try
        O.AddPair(AClave, ANota.Trim);
        Exit(O.ToJSON);
      finally
        O.Free;
      end;
  end;
  Result := AText + ASeparador + ANota;
end;

function SoloLecturaDenegado(const APath: string): string;
var
  A: Cardinal;
begin
  Result := '';
  A := GetFileAttributes(PChar(APath));
  if (A <> INVALID_FILE_ATTRIBUTES) and ((A and FILE_ATTRIBUTE_DIRECTORY) = 0) and
     ((A and FILE_ATTRIBUTE_READONLY) <> 0) then
    Result := MsgFmt(SR_SOLO_LECTURA_ATRIBUTO_FMT, [TPath.GetFileName(APath)]);
end;

function SustitucionDenegada(const APath: string): string;
begin
  Result := EscrituraDenegada(APath);
  // ...y por DONDE se escribe: el temporal y el renombre nacen en la carpeta
  // DADA, y EscrituraDenegada mira la ruta real de APath, que sigue tambien
  // al ULTIMO enlace - una carpeta de la jaula que fuese una union afuera con
  // un enlace de vuelta dentro pasaba, y el temporal nacia FUERA (P4-a de la
  // 1.18.0: la forma del A1 que el revisor de P3 midio en las puertas de los
  // lugares). La real de la carpeta + el nombre (RutaDelEnlace), como alli,
  // contra la ruta REAL de cada sitio (EscribibleDeVerdad): pasarla por la
  // puerta de TEXTO la compararia con las raices declaradas, y una raiz
  // declarada por una union no casaria nunca (las dos formas de un sitio)
  if (Result = '') and not EscribibleDeVerdad(RutaDelEnlace(APath)) then
    Result := MsgFmt(SR_SUSTITUCION_CARPETA_REAL_FMT, [APath]);
  if Result = '' then
    Result := SoloLecturaDenegado(APath);
end;

function EntradaDenegada(const APath: string): string;
begin
  Result := EscrituraDenegada(APath);
  if (Result = '') and not EscribibleDeVerdad(RutaDelEnlace(APath)) then
    Result := MsgFmt(SR_ENTRADA_CARPETA_REAL_FMT, [APath]);
end;

{ Cuantos NOMBRES tiene el fichero de APath: 1 en uno normal; mas de 1 es un
  enlace duro, el MISMO fichero con otro nombre en otra parte - quiza fuera de
  las raices -, y sus atributos SON los de ese otro. 0 si no se puede abrir
  (no se sabe: quien pregunta no toca nada). Sin cruzar un enlace. }
function NombresDelFichero(const APath: string): Cardinal;
var
  H: THandle;
  Info: TByHandleFileInformation;
begin
  Result := 0;
  H := CreateFile(PChar(APath), 0, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
    nil, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT or FILE_FLAG_BACKUP_SEMANTICS, 0);
  if H = INVALID_HANDLE_VALUE then
    Exit;
  try
    if GetFileInformationByHandle(H, Info) then
      Result := Info.nNumberOfLinks;
  finally
    CloseHandle(H);
  end;
end;

procedure QuitaSoloLectura(const APath: string);
var
  A: Cardinal;
begin
  A := GetFileAttributes(PChar(APath));
  if (A = INVALID_FILE_ATTRIBUTES) or ((A and FILE_ATTRIBUTE_DIRECTORY) <> 0) or
     ((A and FILE_ATTRIBUTE_READONLY) = 0) or EsEnlace(APath) then
    Exit;
  // un enlace duro tampoco: su +R es el del otro nombre, y quitarlo aqui lo
  // quitaba FUERA de las raices (medido el 11-oct-2026: una carpeta con un
  // enlace duro, purgada, dejo sin +R ni oculto el fichero de fuera)
  if NombresDelFichero(APath) <> 1 then
    Exit;
  SetFileAttributes(PChar(APath), A and not FILE_ATTRIBUTE_READONLY);
end;

const
  // FileDispositionInfoEx (Windows 10 1809) y sus banderas: borrar un nombre
  // aunque lleve +R SIN cambiar los atributos del fichero
  CLASE_DISPOSICION_EX = 21;
  DISPOSICION_BORRA = $00000001;
  DISPOSICION_IGNORA_SOLO_LECTURA = $00000010;

function SetFileInformationByHandleCrudo(hFile: THandle; AClase: Integer; AInfo: Pointer;
  ATam: DWORD): BOOL; stdcall; external kernel32 name 'SetFileInformationByHandle';

{ Borra el NOMBRE APath sin cambiar los atributos del fichero: con un +R
  tambien, y en un enlace duro solo se va este nombre - el otro, quiza fuera
  de las raices, se queda con sus bytes y sus atributos. EL borrador de un
  fichero de BorraArbolDentro y BorraLoNuestro: los dos ponian los atributos a
  mano antes de borrar (11-oct-2026). Un enlace cae como enlace. Donde el
  sistema de ficheros no conoce la disposicion Ex, como antes, sin tocar un
  enlace duro (QuitaSoloLectura no lo toca, y su borrado con +R falla y se
  dice). Lanza como TFile.Delete. }
procedure BorraNombre(const APath: string);
var
  H: THandle;
  Banderas: DWORD;
begin
  H := CreateFile(PChar(APath), _DELETE, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
    nil, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, 0);
  if H <> INVALID_HANDLE_VALUE then
  try
    Banderas := DISPOSICION_BORRA or DISPOSICION_IGNORA_SOLO_LECTURA;
    if SetFileInformationByHandleCrudo(H, CLASE_DISPOSICION_EX, @Banderas, SizeOf(Banderas)) then
      Exit;
  finally
    CloseHandle(H);
  end;
  QuitaSoloLectura(APath);
  TFile.Delete(APath);
end;

procedure BorraLoNuestro(const APath: string);
begin
  BorraNombre(APath);
end;

procedure QuitaMarcaDeDueno(const ACopia: string);
begin
  try
    if TFile.Exists(MarcaDeDueno(ACopia)) then
      BorraLoNuestro(MarcaDeDueno(ACopia));
  except
  end;
end;

procedure QuitaCopiaDeSeguridad(const ACopia, AAncestro: string);
begin
  if ACopia = '' then
    Exit;
  try
    if TDirectory.Exists(ACopia) then
      BorraArbol(ACopia)
    else if TFile.Exists(ACopia) then
      BorraLoNuestro(ACopia); // la copia de un +R es +R (decima revision)
  except
    // se queda: es una copia en la papelera, no hace dano
  end;
  QuitaMarcaDeDueno(ACopia);
  QuitaCarpetasCreadas(ExtractFileDir(ACopia), AAncestro);
end;

procedure CopiaNuestra(const AOrigen, ADestino: string);
begin
  // copiar es LEER el origen: un enlace duro con un nombre que la sesion no
  // lee no se copia (la segunda barrera: quien llama ya pregunto a la puerta
  // de leer por la ruta que le dieron, y CopiaArbol por cada fichero)
  var Motivo := EnlaceDuroIlegible(AOrigen);
  if Motivo <> '' then
    raise Exception.Create(Motivo);
  TFile.Copy(AOrigen, ADestino);
  QuitaSoloLectura(ADestino);
end;

function RaicesDisponibles: string; forward;

function RutaRelativaDenegada(const APath: string): string;
begin
  Result := '';
  if (APath.Trim = '') or EsRutaAbsoluta(APath.Trim) then
    Exit;
  // el nombre de la casa del servidor que pone el filtro de salida, vuelto
  // como ruta: se dice lo que es (2ag de la 1.18.2, revisor). Las raices, por
  // LA lista de GUARD-002 (RaicesDisponibles): las dos se componian a mano
  // con todas las de escritura, las que no se alcanzan incluidas y sin las de
  // solo lectura (Fable, revision de la 1.22.2)
  if StartsText(NOMBRE_CASA_SERVIDOR, APath.Trim) or StartsText(NOMBRE_CASA_CACHE, APath.Trim) then
    Exit(MsgFmt(SR_GUARD_CASA_DEL_SERVIDOR_FMT, [APath, RaicesDisponibles]));
  Result := MsgFmt(SR_GUARD_RUTA_RELATIVA_FMT, [APath, RaicesDisponibles]);
end;

{ LA negativa de la jaula (GUARD-002), con los sitios donde SI se trabaja
  (RaicesDisponibles: los que el servidor alcanza ahora, los de solo lectura
  marcados). Estaba compuesta a mano en tres sitios, nombraba una raiz que no
  estaba y callaba las de solo lectura, que tambien se leen (Hermes,
  22-oct-2026: tres negativas hasta dar con la raiz; medido el 23-oct-2026). }
function NegativaDeJaula(const APath: string): string;
begin
  Result := MsgFmt(SR_JAIL_FMT, [APath, RaicesDisponibles]);
end;

{ LA negativa de un UNC que no es de ningun sitio declarado, por UN sitio: la
  daban la pasada de la entrada y la jaula, cada una la suya. Si es la ruta
  de RED de un sitio declarado con su letra (una unidad de red), lo dice
  con su mensaje (GUARD-029) y AEsFormaDeRed lo cuenta. Sigue negada -
  cada sitio vale en la forma en que se declaro -, pero el mensaje de la
  jaula saldria ya traducido a esa letra por el enmascarador: "srvx:\a
  esta FUERA; solo se trabaja en srvx:\" (segundo revisor de la 1.8.2;
  medido con J17 de test_git_jaula). Sin abrir nada: FormaDeclarada mira
  la tabla de unidades de la sesion. }
function NegativaDeUnc(const APath: string; out AEsFormaDeRed: Boolean): string;
var
  Declarada: string;
begin
  // el modo local cerrado no tiene sitios: su negativa es la del cierre
  AEsFormaDeRed := False;
  Result := NegativaDeCierre;
  if Result <> '' then
    Exit;
  Declarada := FormaDeclarada(APath);
  AEsFormaDeRed := not SameFileName(Declarada, APath);
  if AEsFormaDeRed then
    Result := MsgFmt(SR_JAIL_FORMA_DE_RED_FMT, [Declarada])
  else
    Result := NegativaDeJaula(APath);
end;

{ Una unidad virtual que la expansion de ida dejo tal cual porque esta sesion
  no la sirve: negada por su NOMBRE, sin resolverla nunca en el disco (eso
  filtraba las letras de la maquina). '' si no lo es, o si no hay unidades
  virtuales. La de PathAnomaly (las lineas de ordenes, que la pedian por
  trozo, se fueron con los args de git en la 1.19.0). }
function MismaRutaEnOtraUnidad(const APath: string; APermiteGit: Boolean): string; forward;

function UnidadNoServidaDenegada(const APath: string): string;
var
  Units, List: string;
  C: Char;
begin
  Result := '';
  Units := ServedDriveLetters;
  C := VirtualUnitLetter(APath);
  if (Units = '') or (C = #0) or (Pos(C, Units) > 0) then
    Exit;
  for C in Units do
  begin
    if List <> '' then
      List := List + ', ';
    List := List + VirtualUnitOf(C, Units) + ':';
  end;
  Result := MsgFmt(SR_UNIT_UNKNOWN_FMT, [APath, List]);
  // ...y si solo se equivoco de unidad, la misma ruta bajo una que esta sesion
  // lee y existe: LA casa de READ-011 (V92), con la letra que nombro y su
  // cola; la unidad que no se sirve no se toca nunca (V140 de la 1.23.1)
  var Otra := MismaRutaEnOtraUnidad(RutaBajoSuLetra(APath), False);
  if Otra <> '' then
    Result := Result + ' ' + MsgFmt(SN_READ_OTRA_UNIDAD_FMT, [Otra]);
end;

function ReadOnlyRootOf(const APath: string): string;
var
  Full, Real, R: string;
begin
  Result := '';
  try
    // Formas LARGAS canonicas en los dos lados: una raiz declarada con
    // nombres cortos (ABCDEF~1) y una ruta que llega resuelta (RealPath la
    // alarga) son el mismo sitio. Comparar texto contra texto no casaba.
    Full := FormaLarga(APath);
    // ...y por la ruta REAL: un junction dentro de una raiz que apunte a una
    // referencia (o a una declarada DENTRO de la raiz) llevaba a ella con
    // un texto que no la nombra, y se escribia (auditoria 25-sep-2026).
    Real := IncludeTrailingPathDelimiter(RealPath(APath));
  except
    Exit;
  end;
  for R in WorkspaceReadOnlyRoots do
    if RutaDentroDe(FormaLarga(R), Full) or EnLugar(Real, RealPath(SinBarraFinal(R)), False) then
      Exit(SinBarraFinal(R));
end;

{ La letra de un sitio no existe para este proceso: nada de lo que hay
  detras puede salir bien, en ninguna tool. }
function LetraNoConectada(const ASitio: string): Boolean;
begin
  Result := (LetraDeRuta(ASitio) <> #0) and
    (ClaseDeLetra(LetraDeRuta(ASitio)) = clAusente);
end;

function MotivoRaizNoDisponible(const ARaiz: string): string;
begin
  Result := '';
  if LetraNoConectada(ARaiz) then
    Result := MsgFmt(SF_WS_LETRA_NO_CONECTADA_FMT, [LetraDeRuta(ARaiz)])
  else if (LetraDeRuta(ARaiz) <> #0) and
          (ClaseDeLetra(LetraDeRuta(ARaiz)) = clLocal) and
          not TDirectory.Exists(SinBarraFinal(ARaiz)) then
    Result := MsgText(SF_WS_CARPETA_RAIZ_NO_EXISTE);
end;

function RaicesNoDisponibles(const ASitios: TArray<string>): TArray<TRaizNoDisponible>;
var
  Una: TRaizNoDisponible;
begin
  Result := [];
  for var R in ASitios do
  begin
    Una.Raiz := SinBarraFinal(R);
    Una.Motivo := MotivoRaizNoDisponible(R);
    if Una.Motivo = '' then
      Continue;
    var Ya := False;
    for var Dicha in Result do
      if SameFileName(Dicha.Raiz, Una.Raiz) then
        Ya := True;
    if not Ya then
      Result := Result + [Una];
  end;
end;

{ Las raices y referencias a las que SI se llega: donde seguir trabajando, las
  de solo lectura marcadas (se leen y no se escriben). La lista de WS-022 y de
  GUARD-002 (NegativaDeJaula). }
function RaicesDisponibles: string;
var
  R: string;
begin
  Result := '';
  for R in WorkspaceRoots + WorkspaceReadOnlyRoots do
    if MotivoRaizNoDisponible(R) = '' then
    begin
      if Result <> '' then
        Result := Result + ', ';
      if RutaEnLista(R, WorkspaceReadOnlyRoots) then
        Result := Result + MsgFmt(SF_JAIL_SOLO_LECTURA_FMT, [SinBarraFinal(R)])
      else
        Result := Result + SinBarraFinal(R);
    end;
  if Result = '' then
    Result := MsgText(SF_WS_NINGUNA_RAIZ_DISPONIBLE);
end;

function RaizEnLetraNoConectada(const APath: string): string;
var
  R: string;
begin
  Result := '';
  for R in WorkspaceRoots + WorkspaceReadOnlyRoots do
    if LetraNoConectada(R) and EnLugar(APath, R) then
      Exit(MsgFmt(SR_WS_RAIZ_NO_DISPONIBLE_FMT, [SinBarraFinal(R),
        MotivoRaizNoDisponible(R), RaicesDisponibles]));
end;

function TieneComodin(const APath: string): Boolean;
begin
  Result := ExtractFileName(SinBarraFinal(APath)).IndexOfAny(['*', '?']) >= 0;
end;

function CarpetaDelComodin(const APath: string): string;
begin
  Result := ExtractFileDir(SinBarraFinal(APath));
end;

{ Windows silently strips trailing dots/spaces from a file name, so a path
  like "X.pas." creates "X.pas" while any check on the literal string sees a
  different extension. Alternate Data Streams ("X.pas::$DATA") play the same
  trick. Measured bypass in the field test: both defeated the .pas guard of
  delphi_textedit. Any path whose final name would be normalized by the OS
  is refused outright - it is never a legitimate request. }
function PathAnomaly(const APath: string): string;
var
  Name, Rest: string;
  C: Char;
begin
  Result := '';
  // Los controles nunca nombran un fichero: NUL trunca el nombre en Win32.
  for C in APath do
    if Ord(C) < 32 then
      Exit(MsgFmt(SR_GUARD_CONTROL_EN_RUTA_FMT, [Ord(C)]));
  // A virtual unit that survived the inbound expansion is one this server does
  // not serve: it must be refused BY NAME, never resolved against the real
  // filesystem (that is what leaked the host's drive letters). Only when a
  // virtual namespace exists at all - with no served drive there is nothing to
  // mask and nothing to name. (UnidadNoServidaDenegada; tambien la pide, por
  // aqui, cada ruta de "paths" de delphi_git.)
  Result := UnidadNoServidaDenegada(APath);
  if Result <> '' then
    Exit;
  // Un prefijo de dispositivo o de ruta extendida, y una unidad virtual sin
  // su barra, con SU motivo: caian en el de abajo, "alternate data stream"
  // (sexta revision)
  // ...tambien con barras normales (//?/ salia GUARD-009; septima revision)
  if EsPrefijoDeDispositivo(APath) then
    Exit(MsgFmt(SR_GUARD_PREFIJO_DISPOSITIVO_FMT, [APath]));
  // un comodin no es parte de una ruta: acababa en INTERNAL dentro de
  // Windows, y un move dejaba copia y carpeta (septima revision)
  if (APath.IndexOf('*') >= 0) or (APath.IndexOf('?') >= 0) then
    Exit(MsgFmt(SR_GUARD_COMODIN_FMT, [APath]));
  if EmpiezaPorUnidadVirtual(APath) then
    Exit(MsgFmt(SR_GUARD_UNIDAD_SIN_BARRA_FMT, [APath, Copy(APath, 1, 5)]));
  // ':' is legal only as the drive separator (C:\...): anywhere else it
  // opens an Alternate Data Stream, which hides content from every check.
  Rest := APath;
  if (Length(Rest) >= 2) and (Rest[2] = ':') then
    Rest := Copy(Rest, 3, MaxInt);
  if Rest.Contains(':') then
    Exit(MsgFmt(SR_GUARD_RUTA_CONTIENE_FUERA_UNIDAD_FMT, [APath]));
  // EVERY segment, not just the last: a folder named "notas " normalizes the
  // same way, and checking only the file name left the rest of the path to
  // slip through (field round 9 hit the same class in the vault resolver).
  for Name in PrefijoSinBarra(Rest).Split(['\', '/']) do
  begin
    if Name = '' then
      Continue;
    // "." and ".." are standard navigation, not a normalization trick: the
    // jail canonicalizes before deciding, so an escape via ".." is caught
    // there. Rejecting them here refused legitimate parent-directory paths.
    if (Name = '.') or (Name = '..') then
      Continue;
    // un nombre que Windows reserva para un dispositivo, con o sin extension: en
    // este Windows 11 se crea como un fichero normal que un Explorer de Windows
    // 10 no abre ni borra; en otros es el dispositivo mismo (decima revision,
    // medido con CON.txt). No hay juez: RtlIsDosDeviceName_U contesta por ESTE
    // Windows, que en una carpeta solo marca NUL (build 26100, V131 de la 1.24),
    // y lo que se protege es el fichero en los otros: la lista documentada
    var Base := Name;
    if Base.IndexOf('.') > 0 then
      Base := Base.Substring(0, Base.IndexOf('.'));
    // (como NTFS compara dos nombres, RutaEnLista: con el locale, en un Windows
    // turco conin$ no era CONIN$; revisor del paisaje de la 1.28, J7)
    if RutaEnLista(Base.TrimRight, ['CON', 'PRN', 'AUX', 'NUL', 'CONIN$', 'CONOUT$',
         'COM0', 'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
         'COM'#$00B9, 'COM'#$00B2, 'COM'#$00B3,
         'LPT0', 'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
         'LPT'#$00B9, 'LPT'#$00B2, 'LPT'#$00B3]) then
      Exit(MsgFmt(SR_GUARD_NOMBRE_RESERVADO_FMT, [Name, APath]));
    // mas de 255 no es un nombre de Windows: SYS-009 INTERNAL al escribir
    // (octava revision)
    if Length(Name) > 255 then
      Exit(MsgFmt(SR_GUARD_NOMBRE_LARGO_FMT, [Length(Name), PrincipioDeTexto(Name, 40)]));
    if Name.Trim([' ']).TrimRight([' ', '.']) <> Name then
    begin
      var Sugerido := Name.Trim([' ']).TrimRight([' ', '.']);
      if Sugerido <> '' then
        Sugerido := MsgFmt(SF_GUARD_QUIZAS_FMT, [Sugerido]);
      Exit(MsgFmt(SR_GUARD_NOMBRE_EMPIEZA_TERMINA_PUNTO_FMT, [Name, Sugerido]));
    end;
  end;
end;

{ El unico borrador de arboles del servidor (la nota larga, en el
  interface). El bit de reparse se mira ANTES de entrar: el enlace cae,
  el destino ni se mira. }
procedure BorraArbolDentro(const ADir: string);
var
  E: string;
  A: Cardinal;
begin
  A := GetFileAttributes(PChar(ADir));
  if A = INVALID_FILE_ATTRIBUTES then
    Exit; // no esta: nada que borrar
  if EsEnlace(ADir) then
  begin
    // RemoveDir sobre un junction/symlink de directorio elimina el punto
    // de reanalisis y jamas toca lo que hay al otro lado.
    SetFileAttributes(PChar(ADir), FILE_ATTRIBUTE_NORMAL);
    var CodigoEnlace: Cardinal;
    if not QuitaCarpetaConReintentos(ADir, CodigoEnlace) then
      RaiseLastOSError(CodigoEnlace);
    Exit;
  end;
  // La RTL limpiaba atributos antes de borrar (los objetos de un .git
  // vienen de solo lectura); se conserva ese contrato. Por la API y no por
  // TFile.SetAttributes: esa valida que la ruta sea un FICHERO y sobre un
  // directorio lanza "file not found" - lo cazaron round13 y round44 en la
  // primera pasada de la suite (2026-09-21).
  // ...salvo en un FICHERO: sus atributos pueden ser los de un enlace duro
  // de fuera (BorraNombre los deja como estan, +R incluido)
  for E in TDirectory.GetFiles(ADir) do
    BorraNombre(E);
  for E in TDirectory.GetDirectories(ADir) do
    BorraArbolDentro(E);
  SetFileAttributes(PChar(ADir), FILE_ATTRIBUTE_NORMAL);
  var Codigo: Cardinal;
  if not QuitaCarpetaConReintentos(ADir, Codigo) then
    RaiseLastOSError(Codigo);
end;

function CarpetasDesechables: TArray<string>;
begin
  Result := [TempFolderName, TrashFolderName];
end;

function EsCarpetaDesechable(const ANombre: string): Boolean;
begin
  Result := RutaEnLista(ANombre, CarpetasDesechables);
end;


function LugaresProtegidos: TArray<string>;
begin
  LoadSecurity;
  Result := RaicesDelModoLocal + SitiosQueNoSeTocan + [ServerDir] + CarpetasDelSistema +
    [PerfilDelUsuario] + RaicesDeLosWorkspaces;
end;

{ La ruta de un enlace se juzga por DONDE ESTA, no por adonde apunta: la ruta
  REAL del padre + el nombre. Quitar o mover un junction nunca toca lo de
  detras, y un junction en el camino no hace pasar una ruta por otra. }
function RutaDelEnlace(const AFull: string): string;
begin
  // el ultimo tramo en su nombre LARGO: tal como lo escribia el agente,
  // OTHERW~1 no era la raiz de otro workspace y se borraba (sexta
  // revision). GetLongPathName no atraviesa el enlace.
  Result := IncludeTrailingPathDelimiter(RealPath(ExtractFileDir(AFull))) +
    ExtractFileName(LongCanonical(AFull));
end;

{ El lugar protegido (tal como esta declarado) que AReal ES o CONTIENE; ''
  si ninguno. EL comparador: BorradoDenegado, ProtegidoDenegado y
  ProtegidoDentroDe. ASoloDentro: no cuenta el lugar que ES AReal, solo los
  de dentro (un repo que es la raiz del workspace no tiene nada que proteger
  por serlo; 2x de la 1.18.2). }
function LugarProtegidoEn(const AReal: string; ASoloDentro: Boolean = False): string;
var
  P, PReal: string;
begin
  Result := '';
  for P in LugaresProtegidos do
  begin
    if P.Trim = '' then
      Continue;
    // una lista NEGRA: un lugar que RealPath no sabe seguir, por su texto
    PReal := SinBarraFinal(RealDeLugar(P.Trim));
    if ASoloDentro and SameFileName(SinBarraFinal(AReal), PReal) then
      Continue;
    if EnLugar(PReal, AReal, False) then
      Exit(SinBarraFinal(P.Trim));
  end;
end;

{ .git se reconoce por su lugar declarado Y real, con alias 8.3 incluidos.
  Una unica decision para lectores, escritores y operaciones del arbol. }
function MetadatosGitDenegados(const APath: string): string;
begin
  Result := '';
  for var Ruta in TArray<string>.Create(LongCanonical(APath), LongCanonical(RealPath(APath))) do
    for var Segmento in Ruta.Split(['\', '/'], TStringSplitOptions.ExcludeEmpty) do
      if SameText(Segmento, '.git') then
        Exit(MsgFmt(SR_GUARD_GIT_METADATA_FMT, [APath]));
end;

{ Operaciones del PADRE: decidir antes de copiar/borrar/renombrar nada.
  Copiar corta al primer metadato; mover el arbol entero revisa sus enlaces.
  No poder revisar una rama no autoriza a moverla. }
function MetadatosGitEnArbolDenegados(const APath: string;
  AAdmiteArbolGit: Boolean = False): string;
var
  Motivo: string;
  Visita: TVisitaRuta;
begin
  Motivo := MetadatosGitDenegados(APath);
  if (Motivo = '') and TDirectory.Exists(APath) and not EsEnlace(APath) then
  begin
    Visita :=
      procedure(const P: string)
      begin
        if Motivo <> '' then
          Exit;
        if AAdmiteArbolGit then
        begin
          // El arbol viaja entero; un enlace de sus metadatos no abre la jaula.
          // Solo un ENLACE puede, y solo de el se pregunta: MetadatosGitDenegados
          // hace RealPath, y de cada entrada un dia de la papelera con un .git
          // de 20.000 ficheros costaba 3,8 s en cada pasada de la purga (revisor
          // de version de la 1.18.1)
          if EsEnlace(P) then
          begin
            var Meta := MetadatosGitDenegados(P);
            if Meta <> '' then
              try
                if PathDenied(P, True) <> '' then Motivo := Meta;
              except
                Motivo := Meta; // lo que no se puede juzgar tampoco se mueve
              end;
          end;
        end
        else
          Motivo := MetadatosGitDenegados(P);
      end;
    try
      RecorreSinEnlaces(APath, Visita, Visita,
        function(const P: string): Boolean
        begin
          Result := Motivo <> '';
        end, True);
    except
      // la carpeta que no se deja listar, con SU negativa (GUARD-040): esta
      // decia "es metadato de git" y mandaba a buscar un .git que no habia
      on E: Exception do
        if EsFallo(E.Message) then
          Motivo := E.Message
        else
          Motivo := MsgFmt(SR_GUARD_GIT_METADATA_FMT, [APath]);
    end;
  end;
  Result := Motivo;
end;

function BorradoDenegado(const ADir: string): string;
var
  Full, Real, Seg, P: string;
  Segs: TArray<string>;
  I: Integer;
  Desechable: Boolean;
begin
  Result := '';
  if (ADir.Trim = '') or not EsRutaAbsoluta(ADir.Trim) then
    Exit(MsgFmt(SR_BORRADO_DENEGADO_FMT, [ADir, MsgText(SF_GUARD_RUTA_VACIA_O_RELATIVA)]));
  try
    Full := SinBarraFinal(TPath.GetFullPath(ADir.Trim));
  except
    Exit(MsgFmt(SR_BORRADO_DENEGADO_FMT, [ADir, MsgText(SF_GUARD_RUTA_INVALIDA)]));
  end;
  // una unidad entera o un recurso UNC entero: "es UNC o prefijo de dispositivo"
  // por los jueces, no por "empieza por dos barras" (A25)
  if (Length(Full) <= 3) or ((EsUnc(Full) or EsPrefijoDeDispositivo(Full)) and
     (Length(Full.Substring(2).Split(['\'], TStringSplitOptions.ExcludeEmpty)) <= 2)) then
    Exit(MsgFmt(SR_BORRADO_DENEGADO_FMT, [ADir, MsgText(SF_GUARD_UNIDAD_O_RECURSO_ENTERO)]));
  // la ruta REAL del padre + el nombre (ver la nota de la interface)
  Real := RutaDelEnlace(Full);
  // (1) lista blanca
  Segs := Real.Split(['\', '/'], TStringSplitOptions.ExcludeEmpty);
  Desechable := False;
  for I := 0 to High(Segs) do
  begin
    Seg := Segs[I];
    // Tercera barrera (David, 25-sep-2026): el segmento que habilita el
    // borrado EMPIEZA POR __, sea cual sea la lista: una entrada futura con
    // nombre normal, o una ruta mal calculada, no habilita nada.
    if not Seg.StartsWith('__') then
      Continue;
    if (I < High(Segs)) and EsCarpetaDesechable(Seg) then
      Desechable := True // DENTRO de una desechable, nunca la carpeta misma
    else if EsCarpetaDescarga(Seg) then
      Desechable := True;
  end;
  if not Desechable then
    Exit(MsgFmt(SR_BORRADO_DENEGADO_FMT, [ADir,
      MsgFmt(SF_GUARD_NO_DENTRO_DESECHABLE_FMT,
      [string.Join(', ', CarpetasDesechables)])]));
  // (2) lista negra: ni ser ni contener un lugar protegido
  P := LugarProtegidoEn(Real);
  // ...y por la ruta real de la carpeta MISMA cuando no es un enlace: en el
  // AppContainer de delphi_test el padre no se deja abrir y RutaDelEnlace se
  // queda con su texto (ABCDEF~1) mientras el lugar protegido se resuelve
  // entero (abcdefghij): dos formas de la misma carpeta, y la lista negra
  // fallaba ABIERTA (medido el 14-oct con la suite de unidad en el
  // contenedor). Cualquiera de las dos formas niega
  if (P = '') and not EsEnlace(Full) then
    P := LugarProtegidoEn(SinBarraFinal(RealPath(Full)));
  if P <> '' then
    Exit(MsgFmt(SR_BORRADO_DENEGADO_FMT, [ADir, MsgFmt(SF_GUARD_CONTIENE_LUGAR_PROTEGIDO_FMT, [P])]));
  // (3) los metadatos git, lo ULTIMO: es lo unico que recorre el arbol, y
  // un borrado que las listas ya niegan no lo paga (negar C:\Windows lo
  // recorria entero; 2g de la 1.18.x). Un repositorio ENTERO (su .git
  // dentro) se borra como se mueve: el arbol va entero y un enlace de sus
  // metadatos no abre la jaula (AAdmiteArbolGit); que ADir SEA un .git, o
  // este dentro de uno, sigue negado. Sin esto un repo mandado a la papelera
  // no se iba nunca: ni purge=true ni la purga de 15 dias, que ademas se
  // cortaba ahi (medido el 10-oct-2026, en la 1.18.0)
  Result := MetadatosGitEnArbolDenegados(Full, True);
end;

function EsEnlace(const P: string): Boolean;
begin
  Result := Lsp.Reparse.EsEnlace(P);
end;

function EnLugarSinEnlaces(const APath, ALugar: string): Boolean;
var
  Lugar, P: string;
begin
  Result := False;
  if (APath.Trim = '') or (ALugar.Trim = '') then
    Exit;
  try
    Lugar := FormaLarga(ALugar.Trim); // con su separador final
    P := SinBarraFinal(LongCanonical(APath.Trim));
    if not RutaDentroDe(Lugar, P) then
      Exit;
    // de APath hacia arriba hasta el lugar, sin el
    for var D in Ancestros(P) do
    begin
      if Length(IncludeTrailingPathDelimiter(D)) <= Length(Lugar) then
        Break;
      if EsEnlace(D) then
        Exit;
    end;
    Result := True;
  except
    Result := False; // una ruta que no parsea no esta en ningun sitio
  end;
end;

function EntradasDeCarpeta(const ADir: string): TArray<string>;
var
  FD: TWin32FindData;
  H: THandle;
  Err: Cardinal;
begin
  Result := TDirectory.GetFileSystemEntries(ADir);
  if Length(Result) > 0 then
    Exit;
  // vacio de la RTL = vacia DE VERDAD o FindFirst fallo: lo dice Windows
  // (una carpeta vacia que no es raiz da '.' y '..')
  // (el MISMO patron que FindFirst en WalkThroughDirectory)
  H := FindFirstFile(PChar(IncludeTrailingPathDelimiter(ADir) + '*'), FD);
  if H <> INVALID_HANDLE_VALUE then
  begin
    Winapi.Windows.FindClose(H);
    Exit;
  end;
  Err := GetLastError;
  if (Err <> ERROR_FILE_NOT_FOUND) and (Err <> ERROR_NO_MORE_FILES) then
    raise EInOutError.Create(MsgFmt(SR_GUARD_CARPETA_ILEGIBLE_FMT,
      [ADir, SysErrorMessage(Err).Trim]));
end;

function CarpetaVacia(const ADir: string): Boolean;
begin
  try
    Result := TDirectory.Exists(ADir) and (Length(EntradasDeCarpeta(ADir)) = 0);
  except
    Result := False;
  end;
end;

procedure RecorreSinEnlaces(const ADir: string; const AVisita: TVisitaRuta;
  const AAlEnlace: TVisitaRuta; const AOmite: TOmiteAlCopiar;
  AFallaSiIlegible: Boolean; const AAlIlegible: TVisitaRuta);
var
  Entradas: TArray<string>;
  E: string;
begin
  try
    Entradas := EntradasDeCarpeta(ADir);
  except
    // una carpeta que no se deja listar: quien puede reclamarla (en su casa)
    // lo hace aqui y se reintenta UNA vez; si no, se salta o se lanza
    if Assigned(AAlIlegible) then
    begin
      try
        AAlIlegible(ADir);
      except
      end;
      try
        Entradas := EntradasDeCarpeta(ADir);
      except
        if AFallaSiIlegible then
          raise;
        Exit;
      end;
    end
    else
    begin
      if AFallaSiIlegible then
        raise;
      Exit; // quien no pide cierre tolera ramas ilegibles
    end;
  end;
  for E in Entradas do
  begin
    if Assigned(AOmite) and AOmite(E) then
      Continue;
    if EsEnlace(E) then
    begin
      // ni se visita ni se entra: lo de detras no es de este arbol. Quien
      // necesita saber que esta aqui, lo recibe.
      if Assigned(AAlEnlace) then
        try
          AAlEnlace(E);
        except
        end;
      Continue;
    end;
    try
      AVisita(E);
    except
      // una entrada que no se deja tocar no para las demas
    end;
    if TDirectory.Exists(E) and (not Assigned(AOmite) or not AOmite(E)) then
      RecorreSinEnlaces(E, AVisita, AAlEnlace, AOmite, AFallaSiIlegible, AAlIlegible);
  end;
end;

{ LA regla de enlaces de la copia: se sigue solo si lo de detras se puede
  LEER en esta sesion. Dos veredictos de la MISMA puerta de lectura: el
  destino real (una referencia, la zona de biblioteca) o el camino por el
  enlace (un enlace a tus propias raices). Ninguno abre nada que no se lea
  ya. La usan CopiaArbol y CopiaDenegada: lo que se mira es lo que se copia. }
function EnlaceLegible(const P: string): Boolean;
begin
  Result := (ReadPathDenied(RealPath(P)) = '') or (ReadPathDenied(P) = '');
end;

function EnlaceAjenoEn(const ADir: string; AEscribe: Boolean;
  const AOmite: TOmiteAlCopiar): string;
var
  // rutas REALES ya recorridas, por ClaveDeRuta: corta los ciclos de enlaces
  Vistos: TDictionary<string, Boolean>;
  Ajeno, Fallo: string;
  // una variable, no una rutina anidada: la captura el aviso de enlace del
  // recorredor (E2555) y por ella se llama a si misma detras de un enlace
  Recorre: TProc<string>;
begin
  Ajeno := '';
  Fallo := '';
  Vistos := TDictionary<string, Boolean>.Create;
  try
    Vistos.Add(ClaveDeRuta(SinBarraFinal(RealPath(ADir))), True);
    Recorre :=
      procedure(D: string)
      begin
        RecorreSinEnlaces(D,
          procedure(const APath: string)
          begin
          end,
          procedure(const APath: string)
          var
            Real: string;
            Sigue: Boolean;
          begin
            if (Ajeno <> '') or (Fallo <> '') then
              Exit;
            // lo de detras del enlace, por la puerta que toca: la del
            // escritor sobre su ruta real, o la regla de lectura del copiador.
            // Lo que no se deja juzgar (una ruta que no parsea) NO se sigue:
            // el recorredor se traga lo que lance este aviso, y tragado
            // seria admitido
            try
              if AEscribe then
                Sigue := EscrituraDenegada(RealPath(APath)) = ''
              else
                Sigue := EnlaceLegible(APath);
            except
              Sigue := False;
            end;
            if not Sigue then
            begin
              Ajeno := APath;
              Exit;
            end;
            // detras de un enlace admitido puede haber otro: se mira tambien.
            // El recorredor se traga lo que lance este aviso: un GUARD-040 de
            // ahi dentro se guarda y se relanza al final
            Real := SinBarraFinal(RealPath(APath));
            if TDirectory.Exists(Real) and not Vistos.ContainsKey(ClaveDeRuta(Real)) then
            begin
              Vistos.Add(ClaveDeRuta(Real), True);
              try
                Recorre(Real);
              except
                on E: Exception do
                  Fallo := E.Message;
              end;
            end;
          end,
          AOmite, True);
      end;
    Recorre(ADir);
  finally
    Vistos.Free;
  end;
  if Fallo <> '' then
    raise EInOutError.Create(Fallo);
  Result := Ajeno;
end;

{ Recursive file walk that TOLERATES unreadable subdirectories. Delphi's
  TDirectory.GetFiles(soAllDirectories) aborts the WHOLE enumeration on the
  first failure - measured on the Android NDK, whose deep paths exceed the
  classic limit and killed an entire delphi_list. One bad folder must never
  hide the rest of the tree. }
function WalkFiles(const ADir: string; const AMasks: TArray<string>;
  AConPapelera, ARecursivo: Boolean; const AAlEntrar: TVisitaRuta;
  AIncluyeEnlacesFuera: Boolean; const AOmite: TOmiteAlCopiar): TArray<string>;
var
  Acc: TStringList;
  // rutas REALES de los enlaces ya seguidos, por ClaveDeRuta: corta ciclos. Era
  // un TStringList sin mayusculas (AnsiCompareText): tomaba por la misma dos
  // carpetas que NTFS separa (ss y la eszett) y se saltaba la segunda (V82)
  Vistos: TDictionary<string, Boolean>;
  // Cada fichero UNA vez: dos mascaras que se solapan ("*;*.pas") o la
  // pasada de la papelera (mascara + '-*', que "*" ya cubre) lo contaban dos
  // veces - total 7 para 3 ficheros (quinta revision). Acc guarda el orden
  // del paseo; esto solo responde "ya esta", en O(1): un arbol como el NDK
  // tiene decenas de miles de ficheros.
  Unicos: TDictionary<string, Boolean>;

  procedure Anade(const F: string);
  begin
    if not Unicos.ContainsKey(ClaveDeRuta(F)) then
    begin
      Unicos.Add(ClaveDeRuta(F), True);
      Acc.Add(F);
    end;
  end;

  procedure Recurse(const D: string);
  var
    F, Sub: string;
  begin
    if Assigned(AAlEntrar) then
      AAlEntrar(D);
    try
      // Un enlace (de fichero o de carpeta) se sigue solo si lo de detras se
      // puede LEER: EnlaceLegible, la regla del copiador. Un junction a
      // cualquier sitio ensenaba, buscaba y empaquetaba lo que la puerta de
      // lectura no deja leer (auditoria 25-sep-2026).
      for var Mascara in AMasks do
        for F in TDirectory.GetFiles(D, Mascara, TSearchOption.soTopDirectoryOnly) do
          // AIncluyeEnlacesFuera: la puerta del build quiere VER un fichero que
          // es un enlace cuyo destino sale (dcc lo seguiria), no saltarlo como
          // el copiador; lo juzga quien llama (ReadPathDenied). V3 de la 1.23
          if not EsEnlace(F) or EnlaceLegible(F) or AIncluyeEnlacesFuera then
            Anade(F);
    except
      // unreadable folder: skip its files, still try its children
    end;
    // Dentro de la papelera cada copia lleva el sello de hora DETRAS de la
    // extension ("UFicha.pas-215825250"), asi que la mascara "*.pas" no casa
    // con ella. Resultado medido el 2026-09-20: includetrash=true ensenaba
    // las copias de seguridad -que SI conservan su nombre- y escondia justo
    // lo BORRADO, que es lo unico que ese flag promete. La mascara se abre
    // solo aqui y solo cuando lo piden: los demas que llaman no se enteran.
    if AConPapelera and EnPapelera(D) then
    try
      for var Mascara in AMasks do
        for F in TDirectory.GetFiles(D, MascaraDeCopias(Mascara),
          TSearchOption.soTopDirectoryOnly) do
          if not EsMarcaDeDueno(F) and (not EsEnlace(F) or EnlaceLegible(F)) then
            Anade(F);
    except
      // idem
    end;
    // El renderizador solo indexa hermanos; los otros lectores recorren.
    if not ARecursivo then
      Exit;
    try
      for Sub in TDirectory.GetDirectories(D) do
      begin
        if EsEnlace(Sub) then
        begin
          if not EnlaceLegible(Sub) then
            Continue;
          var RealSub := ClaveDeRuta(RealPath(Sub));
          if Vistos.ContainsKey(RealSub) then
            Continue; // un ciclo de enlaces
          Vistos.Add(RealSub, True);
        end;
        // Un vault alcanzado por un camino que no lo nombra (detras de un
        // enlace que se sigue) no se recorre: delphi_list ensenaba sus notas
        // (revisor del paisaje de la 1.27, medido). El que el texto nombra lo
        // cuenta como oculto quien llama, por InVault
        if not InVault(Sub) and EnUnVault(Sub) then
          Continue;
        // La papelera se purga solo despues de admitir la lectura del enlace.
        if EsNombreDePapelera(TPath.GetFileName(Sub)) then
          PurgaAlPasar(Sub);
        // ...y lo que quien llama omite no se recorre (despues de la purga:
        // la papelera se purga al pasar aunque no se entre en ella)
        if Assigned(AOmite) and AOmite(Sub) then
          Continue;
        Recurse(Sub);
      end;
    except
      // cannot enumerate children: nothing else to do here
    end;
  end;

begin
  if ReadPathDenied(ADir) <> '' then
    Exit(nil);
  Acc := TStringList.Create;
  Vistos := TDictionary<string, Boolean>.Create;
  Unicos := TDictionary<string, Boolean>.Create;
  try
    Vistos.Add(ClaveDeRuta(RealPath(ADir)), True);
    Recurse(ADir);
    Result := Acc.ToStringArray;
  finally
    Unicos.Free;
    Vistos.Free;
    Acc.Free;
  end;
end;

function WalkFiles(const ADir, AMask: string;
  AConPapelera: Boolean): TArray<string>;
begin
  Result := WalkFiles(ADir, [AMask], AConPapelera);
end;

{ ADestino cae DENTRO de AOrigen (o es el), por las rutas REALES. Con
  AOrigenEsElEnlace, el origen por SU ruta (RutaDelEnlace), no la de detras:
  un MOVE renombra el enlace mismo, y por su destino una junction a un
  antepasado caia "dentro de si misma" y no se podia ni borrar ni mover
  (septima revision). Una copia lee a traves del enlace: la real. }
function RutaParaComparar(const ARuta: string; AEsElEnlace: Boolean = False): string;
begin
  if AEsElEnlace then
    Result := RutaDelEnlace(SinBarraFinal(TPath.GetFullPath(ARuta)))
  else
    Result := RealPath(SinBarraFinal(ARuta));
  Result := IncludeTrailingPathDelimiter(Result);
end;

function CaeDentro(const AOrigenResuelto, ADestinoResuelto: string): Boolean;
begin
  Result := RutaDentroDe(AOrigenResuelto, ADestinoResuelto);
end;

function DentroDeSiMismo(const AOrigen, ADestino: string;
  AOrigenEsElEnlace: Boolean = False): Boolean;
begin
  Result := CaeDentro(RutaParaComparar(AOrigen, AOrigenEsElEnlace),
    RutaParaComparar(ADestino));
end;

function MismaEntrada(const AOrigen, ADestino: string): Boolean;
begin
  try
    Result := SameFileName(RutaParaComparar(AOrigen, True), RutaParaComparar(ADestino, True));
  except
    Result := False;
  end;
end;

{ LA regla de seguir un enlace al COPIAR, para el copiador (CopiaArbol) y
  para quien mira antes lo que se va a copiar (CopiaDenegada): legible, y que
  no lleve al DESTINO - una junction a un antepasado del destino copiaba la
  copia dentro de si misma, con una ruta real nueva en cada vuelta, hasta
  agotar la ruta (decima revision). }
function SeSigueAlCopiar(const P, ADestino: string): Boolean;
begin
  // el enlace RESUELTO (RealPath: lo que hay detras), no su propio nombre
  Result := EnlaceLegible(P) and not DentroDeSiMismo(P, ADestino);
end;

procedure CopiaArbol(const AOrigen, ADestino: string; AConservaAtributos: Boolean;
  out ANoSeguidos: TArray<string>; ASigueEnlaces: Boolean;
  const AOmite: TOmiteAlCopiar; const AAlListar: TListaCopia);
var
  Vistos: TDictionary<string, Boolean>; // las rutas REALES ya copiadas, por ClaveDeRuta
  NoSeg: TStringList;

  function SeSigue(const P: string): Boolean;
  begin
    Result := ASigueEnlaces and SeSigueAlCopiar(P, ADestino);
    if not Result then
      NoSeg.Add(P);
  end;

  procedure Copia(const O, D: string; ADetras: Boolean);
  var
    E, Nombre: string;
  begin
    // la ruta REAL ya copiada no se vuelve a copiar: corta un bucle de enlaces
    if Vistos.ContainsKey(ClaveDeRuta(RealPath(O))) then
      Exit;
    Vistos.Add(ClaveDeRuta(RealPath(O)), True);
    if not Assigned(AAlListar) then
      CrearCarpeta(D);
    // por EL lector que distingue "vacia" de "no se deja listar"
    // (EntradasDeCarpeta, 2g de la 1.18.4): GetFiles/GetDirectories daban
    // VACIA una carpeta que Windows no deja listar y la copia la dejaba vacia
    // sin decirlo (medido en System.IOUtils:1525). Aqui falla cerrado: lo que
    // no se puede mirar no se copia, y quien llama lo dice
    for E in EntradasDeCarpeta(O) do
      if not TDirectory.Exists(E) then
      begin
        // un ENLACE DURO con un nombre que la sesion no lee tampoco se copia:
        // copiarlo era leer el de fuera (medido el 20-oct-2026: la copia de
        // una carpeta salia con sus bytes). Va con los no seguidos
        if EnlaceDuroIlegible(E) <> '' then
          NoSeg.Add(E)
        else if (not EsEnlace(E) or SeSigue(E)) and
           (not Assigned(AOmite) or not AOmite(E)) then
          if Assigned(AAlListar) then
            AAlListar(E, TPath.Combine(D, TPath.GetFileName(E)), False, ADetras or EsEnlace(E))
          // la de seguridad de un move conserva los atributos; la del agente
          // (copy=true) va sin el +R heredado
          else if AConservaAtributos then
            TFile.Copy(E, TPath.Combine(D, TPath.GetFileName(E)), False)
          else
            CopiaNuestra(E, TPath.Combine(D, TPath.GetFileName(E)));
      end
      else
      begin
        Nombre := TPath.GetFileName(E);
        // una papelera de dentro no es contenido: tampoco en la copia de
        // seguridad de un move, que la duplicaba (viaja con la carpeta; V21)
        if EsNombreDePapelera(Nombre) then
          Continue;
        // un VAULT (de cualquier workspace) es de las tools vault_*: no se
        // copia, y se dice con lo no seguido (el de OTRO workspace salia
        // entero en la copia; octava revision). Por su ruta REAL tambien: detras
        // de un enlace que se sigue el texto no lo nombra, y delphi_move
        // copy=true metia sus notas en la jaula (revisor del paisaje de la
        // 1.27, medido)
        if EnUnVault(E) then
        begin
          NoSeg.Add(E);
          Continue;
        end;
        if (not EsEnlace(E) or SeSigue(E)) and
           (not Assigned(AOmite) or not AOmite(E)) and
           (not Assigned(AAlListar) or
            AAlListar(E, TPath.Combine(D, Nombre), True, ADetras or EsEnlace(E))) then
          Copia(E, TPath.Combine(D, Nombre), ADetras or EsEnlace(E));
      end;
  end;

begin
  // Dentro de si misma se copiaria sin fin: el destino recien creado sale
  // en el listado del origen, con una ruta real nueva en cada vuelta.
  if DentroDeSiMismo(AOrigen, ADestino) then
    raise Exception.Create(MsgFmt(SR_COPIA_DENTRO_DE_SI_FMT, [ADestino, AOrigen]));
  Vistos := TDictionary<string, Boolean>.Create;
  NoSeg := TStringList.Create;
  try
    Copia(SinBarraFinal(AOrigen), SinBarraFinal(ADestino), EsEnlace(SinBarraFinal(AOrigen)));
    ANoSeguidos := NoSeg.ToStringArray;
  finally
    NoSeg.Free;
    Vistos.Free;
  end;
end;

{ "Git dentro" (V19; David, 17-oct-2026: "se copia TODO, git incluido, la
  historia sigue en ese proyecto, siempre y cuando su git este dentro de la
  carpeta del proyecto a copiar"): cada repo de lo que se copia -una carpeta
  con su .git, carpeta o fichero- tiene su gitdir, su comun y su arbol de
  trabajo DENTRO de AOrigen. Un worktree o un submodulo suelto (su .git es un
  fichero que apunta a los metadatos de OTRO repo) o un core.worktree que sale
  dejarian dos carpetas trabajando sobre lo mismo. El juez es git
  (DameRepoDeCarpeta, sin cache); sin el, o si no lo reconoce, un .git no se
  copia (GUARD-033). Lo que se mira es lo que CopiaArbol copiaria (AAlListar,
  las mismas reglas): un .git al que se llega por un enlace que la copia sigue
  no esta dentro. '' = se puede. }
function GitDeLaCopiaDenegado(const AOrigen, ADestino: string): string;
var
  Origen, OrigenReal, Motivo: string;
  Repos, NoSeg: TArray<string>;

  function Dentro(const ADir: string): Boolean;
  begin
    Result := EnLugar(ADir, Origen) or EnLugar(ADir, OrigenReal);
  end;

begin
  Result := '';
  if not TDirectory.Exists(AOrigen) then
    Exit;
  Origen := SinBarraFinal(TPath.GetFullPath(AOrigen));
  OrigenReal := SinBarraFinal(RealPath(Origen));
  Motivo := '';
  Repos := [];
  // las reglas de la copia del agente (copy=true en delphi_move): sin
  // atributos y siguiendo los enlaces legibles
  CopiaArbol(Origen, ADestino, False, NoSeg, True, nil,
    function(const O, D: string; AEsCarpeta, ADetras: Boolean): Boolean
    begin
      Result := Motivo = '';
      if not Result then
        Exit;
      // un .git (carpeta o fichero) es un repo: se apunta y no se baja; detras
      // de un enlace que la copia sigue, no esta dentro
      if SameFileName(TPath.GetFileName(O), '.git') then
      begin
        if ADetras then
          Motivo := MsgFmt(SR_MOVE_COPIA_GIT_FUERA_FMT, [TPath.GetDirectoryName(O),
            MsgText(SF_MOVE_GIT_DETRAS_DE_ENLACE), RealPath(O)])
        else
          Repos := Repos + [TPath.GetDirectoryName(O)];
        Exit(False);
      end;
      // ...y un enlace que lleva DENTRO de unos metadatos (su ruta real tiene
      // un .git): GUARD-033, como siempre
      if ADetras and (MetadatosGitDenegados(O) <> '') then
      begin
        Motivo := MetadatosGitDenegados(O);
        Exit(False);
      end;
    end);
  if Motivo <> '' then
    Exit(Motivo);
  for var R in Repos do
  begin
    var GitDir, Comun, Raiz: string;
    if not Assigned(DameRepoDeCarpeta) or not DameRepoDeCarpeta(R, GitDir, Comun, Raiz) then
      Exit(MsgFmt(SR_GUARD_GIT_METADATA_FMT, [TPath.Combine(R, '.git')]));
    if not Dentro(GitDir) then
      Exit(MsgFmt(SR_MOVE_COPIA_GIT_FUERA_FMT, [R, MsgText(SF_MOVE_GIT_METADATOS), GitDir]));
    if not Dentro(Comun) then
      Exit(MsgFmt(SR_MOVE_COPIA_GIT_FUERA_FMT, [R, MsgText(SF_MOVE_GIT_METADATOS), Comun]));
    if (Raiz <> '') and not Dentro(Raiz) then
      Exit(MsgFmt(SR_MOVE_COPIA_GIT_FUERA_FMT, [R, MsgText(SF_MOVE_GIT_ARBOL), Raiz]));
  end;
end;

function CopiaDenegada(const AOrigen, ADestino: string): string;
begin
  if DentroDeSiMismo(AOrigen, ADestino) then
    Exit(MsgFmt(SR_COPIA_DENTRO_DE_SI_FMT, [ADestino, AOrigen]));
  // lo que ES metadato de git (o esta dentro de un .git) no se copia
  Result := MetadatosGitDenegados(AOrigen);
  if Result <> '' then
    Exit;
  // ...y adonde va: lo copiado llega alli entero, como al mover (2r). Antes
  // de recorrer el origen: un arbol grande se niega sin recorrerlo
  Result := ProtegidoDenegado(ADestino, True);
  if Result <> '' then
    Exit;
  try
    Result := GitDeLaCopiaDenegado(AOrigen, ADestino);
  except
    // lo que no se deja listar (GUARD-040) no se copia: con SU negativa
    on E: Exception do
      Result := IfThen(EsFallo(E.Message), E.Message, MsgFmt(SR_GUARD_GIT_METADATA_FMT, [AOrigen]));
  end;
end;

procedure PurgaAlPasar(const ATrashDir: string);
begin
  try
    // LA pregunta de escritura (solo lectura + PathDenied), no rehecha a mano
    // (revisor de 9a9c4cc: era su cuerpo, a una llamada)
    if EscrituraDenegada(ATrashDir) <> '' then
      Exit;
    PurgeOldBackups(ATrashDir);
  except
    // purgar al pasar nunca rompe el listado que pasaba
  end;
end;

{ Un dia de la papelera que la purga no pudo quitar lo DICE en el log, una
  vez (David, 11-oct-2026: el juicio que lo retiene se queda; la papelera la
  vacia el operador, y tiene que saber cual y por que). Se reintentaba callado
  en cada purga (revisor propio del punto 2 de la 1.18.1). }
procedure AvisaDiaQueSeQueda(const ADia, AMotivo: string);
begin
  TMonitor.Enter(GDiasQueSeQuedan);
  try
    if GDiasQueSeQuedan.ContainsKey(ADia) then
      Exit;
    GDiasQueSeQuedan.Add(ADia, True);
  finally
    TMonitor.Exit(GDiasQueSeQuedan);
  end;
  try
    TLogger.Warning(MsgFmt(SL_PAPELERA_DIA_SE_QUEDA_FMT, [ADia, AMotivo]));
  except
    // el aviso nunca rompe la purga, que nunca rompe una edicion
  end;
end;

procedure PurgeOldBackups(const ADir: string);
const
  RETENTION_DAYS = 15;
var
  D, Limit: string;
begin
  try
    Limit := NombreDeDia(Now - RETENTION_DAYS);
    for D in TDirectory.GetDirectories(ADir) do
      if EsCarpetaDeDia(TPath.GetFileName(D)) and
         (TPath.GetFileName(D) < Limit) then
      try
        BorraArbol(D); // sin cruzar enlaces: el de aqui abajo
      except
        // un dia que no se deja borrar (algo abierto dentro, lo que el guard
        // niegue) no frena a los demas: con un solo try para todo el bucle
        // el primero cortaba la purga y los dias de detras se quedaban para
        // siempre (medido el 10-oct-2026 con un repo en la papelera). Y se
        // queda DICIENDOLO, una vez
        on E: Exception do
          AvisaDiaQueSeQueda(D, E.Message);
      end;
  except
    // purging must never break an edit
  end;
end;

{ Le da a ADir, como UN objeto y SIN propagar, una DACL PROTEGIDA con UNA sola
  ACE de permitir para la cuenta del servidor (el SID de su token): lo justo
  para que su casa se liste y se borre (list, traverse, read-attributes,
  delete-child, DELETE, SYNCHRONIZE). Nada para Todos, nada heredable.
  SetFileSecurity fija ESTE objeto y NO recorre el arbol -al reves que
  SetNamedSecurityInfo, que propaga la herencia a los hijos: un recorrido de
  Windows que ademas podria tocar lo de detras de un enlace-; los arboles solo
  los recorre RecorreSinEnlaces, que nunca cruza un enlace, y ADir aqui nunca es
  uno. Medido 26-oct-2026: deja D:P(A;;0x1100e1;;;<dueno>), listable y borrable,
  sin Everyone y sin propagar (no cruza una junction de dentro, medido). No
  lanza: lo que no se pueda (un OWNER_RIGHTS que le quita el WRITE_DAC al dueno)
  lo dira BorraArbol despues. }
procedure ReclamaDaclHeredada(const ADir: string);
const
  ACL_REVISION = 2;
  // lo justo para que el servidor liste y borre lo suyo (medido: sin SYNCHRONIZE
  // la RTL no abre ni para listar ni para borrar) = $1100E1
  RECLAMO_MASK = FILE_LIST_DIRECTORY or FILE_TRAVERSE or FILE_READ_ATTRIBUTES or
    FILE_DELETE_CHILD or $00010000 {DELETE} or SYNCHRONIZE;
var
  Buf: TArray<Byte>;
  SD: TSecurityDescriptor;
  Acl: array[0 .. 127] of Byte;
begin
  // el SID de la cuenta del servidor (dueno de lo que dejo delphi_test en la
  // casa), por EL lector del token (Lsp.Sandbox)
  var Sid := SidDelProceso(Buf);
  if Sid = nil then
    Exit;
  if not InitializeAcl(PACL(@Acl)^, SizeOf(Acl), ACL_REVISION) then
    Exit;
  // UNA ACE de permitir para el dueno; NUNCA una DACL nula (control total a
  // todos) ni una para Todos, NUNCA heredable
  if not AddAccessAllowedAce(PACL(@Acl)^, ACL_REVISION, RECLAMO_MASK, Sid) then
    Exit;
  InitializeSecurityDescriptor(@SD, SECURITY_DESCRIPTOR_REVISION);
  SetSecurityDescriptorDacl(@SD, True, PACL(@Acl), False);
  SetSecurityDescriptorControl(@SD, SE_DACL_PROTECTED, SE_DACL_PROTECTED);
  // SetFileSecurity, NO SetNamedSecurityInfo: fija ESTE objeto, no recorre el arbol
  SetFileSecurityW(PChar(ADir), DACL_SECURITY_INFORMATION, @SD);
end;

procedure ReclamaArbol(const ADir: string);
begin
  // SOLO la casa del servidor, por su nombrador (no la jaula del agente): el
  // reclamo ESCRIBE seguridad, y solo sobre lo nuestro. test_paisaje lo vigila.
  if not EnLugarSinEnlaces(ADir, ServerTempDir('')) then
    Exit;
  RecorreSinEnlaces(ADir,
    procedure(const APath: string)
    begin
    end,
    nil, nil, False,
    procedure(const APath: string)
    begin
      // nunca un enlace (SetNamedSecurityInfo sobre un junction etiquetaria su
      // destino): el recorredor ya no entra en enlaces, y aqui tambien se mira
      if not EsEnlace(APath) then
        ReclamaDaclHeredada(APath);
    end);
end;

procedure BorraArbol(const ADir: string);
var
  Motivo: string;
begin
  // El guard ANTES de tocar nada, y una sola vez: los hijos de algo aprobado
  // estan dentro de ello (misma lista blanca) y si hubiera un lugar
  // protegido debajo, el padre ya lo CONTENDRIA y se habria denegado.
  Motivo := BorradoDenegado(ADir);
  if Motivo <> '' then
    raise Exception.Create(Motivo);
  // ...y lo NUESTRO, fuera, como en MueveArbol: con un DelphiLSP vivo en la
  // carpeta se borraba el contenido y quedaba el cascaron (29-sep-2026)
  SueltaLoNuestroBajo(ADir);
  try
    BorraArbolDentro(ADir);
  finally
    YaNoSeQuita(ADir);
  end;
end;

{ Un lugar protegido en una negativa: se nombra solo lo que esta sesion ya
  puede leer (la nota, en la interface de ProtegidoDenegado); si no, "un
  sitio protegido". Lo usan ProtegidoDenegado y ProtegidoDentroDe. }
function NombreDeLugarProtegido(const AP: string): string;
begin
  if ReadPathDenied(AP) = '' then
    Result := '"' + AP + '"'
  else
    Result := MsgText(SN_LUGAR_PROTEGIDO);
end;

function ProtegidoDenegado(const ADir: string; AComoDestino: Boolean): string;
var
  Full, P: string;
begin
  Result := '';
  try
    Full := SinBarraFinal(TPath.GetFullPath(ADir.Trim));
  except
    Exit; // una ruta que no parsea es cosa de PathDenied
  end;
  Result := MetadatosGitEnArbolDenegados(Full, True);
  if Result <> '' then
    Exit;
  P := LugarProtegidoEn(RutaDelEnlace(Full));
  if P = '' then
    Exit;
  P := NombreDeLugarProtegido(P);
  if AComoDestino then
    Result := MsgFmt(SR_MUDANZA_DESTINO_PROTEGIDO_FMT, [ADir, P])
  else
    Result := MsgFmt(SR_MUDANZA_PROTEGIDA_FMT, [ADir, P]);
end;

function ProtegidoDentroDe(const ADir: string): string;
var
  Full: string;
begin
  Result := '';
  try
    Full := SinBarraFinal(TPath.GetFullPath(ADir.Trim));
  except
    Exit; // una ruta que no parsea es cosa de PathDenied
  end;
  Result := LugarProtegidoEn(RutaDelEnlace(Full), True);
  if Result <> '' then
    Result := NombreDeLugarProtegido(Result);
end;

function MovidoDenegado(const AOrigen, ADestino: string): string;
var
  UO, UD: string;
begin
  // LA pregunta de escribir, con el modo de solo lectura: el juez de lo que
  // mueve MueveArbol y MezclaArbol no lo preguntaba (V220)
  Result := EscrituraDenegada(AOrigen);
  if Result <> '' then
    Exit;
  Result := EscrituraDenegada(ADestino);
  if Result <> '' then
    Exit;
  Result := ProtegidoDenegado(AOrigen);
  if Result <> '' then
    Exit;
  // ...y adonde va: lo de dentro llega alli entero (2r)
  Result := ProtegidoDenegado(ADestino, True);
  if Result <> '' then
    Exit;
  // (el mismo con otras mayusculas no esta dentro: es renombrarlo)
  if DentroDeSiMismo(AOrigen, ADestino, True) and not MismaEntrada(AOrigen, ADestino) then
    Exit(MsgFmt(SR_COPIA_DENTRO_DE_SI_FMT, [ADestino, AOrigen]));
  // la unidad REAL de cada lado: un junction en el camino no la disfraza
  try
    UO := ExtractFileDrive(RutaDelEnlace(SinBarraFinal(
      TPath.GetFullPath(AOrigen))));
    UD := ExtractFileDrive(RealPath(ADestino));
  except
    Exit(MsgFmt(SR_GUARD_RUTA_INVALIDA_FMT, [AOrigen]));
  end;
  if not SameText(UO, UD) then
    Result := MsgFmt(SR_MUDANZA_OTRA_UNIDAD_FMT, [AOrigen, ADestino]);
end;

var
  GSoltadores: TArray<TSoltadorDeCarpeta>;

procedure RegistraSoltadorDeCarpeta(ASoltador: TSoltadorDeCarpeta);
begin
  if not Assigned(ASoltador) then
    Exit;
  SetLength(GSoltadores, Length(GSoltadores) + 1);
  GSoltadores[High(GSoltadores)] := ASoltador;
end;

procedure AvisaALosSoltadores(const ACarpeta: string; AEmpieza: Boolean);
var
  I: Integer;
begin
  for I := 0 to High(GSoltadores) do
    try
      GSoltadores[I](ACarpeta, AEmpieza);
    except
      // lo que no se suelte deja fallar la mudanza, entera, como antes
    end;
end;

procedure SueltaLoNuestroBajo(const ACarpeta: string);
begin
  AvisaALosSoltadores(ACarpeta, True);
end;

procedure YaNoSeQuita(const ACarpeta: string);
begin
  AvisaALosSoltadores(ACarpeta, False);
end;

procedure MueveArbol(const AOrigen, ADestino: string);
var
  Motivo: string;
begin
  // El guard ANTES de tocar nada, como en BorraArbol.
  Motivo := MovidoDenegado(AOrigen, ADestino);
  if Motivo <> '' then
    raise Exception.Create(Motivo);
  // ...y lo NUESTRO, fuera: una mudanza que el guard niega no suelta nada
  SueltaLoNuestroBajo(AOrigen);
  try
  // un RENOMBRE (MoveFileEx sin MOVEFILE_COPY_ALLOWED), ni TDirectory.Move:
  // en la misma unidad renombra de un golpe; si no puede, devuelve False sin
  // haber tocado nada. Entre unidades falla con ERROR_NOT_SAME_DEVICE: el
  // mismo rechazo, por si la unidad llego disfrazada (un punto de montaje).
  // MoveFile a secas no vale: a una CARPETA no la copia, pero un fichero lo
  // copia y lo borra entre unidades (medido el 3-nov-2026, J4 del revisor del
  // paisaje de la 1.27), y MezclaArbol y delphi_move mueven ficheros
  var Codigo: Cardinal;
  if not RenombraConReintentos(SinBarraFinal(AOrigen), SinBarraFinal(ADestino), 0, Codigo) then
  begin
    if Codigo = ERROR_NOT_SAME_DEVICE then
      raise Exception.Create(MsgFmt(SR_MUDANZA_OTRA_UNIDAD_FMT, [AOrigen, ADestino]));
    RaiseLastOSError(Codigo);
  end;
  finally
    YaNoSeQuita(AOrigen);
  end;
end;

procedure MezclaArbol(const AOrigen, ADestino: string; var AHechos: TArray<TPasoDeMezcla>);

  procedure Anota(const ADe, AA: string);
  var
    P: TPasoDeMezcla;
  begin
    P.De := ADe;
    P.A := AA;
    AHechos := AHechos + [P];
  end;

  procedure Mezcla(const O, D: string);
  begin
    for var E in EntradasDeCarpeta(O) do
    begin
      var N := TPath.Combine(D, TPath.GetFileName(E));
      // una carpeta (no un enlace) que tambien esta en el destino se mezcla;
      // lo demas se renombra de un golpe
      if TDirectory.Exists(E) and not EsEnlace(E) and TDirectory.Exists(N) and not EsEnlace(N) then
        Mezcla(E, N)
      else
      begin
        var Codigo: Cardinal;
        if not RenombraConReintentos(E, N, 0, Codigo) then
          raise Exception.Create(MotivoDeRenombre(E, Codigo));
        Anota(E, N);
      end;
    end;
    // vacia ya: QuitaCarpetaConReintentos solo quita una carpeta vacia
    var CodigoVacia: Cardinal;
    if not QuitaCarpetaConReintentos(O, CodigoVacia) then
      RaiseLastOSError(CodigoVacia);
    Anota(O, '');
  end;

var
  Motivo: string;
begin
  Motivo := MovidoDenegado(AOrigen, ADestino);
  if Motivo <> '' then
    raise Exception.Create(Motivo);
  SueltaLoNuestroBajo(AOrigen);
  try
    Mezcla(SinBarraFinal(AOrigen), SinBarraFinal(ADestino));
  finally
    YaNoSeQuita(AOrigen);
  end;
end;

function DeshazMezcla(const AHechos: TArray<TPasoDeMezcla>): string;
begin
  Result := '';
  for var I := High(AHechos) downto 0 do
    try
      if AHechos[I].A = '' then
      begin
        CrearCarpeta(AHechos[I].De) // la que la mezcla vacio y quito
      end
      else
      begin
        var Codigo: Cardinal;
        if not RenombraConReintentos(AHechos[I].A, AHechos[I].De, 0, Codigo) then
          RaiseLastOSError(Codigo);
      end;
    except
      on E: Exception do
        AnadeLineaDeRuta(Result, IfThen(AHechos[I].A <> '', AHechos[I].A, AHechos[I].De), E.Message.Trim);
    end;
end;

function EspacioDenegado(const ACarpeta: string; ABytes: Int64): string;
const
  MEGA = 1024 * 1024;
var
  Libre, Total: Int64;
begin
  Result := '';
  if ABytes <= 0 then
    Exit;
  var Carpeta := PrimerAncestroQueExiste(ACarpeta);
  if (Carpeta = '') or not GetDiskFreeSpaceEx(PChar(IncludeTrailingPathDelimiter(Carpeta)),
       Libre, Total, nil) then
    Exit;
  if Libre < ABytes + MARGEN_DISCO_LIBRE then
    Result := MsgFmt(SR_GUARD_SIN_ESPACIO_FMT, [(ABytes + MEGA - 1) div MEGA, Carpeta,
      Libre div MEGA, MARGEN_DISCO_LIBRE div MEGA]);
end;

{ (la nota, en la interface) Nunca lanza: no poder tirar un temporal no es
  motivo para que falle lo que lo pedia. }
procedure VaciaDesechable(const ADir: string);
var
  E: string;
begin
  // El guard del unico que vacia (David, 25-sep-2026): solo una carpeta de la
  // lista central de desechables, y con el __ delante. Una ruta mal
  // calculada nunca vacia otra cosa.
  var Nombre := TPath.GetFileName(SinBarraFinal(ADir));
  if not (Nombre.StartsWith('__') and EsCarpetaDesechable(Nombre)) then
    Exit;
  // ...y si la propia temporal es un ENLACE, lo de detras no es nuestro:
  // enumerarla seria vaciar el destino (25-sep-2026).
  if EsEnlace(SinBarraFinal(ADir)) then
    Exit;
  try
    if not TDirectory.Exists(ADir) then
      Exit;
    for E in TDirectory.GetFiles(ADir) do
      try
        TFile.Delete(E);
      except
      end;
    for E in TDirectory.GetDirectories(ADir) do
      try
        ReclamaArbol(E); // V9: una carpeta nacida cerrada que dejo un test, recuperada antes de borrar
        BorraArbol(E);
      except
      end;
  except
  end;
end;

{ Optional per-agent write confinement (OFF by default). When on, an identified
  agent may write only inside <root>\<its-name>\... or an explicitly shared
  subfolder - so several agents can share one workspace root without stepping on
  each other. A caller with no identity (stdio, the operator's own console) is
  trusted with everything, the same rule the recoverable trash already uses.
  Reading is never confined: an agent still sees the whole tree. }
function AgentConfineDenied(const AFull, ARoot: string): string;
var
  Me, Rel, Seg: string;
  P: Integer;
begin
  Result := '';
  if not AgentConfinementNow then
    Exit;
  Me := CurrentAgent;
  if Me = '' then
    Exit; // stdio / operator: not confined
  // el tramo bajo la raiz, por EL corte (TrozoBajo): fuera de ella, '' y se niega
  TrozoBajo(ARoot, AFull, Rel);
  Rel := ConBarrasDeWindows(Rel);
  P := Rel.IndexOf('\');
  if P < 0 then
    Seg := Rel
  else
    Seg := Rel.Substring(0, P);
  if EsDelAgente(Seg) then
    Exit; // your own folder
  // como NTFS compara dos nombres (RutaEnLista): SameText solo plegaba ASCII y una
  // compartida con una letra no ASCII en otra mayuscula se negaba (revisor del
  // paisaje de la 1.26, 16)
  if RutaEnLista(Seg, SharedFoldersNow) then
    Exit; // a folder the operator marked shared
  Result := MsgFmt(SR_AGENT_CONFINED_FMT, [Me, Me]);
end;

{ El confinamiento por la ruta REAL de AFull: la jaula juzga la real y el
  confinamiento el texto, y <raiz>\agenteA\lnk, una union a <raiz>\agenteB,
  dejaba a A escribir en la carpeta de B (V113 de la 1.23.1, medido). Contra
  la raiz cuya ruta real contiene la real; fuera de todas, lo dice la jaula. }
function ConfinamientoPorLaRutaReal(const AFull: string; const ARoots: TArray<string>): string;
var
  Real: string;
begin
  Result := '';
  if not AgentConfinementNow or (CurrentAgent = '') then
    Exit;
  try
    Real := RealPath(AFull);
  except
    Exit; // una real que no se resuelve la niega la jaula
  end;
  if (Real = '') or EsPrefijoDeDispositivo(Real) then
    Exit;
  Real := FormaLarga(Real);
  // la raiz real mas honda que la contiene, comparada por su ruta real
  var Mejor := RaizMasHonda(ARoots, Real,
    function(const ARaiz: string): string
    begin
      Result := FormaLarga(RealDeLugar(ARaiz));
    end);
  if Mejor <> '' then
    Result := AgentConfineDenied(SinBarraFinal(Real), Mejor);
end;

{ La jaula, con AFueraDeJaula = True cuando la negativa es "fuera de las
  raices" (la pista de la zona de biblioteca va solo ahi). Quien pregunta
  es JaulaDenegada, justo debajo. }
function JaulaDecide(const APath: string; out AFueraDeJaula: Boolean): string;
var
  Roots: TArray<string>;
  Full, R: string;
begin
  AFueraDeJaula := False;
  // Una ruta VACIA es un parametro que falta, no una ruta invalida: el eco
  // de "Invalid path: " vacio no decia cual (revision 27-sep-2026)
  if APath.Trim = '' then
    Exit(MsgText(SR_GUARD_RUTA_VACIA));
  // Name normalization first: it applies with or without a jail configured.
  Result := PathAnomaly(APath);
  if Result <> '' then
    Exit;
  // Solo rutas ABSOLUTAS (<letra>:\ o UNC, la regla de EsRutaAbsoluta). Una
  // relativa se resolvia contra la carpeta del PROCESO: fuera de la jaula
  // decia "fuera" (DENIED) y, si el servidor se lanzo desde dentro de una
  // raiz (stdio), se aceptaba y escribia donde nadie habia dicho; un
  // "/home/x" de un cliente Linux, igual (quinta revision). Aqui, a la
  // entrada, para todo camino que pase por la puerta.
  Result := RutaRelativaDenegada(APath);
  if Result <> '' then
    Exit;
  // El modo local cerrado al cargar, con su motivo, ANTES de mirar nada en
  // el disco (iba mas abajo; tercera revision). Un workspace con su token
  // tiene su propia jaula y no lee nada del entorno: no le toca
  Result := NegativaDeCierre;
  if Result <> '' then
    Exit;
  // Un UNC que no es de ningun sitio declarado: fuera, por TEXTO, antes de
  // InVault / ReadOnlyRootOf, que lo resuelven en el disco (SMB hacia el
  // host que diga el agente; septima revision). Tambien para quien llama a
  // la puerta desde dentro, no solo para la entrada.
  if UncFueraDeLugares(APath) then
  begin
    // (la ruta de red de un sitio declarado con su letra NO es "fuera de
    // las raices": no lleva la pista de la zona de biblioteca)
    var EsFormaDeRed: Boolean;
    Result := NegativaDeUnc(APath, EsFormaDeRed);
    AFueraDeJaula := not EsFormaDeRed;
    Exit;
  end;
  // The knowledge vault belongs to the vault_* tools ALONE, wherever it sits.
  // If it happens to live inside a workspace root, the code tools must still
  // keep out - otherwise delphi_edit could rewrite a note behind the vault's
  // back, skipping its automatic backup and its protected governance files.
  // ...y por la ruta REAL, UNA vez y antes de toda rama: la de las raices lo
  // preguntaba y la de las referencias y la de la biblioteca contestaban
  // antes "se lee" - con el vault dentro de una ReadOnlyRoot, un enlace en la
  // raiz o en la referencia que apuntase dentro dejaba leerlo (V192 de la
  // 1.23.1, medido; la sexta revision lo habia cerrado solo en las raices).
  // Por LA regla del vault, la de los recorredores
  var VerdadDelVault := '';
  if EnUnVault(APath, VerdadDelVault) then
    Exit(MsgText(SR_VAULT_NOT_CODE));
  if not HayJaula then
    Exit; // no jail configured
  Roots := WorkspaceRoots;
  try
    Full := TPath.GetFullPath(APath);
  except
    Exit(MsgFmt(SR_GUARD_RUTA_INVALIDA_FMT, [APath]));
  end;
  // Una REFERENCIA (ReadOnlyRoots) se LEE: dentro de ella por la ruta REAL,
  // el mismo repaso de enlaces que las raices (un junction plantado en la
  // referencia que apunte fuera no abre nada). Que no se ESCRIBE lo dice
  // PathDenied, que la mira antes que las raices.
  var Ref := ReadOnlyRootOf(APath);
  if Ref <> '' then
  begin
    if EnLugar(RealPath(APath), RealPath(Ref), False) then
      Exit('');
    Exit(MsgFmt(SR_JAIL_LINK_FMT, [APath]));
  end;
  var FullLargo := FormaLarga(Full);
  for R in Roots do
    if RutaDentroDe(R, Full) or
       RutaDentroDe(FormaLarga(R), FullLargo) then
    begin
      // Dentro POR EL TEXTO (el declarado o el largo, FormaLarga). Falta que
      // lo este DE VERDAD: un junction o un
      // symlink plantado en la jaula apuntaba fuera y el sistema de ficheros
      // servia el destino tan tranquilo (ver RealPath, y la bateria
      // test_round33 que lo reproduce).
      //
      // OJO a como se compara: el mundo REAL consigo mismo, la ruta real
      // contra las raices reales. Mezclar las dos formas - raices resueltas
      // contra rutas textuales - fue el primer intento de esto y rompio algo
      // peor de lo que arreglaba: las carpetas temporales llegan en 8.3
      // (ABCDEF~1), RealPath las alarga, la comparacion dejaba de casar y se
      // pudo BORRAR la propia raiz del workspace. Lo cazo test_guard en la
      // misma tanda.
      // (la de arriba si ya se calculo: una ruta real por pregunta)
      var Verdad := VerdadDelVault;
      if Verdad = '' then
        Verdad := IncludeTrailingPathDelimiter(RealPath(APath));
      var DentroDeVerdad := False;
      for var RR in Roots do
        if EnLugar(Verdad, RealPath(SinBarraFinal(RR)), False) then
        begin
          DentroDeVerdad := True;
          Break;
        end;
      if not DentroDeVerdad then
        Exit(MsgFmt(SR_JAIL_LINK_FMT, [APath]));
      // (el vault por la ruta REAL se pregunta arriba, para todas las ramas)
      Exit(''); // dentro de una raiz, de verdad: se lee
    end;
  // Fuera de las raices: la zona de biblioteca (RTL/VCL, componentes
  // registrados) se LEE si esta abierta. Solo para quien esta fuera DE
  // VERDAD: un enlace que sale, el vault y las anomalias ya se negaron
  // arriba y nunca llegan aqui. Como las raices: dentro por el TEXTO, en la
  // forma larga (LugaresDeLaBiblioteca ya lo esta: una raiz registrada en
  // 8.3 negaba hasta lo suyo), y DE VERDAD por la ruta real - un enlace YA
  // plantado en una carpeta de la Library Path que apuntase fuera se leia
  // (M1 de la 1.18.0, medido el 9-oct-2026 con la HKCU virtual: el secreto
  // de la victima salio por delphi_read). Primero la raiz que casa por el
  // texto: un recurso de red de la biblioteca que no contesta no se pregunta
  // en cada lectura (David, 1-oct: la biblioteca en red se lee).
  if LibraryZoneEnabled then
    for R in LugaresDeLaBiblioteca do
      if RutaDentroDe(R, FullLargo) then
      begin
        var VerdadLib := RealPath(APath);
        if EnLugar(VerdadLib, RealPath(R)) or
           EnAlgunLugar(VerdadLib, LugaresDeLaBiblioteca) then
          Exit('');
        Exit(MsgFmt(SR_JAIL_LINK_BIBLIOTECA_FMT, [APath]));
      end;
  AFueraDeJaula := True;
  Result := NegativaDeJaula(APath);
end;

function FindFirstFileNameCrudo(AFichero: PChar; ABanderas: DWORD; var ATam: DWORD;
  ANombre: PChar): THandle; stdcall; external kernel32 name 'FindFirstFileNameW';
function FindNextFileNameCrudo(ABusqueda: THandle; var ATam: DWORD;
  ANombre: PChar): BOOL; stdcall; external kernel32 name 'FindNextFileNameW';

{ Un FICHERO con otro nombre (un enlace duro) que esta sesion no puede leer:
  es el MISMO fichero, y leerlo por aqui era leer el de fuera (2al-H2, medido
  el 20-oct-2026 contra 1.21.0: delphi_read, delphi_search y el .res de
  delphi_styles lo leian). El juez es Windows: los nombres del fichero
  (FindFirstFileNameW), cada uno por la jaula (JaulaDecide). Uno de un solo
  nombre - lo normal - cuesta una apertura sin leer nada; uno con varios que
  no se pueden listar se niega: no se sabe donde estan. '' si no es un
  fichero, no existe o tiene un nombre. }
function EnlaceDuroDenegado(const APath: string): string;
const
  TAM_NOMBRE = 32768;
var
  Full, Raiz: string;
  Nombres, Tam: DWORD;
  Vol: array [0 .. MAX_PATH] of Char;
  Buf: array of Char;
  H: THandle;
  Fuera: Boolean;
begin
  Result := '';
  try
    Full := TPath.GetFullPath(APath);
    // un ENLACE se juzga por el fichero de detras: NombresDelFichero abre sin
    // seguir el enlace y contaba el symlink (un nombre), y un symlink a un
    // enlace duro de fuera leia el fichero de fuera (P3 del revisor del
    // paisaje de la 1.29, medido contra produccion: delphi_read lo devolvio)
    if EsEnlace(Full) then
      Full := RealPath(Full);
  except
    Exit; // la jaula ya dijo lo suyo de una ruta invalida
  end;
  Nombres := NombresDelFichero(Full);
  if Nombres <= 1 then
    Exit;
  if not GetVolumePathName(PChar(Full), Vol, Length(Vol)) then
    Exit(MsgFmt(SR_JAIL_ENLACE_DURO_SIN_NOMBRES_FMT, [APath, Nombres]));
  // cada nombre llega desde la raiz de su volumen ("\Users\...\x.txt")
  Raiz := PrefijoSinBarra(string(PChar(@Vol[0])));
  SetLength(Buf, TAM_NOMBRE);
  Tam := TAM_NOMBRE;
  H := FindFirstFileNameCrudo(PChar(Full), 0, Tam, @Buf[0]);
  if H = INVALID_HANDLE_VALUE then
    Exit(MsgFmt(SR_JAIL_ENLACE_DURO_SIN_NOMBRES_FMT, [APath, Nombres]));
  try
    repeat
      if JaulaDecide(Raiz + string(PChar(@Buf[0])), Fuera) <> '' then
        Exit(MsgFmt(SR_JAIL_ENLACE_DURO_FMT, [APath]));
      Tam := TAM_NOMBRE;
    until not FindNextFileNameCrudo(H, Tam, @Buf[0]);
  finally
    Winapi.Windows.FindClose(H);
  end;
end;

function EnlaceDuroIlegible(const APath: string): string;
begin
  // sin jaula no hay fuera
  Result := '';
  if HayJaula then
    Result := EnlaceDuroDenegado(APath);
end;

function EscrituraEnElFicheroDenegada(const APath: string): string;
var
  Nombres: Cardinal;
begin
  Result := '';
  if not HayJaula then
    Exit;
  // medido el 20-oct-2026: delphi_upload sobre un enlace duro dejo lo subido
  // en el fichero de FUERA de las raices; y por un symlink a el, el fichero de
  // detras, el que se escribiria (P3 de la 1.29)
  if EsEnlace(APath) then
    Nombres := NombresDelFichero(RealPath(APath))
  else
    Nombres := NombresDelFichero(APath);
  if Nombres > 1 then
    Result := MsgFmt(SR_ESCRITURA_EN_ENLACE_DURO_FMT, [APath, Nombres]);
end;

function JaulaDenegada(const APath: string; out AFueraDeJaula: Boolean;
  APermiteGit: Boolean): string; overload;
begin
  Result := JaulaDecide(APath, AFueraDeJaula);
  if (Result = '') and not APermiteGit then
    Result := MetadatosGitDenegados(APath);
  // Un FICHERO que llega con separador final (x.txt\) nombrado como carpeta:
  // se leia como el fichero y fallaba dentro de Windows (INTERNAL, septima
  // revision). Una carpeta con su separador es lo normal. Y DESPUES de la
  // jaula, solo de lo que se puede leer: se miraba antes, y de cualquier
  // ruta de la maquina se contestaba si alli habia un fichero (tercera
  // revision de la 1.9.0)
  if (Result = '') and (APath.EndsWith('\') or APath.EndsWith('/')) and
     TFile.Exists(SinBarraFinal(ConBarrasDeWindows(APath))) then
    Result := MsgFmt(SR_GUARD_BARRA_FINAL_FMT, [APath]);
end;

function JaulaDenegada(const APath: string; APermiteGit: Boolean): string; overload;
var
  Fuera: Boolean;
begin
  Result := JaulaDenegada(APath, Fuera, APermiteGit);
end;

{ El gitdir SEPARADO (git init --separate-git-dir) deja los metadatos de git
  SIN segmento .git, asi que el atajo de MetadatosGitDenegados no los ve y el
  agente podria plantar un hook que corre el git de la PERSONA. El juez es
  git (9.A, norma 6): desde la carpeta del fichero -o su primer ancestro que
  exista, porque el fichero puede no estar aun- se pregunta el gitdir y el
  comun (DameGitDirDeCarpeta); si el fichero cae dentro de cualquiera de los
  dos, es metadato. '' = no lo es, o no hay juez de git (el atajo del .git ya
  decidio). Solo la ESCRITURA lo llama (PathDenied, not APermiteGit). }
function MetadatosGitSeparadoDenegado(const APath: string): string;
var
  Carpeta, GitDir, Comun: string;

  function Dentro(const ADir: string): Boolean;
  begin
    Result := (ADir <> '') and
      (EnLugar(TPath.GetFullPath(APath), ADir, True) or
       EnLugar(RealPath(APath), ADir, True));
  end;

begin
  Result := '';
  if not Assigned(DameGitDirDeCarpeta) then
    Exit;
  Carpeta := PrimerAncestroQueExiste(ExtractFileDir(TPath.GetFullPath(APath)));
  if (Carpeta = '') or not TDirectory.Exists(Carpeta) then
    Exit;
  if not DameGitDirDeCarpeta(Carpeta, GitDir, Comun) then
    Exit;
  if Dentro(GitDir) or Dentro(Comun) then
    Result := MsgFmt(SR_GUARD_GIT_METADATA_FMT, [APath]);
end;

function PathDenied(const APath: string; APermiteGit: Boolean): string;
var
  Roots: TArray<string>;
  Full: string;
begin
  // PRIMERO la jaula; solo delphi_git recibe el permiso de metadatos.
  Result := JaulaDenegada(APath, APermiteGit);
  if Result <> '' then
    Exit;
  // El gitdir SEPARADO no tiene segmento .git: lo juzga git, y SOLO en la
  // escritura (not APermiteGit; delphi_git maneja su propio .git). Un proceso
  // git por escritura dentro de un repo, cacheado por carpeta (9.A).
  if not APermiteGit then
  begin
    Result := MetadatosGitSeparadoDenegado(APath);
    if Result <> '' then
      Exit;
  end;
  if not HayJaula then
    Exit; // no jail configured: tampoco reglas de escritura
  Roots := WorkspaceRoots;
  Full := TPath.GetFullPath(APath); // ya no lanza: la jaula lo comprobo
  // Un proyecto de REFERENCIA (ReadOnlyRoots) manda sobre Roots: una
  // carpeta declarada en los dos sitios, o una raiz que caiga dentro de una
  // referencia, es de SOLO LECTURA (David, 25-sep-2026). Por eso se mira
  // ANTES de las raices; el texto dice que se lee y no se toca.
  var Ref := ReadOnlyRootOf(APath);
  if Ref <> '' then
    Exit(MsgFmt(SR_REFERENCE_ROOT_FMT, [APath, Ref]));
  var FullLargo := FormaLarga(Full);
  // La raiz mas honda que lo contiene: de ella se cuenta el tramo del agente. La
  // pertenencia a la jaula, por las dos formas.
  var MejorRaiz := RaizMasHonda(Roots, FullLargo, FormaLarga, Full);
  if MejorRaiz <> '' then
  begin
    // Dentro de la jaula, pero quiza en una carpeta declarada de SOLO
    // LECTURA: un vendor/, un submodulo, un clon de referencia con su
    // propio git. Se comprueba AQUI y no en el lector, y esa es justo la
    // distincion que se quiere: se lee, no se escribe. EL lector de
    // ReadOnlyPaths, por el texto y por la ruta real (su nota)
    var Ro := SoloLecturaDeclaradaEn(APath);
    if Ro <> '' then
      Exit(MsgFmt(SR_READONLY_PATH_FMT, [APath, Ro]));
    // las dos en la forma larga: el tramo del agente se cuenta desde la raiz
    // MAS especifica; y por la ruta REAL, la que juzga la jaula (V113 de la 1.23.1)
    Result := AgentConfineDenied(SinBarraFinal(FullLargo), MejorRaiz);
    if Result = '' then
      Result := ConfinamientoPorLaRutaReal(Full, Roots);
    Exit;
  end;
  // la jaula lo dejo pasar sin estar en una raiz: es zona de biblioteca,
  // que se lee y nunca se escribe
  Result := NegativaDeJaula(APath);
end;

function ParametroQueNoVa(const AModo: string; const ATabla, AEnviados: array of string;
  out ASuyos, AVaCon: string): string;
var
  I: Integer;
  Hay: Boolean;
  Suyos: string;
  Enviados, ConTodo, ConEse: TArray<string>;

  function Lleva(const ALista, AParam: string): Boolean;
  begin
    Result := (' ' + LowerCase(ALista) + ' ').Contains(' ' + LowerCase(AParam) + ' ');
  end;

begin
  Result := '';
  ASuyos := '';
  AVaCon := '';
  Hay := False;
  I := 0;
  while I + 1 <= High(ATabla) do
  begin
    if SameText(ATabla[I], AModo) then
    begin
      Hay := True;
      ASuyos := ATabla[I + 1];
      Break;
    end;
    Inc(I, 2);
  end;
  if not Hay then
    Exit;
  Suyos := ASuyos;
  // lo enviado, en el orden de la terna; el que sobra es el primero que el
  // modo no lleva
  Enviados := [];
  I := 0;
  while I + 2 <= High(AEnviados) do
  begin
    if (AEnviados[I + 1].Trim <> '') and
       not SameText(AEnviados[I + 1].Trim, AEnviados[I + 2]) then
    begin
      Enviados := Enviados + [AEnviados[I]];
      if (Result = '') and not Lleva(Suyos, AEnviados[I]) then
        Result := AEnviados[I];
    end;
    Inc(I, 3);
  end;
  if Result = '' then
    Exit;
  // un modo que no toma ninguno: "takes no parameters", no "takes ."
  // (segunda revision de la 1.17.0, PAS-051 de platforms)
  if ASuyos.Trim = '' then
    ASuyos := MsgText(SF_MODO_SIN_PARAMETROS);
  // con que modos SI va, de la misma tabla: los que lo llevan todo, y los
  // que llevan el que sobra
  ConTodo := [];
  ConEse := [];
  I := 0;
  while I + 1 <= High(ATabla) do
  begin
    if Lleva(ATabla[I + 1], Result) then
    begin
      ConEse := ConEse + [ATabla[I]];
      Hay := True;
      for var E in Enviados do
        if not Lleva(ATabla[I + 1], E) then
        begin
          Hay := False;
          Break;
        end;
      if Hay then
        ConTodo := ConTodo + [ATabla[I]];
    end;
    Inc(I, 2);
  end;
  if (Length(Enviados) > 1) and (Length(ConTodo) > 0) then
    AVaCon := MsgFmt(SF_LO_ENVIADO_VA_CON_FMT, [string.Join(', ', Enviados), string.Join(', ', ConTodo)])
  else if Length(ConEse) > 0 then
    AVaCon := MsgFmt(SF_PARAMETRO_VA_CON_FMT, [Result, string.Join(', ', ConEse)]);
end;

function PrimerAncestroQueExiste(const ARuta: string): string;
begin
  Result := ARuta;
  // un ENLACE existe aunque su destino no (una junction a una unidad
  // desmontada): TDirectory.Exists dice False, y el deshacer la tomaba
  // por creada y la quitaba (decima revision). Si no existe ninguno, la
  // raiz (la ultima de la subida)
  for var D in Ancestros(ARuta) do
  begin
    Result := D;
    if TDirectory.Exists(D) or EsEnlace(D) then
      Exit;
  end;
end;

// LA politica de reintentos (abajo, junto al renombre que la uso primero)
function ConReintentos(const AOperacion: TFunc<Boolean>; out ACodigo: Cardinal): Boolean; forward;

procedure QuitaCarpetasCreadas(const ADesde, AAncestro: string;
  const AJuez: TJuezDeCarpeta);
var
  D: string;

  function Denegado(const ARuta: string): string;
  begin
    if Assigned(AJuez) then
      Result := AJuez(ARuta)
    else
      Result := EscrituraDenegada(ARuta);
  end;

begin
  if AAncestro = '' then
    Exit;
  try
    for D in Ancestros(SinBarraFinal(ADesde)) do
    begin
      if (Length(D) <= Length(SinBarraFinal(AAncestro))) or (Denegado(D) <> '') then
        Break;
      // un enlace no lo creo nadie aqui: nunca se quita (decima revision)
      if EsEnlace(D) then
        Break;
      // por LA politica de reintentos: un lector de un instante la tiene
      // abierta y rebota con 32 (V45 de la 1.27, medido: un clone fallido
      // dejaba la suya, y un segundo despues se podia quitar)
      var Err: Cardinal;
      if not QuitaCarpetaConReintentos(D, Err) then
      begin
        // no esta vacia (otro dejo algo) o no se puede: se queda, y el log
        // dice por que
        try TLogger.Warning(MsgFmt(SL_CARPETA_CREADA_SE_QUEDA_FMT, [Err, D])); except end;
        Break;
      end;
    end;
  except
    // quitar lo creado nunca lanza
  end;
end;

function RutaSinTocarElDisco(const APath: string): Boolean;
begin
  Result := UncFueraDeLugares(APath) or EsPrefijoDeDispositivo(APath);
end;

function UncFueraDeLugares(const APath: string): Boolean;
var
  P, L: string;
  Lugares: TArray<string>;
begin
  P := ConBarrasDeWindows(APath.Trim);
  // los prefijos de dispositivo son de PathAnomaly (GUARD-022), no de aqui
  if not EsUnc(P) then
    Exit(False);
  // sin jaula no hay "fuera"; el modo local CERRADO no tiene sitios, y todo
  // UNC lo esta: se llegaba al host que nombrase el agente antes de negarlo
  // (1,3 s medidos con uno que no existe; tercera revision de la 1.9.0)
  if not HayJaula then
    Exit(NegativaDeCierre <> '');
  Lugares := LugaresDeclarados; // ya sin blancos y con barras de Windows
  P := IncludeTrailingPathDelimiter(P);
  for L in Lugares do
  begin
    if EnLugar(P, L, False) then
      Exit(False);
    // ...y por la forma LARGA de un sitio declarado en 8.3: la entrada ya
    // alargo la ruta del agente y un sitio UNC declarado con ~ lo negaba
    // TODO (octava revision). La E/S es sobre el sitio del operador, no
    // sobre lo que manda el agente.
    if (L.IndexOf('~') >= 0) and RutaDentroDe(FormaLarga(L), P) then
      Exit(False);
    // ...y una ruta del agente con segmentos en 8.3 (C$\Users\DAVID~1\...\largo):
    // se alarga ELLA, pero solo si su recurso (\\servidor\recurso) es el de
    // un sitio declarado - la E/S va a un host que declaro el operador, nunca
    // a uno que nombre el agente (octava revision; lo media el A13 de
    // test_alias83 con una raiz UNC, hasta la 1.8.2)
    if (P.IndexOf('~') >= 0) and
       SameFileName(ExtractFileDrive(P), ExtractFileDrive(L)) and
       RutaDentroDe(FormaLarga(L), FormaLarga(P)) then
      Exit(False);
  end;
  Result := True;
end;

{ La misma ruta bajo OTRA unidad, si cae en un sitio que esta sesion lee y su
  puerta la deja leer: la que nombra la negativa (V92 de la 1.23.1: Hermes
  escribio srvn:\Program Files (x86)\... con sus raices en srvn: y la zona de
  biblioteca en srvc:, y la negativa no decia cual). Las candidatas, de
  Lsp.Lugares (MismaRutaEnOtrasUnidades: la ruta bajo la letra de cada lugar
  declarado que la contiene); la buena pasa la puerta y EXISTE - medido en
  vivo: una raiz que es una unidad entera (srvn:\) contiene
  por texto cualquier ruta, y la pista nombraba una que no estaba -. Mirarla
  despues de la puerta no es un oraculo: es una ruta que la sesion ya lee.
  '' si no hay. }
function MismaRutaEnOtraUnidad(const APath: string; APermiteGit: Boolean): string;
var
  Fuera: Boolean;
begin
  Result := '';
  for var Candidata in MismaRutaEnOtrasUnidades(APath) do
    if (JaulaDenegada(Candidata, Fuera, APermiteGit) = '') and
       (FileExists(Candidata) or DirectoryExists(Candidata)) then
      Exit(Candidata);
end;

function ReadPathDenied(const APath: string; APermiteGit: Boolean): string;
var
  Fuera: Boolean;
begin
  // la jaula tal cual: sin perdones que acertar (hasta la 1.7.3 era PathDenied
  // menos una tabla de perdones por motivo; ver JaulaDenegada)
  Result := JaulaDenegada(APath, Fuera, APermiteGit);
  // Refused for reading: say that a library zone exists and how to see it.
  // Field 2026-08-22: an agent listed the PARENT of a registered component
  // folder, got the plain jail refusal, and concluded list and read disagreed.
  // Solo si la zona EXISTE y solo para quien esta fuera de la jaula: se
  // pegaba a toda negativa, con la zona apagada (contradecia a WS-001) y a
  // las rutas invalidas (revision 27-sep-2026)
  if (Result <> '') and Fuera and LibraryZoneEnabled then
    Result := Result + ' ' + MsgText(SN_READ_ZONE_HINT);
  // ...y si solo se equivoco de unidad, la buena (V92)
  if (Result <> '') and Fuera then
  begin
    var Otra := MismaRutaEnOtraUnidad(APath, APermiteGit);
    if Otra <> '' then
      Result := Result + ' ' + MsgFmt(SN_READ_OTRA_UNIDAD_FMT, [Otra]);
  end;
  // ...y un fichero con otro nombre que esta sesion no lee: leerlo es leer
  // ese (un enlace duro). Solo al LEER - aqui pregunta la puerta de leer
  // (LeeTexto/LeeBytes) -: quitar o mover ESTE nombre no toca el otro, y el
  // escritor atomico pone un fichero nuevo en su sitio. Sin jaula no hay fuera
  if Result = '' then
    Result := EnlaceDuroIlegible(APath);
end;

function ExisteYSeLee(const ARuta: string; ACarpeta: Boolean): Boolean;
begin
  Result := (ARuta <> '') and (ReadPathDenied(ARuta) = '') and
    (TFile.Exists(ARuta) or (ACarpeta and TDirectory.Exists(ARuta)));
end;

function MotivoDeRenombre(const APath: string; ACodigo: Cardinal): string;
begin
  Result := MotivoDelSistema(TPath.GetFileName(APath) + ': ' + SysErrorMessage(ACodigo));
  if Result = '' then
    Result := MsgFmt(SR_EDIT_RENAME_ATOMICO_FALLIDO_FMT,
      [TPath.GetFileName(APath), ACodigo, SysErrorMessage(ACodigo).Trim]);
end;

{ LA politica de reintentos de una operacion sobre el disco que un lector de un
  instante hace rebotar (5, 32, 33): cinco intentos, 100 ms entre uno y otro;
  otro codigo no se reintenta. AOperacion devuelve si pudo y deja su codigo en
  GetLastError. La comparten el renombre (RenombraConReintentos) y quitar una
  carpeta vacia que creo la llamada (QuitaCarpetasCreadas: un clone fallido
  dejaba la suya con 32, V45 de la 1.27). }
function ConReintentos(const AOperacion: TFunc<Boolean>; out ACodigo: Cardinal): Boolean;
begin
  ACodigo := 0;
  for var Intento := 1 to 5 do
  begin
    Result := AOperacion();
    if Result then
      Exit;
    ACodigo := GetLastError;
    if (ACodigo <> ERROR_ACCESS_DENIED) and (ACodigo <> ERROR_SHARING_VIOLATION) and
       (ACodigo <> ERROR_LOCK_VIOLATION) then
      Exit;
    Sleep(100);
  end;
end;

function RenombraConReintentos(const AOrigen, ADestino: string; AFlags: Cardinal;
  out ACodigo: Cardinal): Boolean;
begin
  Result := ConReintentos(
    function: Boolean
    begin
      Result := MoveFileEx(PChar(AOrigen), PChar(ADestino), AFlags);
    end, ACodigo);
end;

function QuitaCarpetaConReintentos(const ACarpeta: string; out ACodigo: Cardinal): Boolean;
begin
  Result := ConReintentos(
    function: Boolean
    begin
      Result := RemoveDir(ACarpeta);
    end, ACodigo);
end;

initialization
  GDiasQueSeQuedan := TDictionary<string, Boolean>.Create;

finalization
  GDiasQueSeQuedan.Free;

end.