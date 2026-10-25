unit Lsp.Patch;

{ Safe Delphi source editing engine - the port of an internally
  battle-tested tool (30+ measured test rounds against several LLMs, small
  and large). Every gate below exists because a model was measured breaking
  a file through that exact hole. Design rules:

  - Anchor = ONE full existing line (the blanks at either end do not count);
    never substrings, never multi-line anchors, never whole-file rewrites.
  - Encoding is detected (UTF-8 BOM / strict UTF-8 / the machine's ANSI page / UTF-16 by BOM) and preserved;
    a character that does not fit the file's codepage REJECTS the edit with
    the legitimate native-literal alternative spelled out.
  - Atomic writes (tmp + rename), automatic pre-edit backups under
    __delphi-patch\<yyyymmdd>\ next to the file, 2-step restore.
  - Binary designer files (TPF0) and IDE graveyards (__history/__recovery)
    are hard-rejected.
  - After every write the file is re-read from disk and audited: corruption
    marks, high-byte accounting, alien line endings, mojibake signatures,
    'end.' structure, routine-inserted-inside-a-method heuristic. }

interface

uses
  Lsp.Codificacion,
  Lsp.DesignerMeta; // TFaltaTabla y su espera: el lint de un form (LintDeForm)

type
  TPatchArgs = record
    Path: string;
    OldLine: string;      // anchor (one full line)
    NewText: string;      // replacement (may be multi-line)
    HasOld, HasNew: Boolean;
    AtLine: Integer;      // 1-based disambiguation; 0 = unset
    ToLine: Integer;      // 1-based LAST line of the range; 0 = just the anchor
    DeleteLine: Boolean;  // true = remove the anchored line entirely
    Fragment: string;     // modo fragmento: un trozo de la linea AtLine
    Insert: string;       // '', 'rutina-global', 'metodo'
    Code: string;
    ClassName_: string;
    Visibility: string;
    Visible: Boolean;
    CreateUnit_: Boolean;
    Content: string;      // createunit: whole file content in one call
    Eol: string;          // 'lf' = LF endings; anything else = CRLF (default)
    Restore: Boolean;
    Confirm: Boolean;
    Ensayo: Boolean;      // todo menos escribir: el preview de un changeset pregunta al motor
  end;

function ExecutePatch(const A: TPatchArgs): string;

type
  TMetrics = record
    Bytes, CR, LF, CRLF, Loose, High, Corruption: Integer;
  end;

{ EL detector de codificacion, publico para que la suite DUnitX del motor
  (LspUnitTests) lo pruebe sin pasar por un fichero; sus dos inversas
  (DecodeBytes / EncodeText) y las clases que decide (TEncKind) estan en
  Lsp.Codificacion desde el 8-oct-2026. UTF-16 (LE y BE, siempre con BOM: es
  como lo escribe el IDE cuando se elige ese formato al ver un .dfm como
  texto) entro el 24-sep-2026; antes lo reconocia SOLO
  Lsp.Client.LoadSourceText por su cuenta. Un detector, no dos.
  AEsDesigner (EsRutaDeDesigner de su ruta): un form de TEXTO sin BOM es
  ANSI, lo sea o no como UTF-8 - asi lo leen dcc, el parser de forms del
  IDE y el renderizador (medido 9-oct-2026: 'Accion' acentuado en UTF-8 sin
  BOM se ejecuta como 'AcciÃ³n'); el servidor lo leia como UTF-8 (4.1 de la
  1.18.0, David: un parametro del detector, no un segundo detector). }
function DetectEnc(const B: TArray<Byte>; AEsDesigner: Boolean = False): TEncKind;
{ LA etiqueta que se ENSENA de la codificacion de un fichero (encoding= de
  delphi_read, delphi_edit y delphi_textedit): su EncName, salvo la de uno sin
  BOM y sin ningun byte alto (AEsAscii), que leen igual el UTF-8 y la ANSI:
  'ascii (utf8/ansi compatible)'. El detector lee ese ASCII en la preferencia
  del IDE para los ficheros NUEVOS (la cuenta EncAlEscribir para un fuente que
  nace en la llamada), y delphi_read decia utf8 de una unit que el IDE abre
  como ANSI (A41 de la 1.23, David 24-oct); el create de delphi_textedit ya lo
  decia asi, con su propia regla. Solo la etiqueta: los bytes no cambian. }
function EtiquetaDeCodificacion(K: TEncKind; AEsAscii: Boolean): string;
{ La sangria (espacios y tabuladores) del principio de S. }
function LeadingWhite(const S: string): string;
{ La sangria de la linea de ATexto en la que esta la posicion APos (1-based):
  solo el blanco del principio de esa linea. Para meter una etiqueta al lado
  de otra en un .dproj: BuildRunner y Config copiaban TODO lo que habia
  delante del ancla en su linea, y con dos etiquetas en una linea (un .dproj
  editado a mano) duplicaban la de delante (revisor de la 1.15.0). }
function SangriaDeLaLineaEn(const ATexto: string; APos: Integer): string;
{ LA regla de la sangria que el agente deja fuera del ancla, para delphi_edit
  y delphi_textedit (6-oct-2026: estaba escrita dos veces, de dos formas, y
  delphi_edit la duplicaba). Si el ancla (AAncla, tal como llego) trae menos
  sangria que la linea real (ALinea) y la primera linea de ANuevas no trae
  ninguna, todas las lineas con texto de ANuevas toman la de ALinea; si no,
  van tal cual: nunca se duplica. }
function SangraComoLaLinea(const ALinea, AAncla: string;
  const ANuevas: TArray<string>): TArray<string>;
function Measure(const B: TArray<Byte>): TMetrics;

{ El decodificador de delphi_read, suelto: bytes -> texto con SU encoding real
  (BOM de UTF-8 o UTF-16, UTF-8 estricto, y la ANSI solo cuando algun byte alto
  NO forma secuencia valida). Es EL detector: nadie mas decide codificaciones.
  Para quien ya tiene los bytes en la mano y no quiere leer el fichero dos
  veces. }
function DecodeSourceBytes(const B: TArray<Byte>; AEsDesigner: Boolean = False): string; // = TBytes

{ La regla UNICA de "esto no es texto": un byte NUL en los primeros 64 KB,
  salvo que el detector diga UTF-16, donde los NUL son la mitad de cada
  caracter ASCII. Vivia dos veces (delphi_read con 4 KB y delphi_textedit
  con 64 KB) y ninguna sabia de UTF-16 (24-sep-2026). }
function LooksBinaryBytes(const B: TArray<Byte>): Boolean;

{ Sustituye un BLOQUE CONTIGUO de lineas, comparado entero y por contenido
  (sin sangria). Encoding y finales de linea, los del fichero. Vivia dentro de
  delphi_edit y por eso delphi_textedit no podia tener anclas de bloque -
  editar un parrafo largo de documentacion obligaba a pegar el parrafo entero
  como ancla de una linea (medido el 2026-09-20 con TOOLS.md, que tiene
  parrafos de 3 KB en UNA linea). Es generico: solo usa PatchLoadText y
  PatchSaveText.
  AOccurrence: 0 = tiene que ser unico; 1, 2... = esa aparicion.
  AAtLine (1-based, 0 = sin usar): la linea donde empieza el bloque, YA
  resuelta por quien llama. Dentro de una tanda es obligatorio usarla: las
  ocurrencias se resuelven contra el fichero ORIGINAL y se arrastran, porque
  contarlas aqui seria contarlas sobre el fichero ya mutado. }
function ApplyBlockEdit(const APath, AOld, ANew: string;
  AOccurrence: Integer; AAtLine: Integer = 0): string;

{ Las lineas que pone "new": UNA regla para delphi_edit y delphi_textedit,
  de una linea o de bloque. Un salto final es el FIN de la ultima linea (un
  bloque leido de un fichero siempre lo trae: se colaba como linea en
  blanco en medio del codigo, medido 2026-08-25) y se quita; cada salto DE
  MAS es una linea en blanco pedida. Hasta el 26-sep habia tres reglas:
  delphi_edit quitaba uno y con dos dejaba DOS en blanco, delphi_textedit
  no quitaba ninguno, y las anclas de bloque de las dos quitaban TODOS -
  un bloque no podia acabar en linea en blanco y la tool contestaba
  APLICADAS (lo cazaron las baterias al pasarlas al cliente unico). }
function LineasDeNew(const ANew: string): TArray<string>;

{ La negativa de un ancla de UNA linea que no casa con ninguna, con el
  motivo: si el texto esta DENTRO de una linea lo dice (y como cambiar
  solo ese trozo); si no, "no aparece" con la mejor pista (el U+FFFD de
  una lectura rota, o la linea mas parecida). UN texto para
  delphi_edit y delphi_textedit; la linea que falta de un ancla de
  bloque usa la misma pista. AFichero es el nombre a ensenar. }
function AnclaPerdida(const ALines: TArray<string>;
  const AOld, AFichero: string): string;

{ EL rango, validado en un solo sitio.

  "old" ancla la PRIMERA linea y "toline" (1-based, incluida) dice hasta
  donde llega. Devuelve '' y el indice 0-based final en AFin, o el texto de
  rechazo si el rango no tiene sentido. ATarget0 es la linea del ancla ya
  resuelta (0-based) y ATotal cuantas lineas tiene el fichero.

  Vive aqui y no dentro de cada motor porque los motores son DOS -el de
  Pascal (DoEdit) y el de texto plano (DoEditLine)- y las reglas de un rango
  no tienen nada de Pascal. Escribirlas dos veces es como nacieron los tres
  bugs gemelos del 2026-09-20. }
function RangoHasta(const APath: string;
  ATarget0, AToLine, ATotal: Integer; out AFin: Integer): string;

{ EL modo fragmento, resuelto en un solo sitio.

  Convierte (fragmento + atline + new) en lo unico que entienden los motores:
  la linea COMPLETA que hay (AOld) y la linea COMPLETA que queda (ANewLine).
  Devuelve '' o el texto de rechazo. No escribe nada y no sabe nada de Pascal:
  despues, el motor de siempre vuelve a casar la linea entera en AtLine antes
  de tocar el disco, asi que la regla del ancla completa no se relaja - solo
  deja de teclearla quien llama. Si el fichero cambia entre medias, el ancla
  ya no casa y la edicion se rechaza.

  Lo llaman las cuatro puertas por las que entra una edicion: delphi_edit,
  delphi_textedit, las tandas (AplicaTanda) y el stage de delphi_changeset.
  AOtros: el nombre del parametro incompatible que venga puesto ('' si
  ninguno), para que la negativa sea la misma en las cuatro. }
function FragmentoALinea(const APath, AFrag, ANew: string; AAtLine: Integer;
  const AOtros: string; out AOld, ANewLine: string): string;

{ La linea (1-based) donde empieza la N-esima aparicion de un ancla de BLOQUE,
  0 si no hay tantas. El gemelo de NthOccurrenceLine para bloques, y por el
  mismo motivo: pre-resolver una tanda contra el fichero original. }
function NthBlockLine(const APath, AOld: string; AN: Integer): Integer;

{ La linea (1-based) de la N-esima aparicion de un ancla de UNA linea, 0 si no
  hay tantas. Desempata dentro de una tanda mejor que atline, porque los
  numeros de linea SE MUEVEN segun las entradas anteriores. }
function NthOccurrenceLine(const APath, AAnchor: string; AN: Integer): Integer;

{ Encoding-correct numbered read (also serves the remote file toolset). }
function ReadNumbered(const APath: string; AFrom, ATo: Integer): string;

{ Una posicion a la que nadie podria apuntar: linea o columna negativa, linea
  mas alla del final, columna mas alla de la linea, o fichero que no esta.
  '' cuando la posicion es real.

  Vive AQUI, y no en la unidad de una tool, porque la usan SEIS: definition,
  hover, signature, completion, references y rename_symbol. Estaba en la
  implementation de Mcp.Tools.DelphiLsp, o sea invisible para las otras dos
  unidades, y por eso cuatro validaban y dos no: delphi_completion contestaba
  ok:true con 16.835 candidatos a una columna NEGATIVA, y references lanzaba
  una excepcion cruda en ingles. Duplicarla en cada unidad habria sido repetir
  el fallo; se mueve al sitio donde ya miran todas. }
function PositionOutOfRange(const APath: string; ALine, AChar: Integer): string;
{ Lo que impide preguntar por la posicion ALine:AChar de APath: la puerta de
  lectura (ReadPathDenied: sin ruta, GUARD-018) y PositionOutOfRange (que
  sea un fuente Delphi y que la posicion exista). '' si se puede. EL
  preambulo de las seis tools de posicion: cuatro lo escribian con
  NotDelphiSource delante, que repetia la pregunta del fuente, y dos con la
  puerta a mano (W7 de la auditoria de duplicados del 16-oct; V34 de la
  1.23). delphi_rename_symbol pasa antes la de escritura si escribe. }
function PosicionQueNoSePregunta(const APath: string; ALine, AChar: Integer): string;

{ Las LINEAS de un texto, como las cuenta delphi_read: los tres saltos
  (CRLF, LF, CR) son uno, y el salto final CIERRA la ultima linea, no abre
  otra ("a\nb\n" son 2; "" son 0). Estaba escrito cuatro veces con dos
  condiciones distintas, y vault_read y LSP-004 no lo aplicaban: la nota de
  5 lineas salia de 6, y el LSP decia 21 donde delphi_read decia 20
  (sexta revision). CuantasLineasReales es la misma regla para quien
  necesita conservar la fantasma (para volver a unir el texto). }
function LineasDelTexto(const AText: string): TArray<string>;
{ Si una linea del fichero ES la de un ancla: LA regla de los motores de
  Pascal y de texto, de sus bloques, de occurrence y del preview del
  changeset (A15 de la 1.23). Los blancos de los DOS extremos no cuentan, ni
  la sangria ni los de detras ("  foo;  " es "foo;"): lo que quita el Trim de
  la RTL, todo lo que es <= ' '. Eran tres reglas: el ancla de una linea de
  Pascal contaba el final exacto, y la de texto y los bloques lo recortaban,
  asi que la misma linea casaba en un bloque y sola no. }
function LineaEsLaDelAncla(const ALinea, AAncla: string): Boolean;
{ Las lineas (0-based) donde casa un ancla de UNA linea, por
  LineaEsLaDelAncla. El preview del changeset preguntaba con OTRA regla y
  decia limpio lo que el commit rechazaba (octava revision): UNA pregunta
  para los motores y para su preview. }
function LineasDondeCasaElAncla(const ALines: TArray<string>; const AAncla: string): TArray<Integer>;
{ Donde EMPIEZA un ancla (0-based), de una linea o de bloque: todas sus
  apariciones, en orden, las que cuenta occurrence (las de un bloque, hasta
  500). Estaba escrito dentro de la guarda de sangria; lo pregunta tambien
  la puerta de una tanda, en el fichero de antes (A15). }
function IniciosDelAncla(const ALines: TArray<string>; const AAncla: string): TArray<Integer>;
{ La linea que edita un ancla de UNA linea entre las que casan (AHits, 0-based,
  de LineasDondeCasaElAncla, al menos una): la unica, o la de atline (AAtLine,
  1-based) si es de ellas. '' y su indice en AIdx; si no, LA negativa de las
  dos tools: repetida sin atline (EDIT-077) o un atline que no es ninguna
  (EDIT-062). delphi_textedit decia lo mismo con otros dos codigos (TEXT-009
  y TEXT-002, A15 de la 1.23). }
function LineaElegida(const AHits: TArray<Integer>; AAtLine: Integer; out AIdx: Integer): string;
function CuantasLineasReales(const ALines: TArray<string>): Integer;
{ Borrar una linea EN BLANCO (P3-L9): no tiene texto que copiar como ancla,
  asi que el ancla es la posicion (atline, 1-based) y la condicion de que
  ESA linea este en blanco - lo que casa con un ancla vacia
  (LineaEsLaDelAncla). '' si se puede; si no, la negativa (EDIT-123 con la
  linea citada, EDIT-124 si no existe). AReales: las lineas sin la fantasma
  del salto final, como las cuenta cada motor. }
function LineaEnBlancoDenegada(const ALines: TArray<string>;
  AReales, AAtLine: Integer; const AFichero: string): string;

{ El salto de linea DOMINANTE de un texto (CRLF, LF o CR suelto: el que mas
  aparece; CRLF si no hay ninguno, el de Windows), para quien vuelve a unir
  lineas. UNO: estaba en Lsp.TextEdit (DominantEol) y escrito a mano en otros
  ocho sitios como "CRLF si hay alguno", que no veia un CR suelto (septima
  revision). }
function SaltoDominante(const AText: string): string;
{ Las lineas de un texto CON la fantasma del salto final (un CR suelto es
  salto): para quien vuelve a unir el texto con su salto. LineasDelTexto es
  esta sin la fantasma. UN troceador: habia cinco a mano que no veian el CR
  suelto (octava revision). }
function SplitToLines(const T: string): TArray<string>;
{ Las mismas lineas que SplitToLines, y en ASaltos el salto con que acaba
  CADA una ('' la ultima): para quien reescribe unas lineas y tiene que
  dejar las demas byte a byte, un fichero mixto tambien. UneConSusSaltos
  es su inversa. El renombrado de una unit troceaba solo por LF: un
  fichero de CR sueltos era UNA linea y no se reescribia (novena revision). }
function SplitToLinesConSalto(const T: string; out ASaltos: TArray<string>): TArray<string>;
function UneConSusSaltos(const ALineas, ASaltos: TArray<string>): string;
{ Las lineas (desde 1) con la firma de un mojibake: UTF-8 leido como ANSI o
  como Latin-1. Lo pregunta el aviso de un texto nuevo que lo trae; en la
  interfaz para el DUnitX, que la mide en otras paginas. }
function MojibakeLines(const T: string): TArray<Integer>;
{ ATexto con ACuantas lineas desde ALinea (0-based, las de SplitToLines)
  cambiadas por ANuevas, y cada linea de fuera BYTE A BYTE, con su salto: una
  edicion no reescribe lo que no toca (1.18.2; medido el 10-oct-2026: textedit
  dejaba en CRLF una linea LF que no habia tocado, y asi los siete que unian
  todas las lineas con el salto dominante). Los saltos de ANuevas son ASalto
  (el dominante: es texto que se escribe), y la ultima se queda el salto con
  que acababa la ultima que se va. ANuevas vacio: las lineas se van con su
  salto (las ultimas de un texto sin salto final, con el de delante: sigue sin
  el). ACuantas = 0: ANuevas entran delante de ALinea. Lo que el tramo deja
  IGUAL al principio y al final no se toca. UN compositor para
  todo el que cambia lineas de un texto que ya existe. }
function CambiaLineasEnSuTexto(const ATexto: string; ALinea, ACuantas: Integer;
  const ANuevas: TArray<string>; const ASalto: string): string;
{ Lo mismo para un TRAMO de la vista en LF de ATexto (la de ConSalto(ATexto,
  #10): un salto, CRLF, LF o CR suelto, es un caracter): desde ADesde (0-based)
  ALargo caracteres cambiados por ANuevo (en LF). Las lineas que toca el tramo
  se reescriben enteras por CambiaLineasEnSuTexto; las demas, byte a byte. Para
  quien cambia un trozo y no lineas (vault_patch, vault_append). }
function EmpalmaEnSuTexto(const ATexto: string; ADesde, ALargo: Integer;
  const ANuevo, ASalto: string): string;
{ Que linea de AAntes es cada una de ADespues en el cambio mas corto (Myers,
  por contenido; lo igual delante y detras, sin buscar): su indice, o -1 si
  es nueva. Para quien recibe el texto ENTERO que compuso un escritor y tiene
  que saber que se quedo. Con mas de 1000 cambios en medio, el medio entero
  sale nuevo: eso ya es reescribir. }
function LineasQueSeQuedan(const AAntes, ADespues: TArray<string>): TArray<Integer>;
{ ANuevo, el texto ENTERO que un escritor compuso sobre AAntes, con la regla
  de quien cambia lineas: cada tramo que cambia (LineasQueSeQuedan), por
  CambiaLineasEnSuTexto con el salto dominante de AAntes; lo que se queda,
  byte a byte, y el final como lo deja ANuevo. Para PatchSaveConSuSalto, que
  pasaba lo nuevo al dominante solo si el fichero no tenia NINGUN CRLF: en
  uno mixto, un bloque insertado con sLineBreak dejaba en CRLF la linea LF de
  delante (V35 de la 1.23, medido el 24-oct-2026). }
function ReescribeConSusSaltos(const AAntes, ANuevo: string): string;
{ El texto con TODOS sus saltos (CRLF, LF o CR suelto) como ASalto: UN
  normalizador para quien crea o inserta texto. Estaba escrito seis veces,
  y el create del changeset solo miraba CRLF y LF: "uno\rdos\r" salia
  "uno\rdos\r\r\n" (novena revision). }
function ConSalto(const AText, ASalto: string): string;

{ Si el texto lleva algun salto de linea (CR o LF): la pregunta "un ancla es
  UNA linea" de DoEdit, DoEditLine, FragmentoALinea y el stage de un changeset
  (decima revision: estaba escrita tres veces y al stage le faltaba). }
function TieneSalto(const AText: string): Boolean;
{ Los ficheros que edita el motor de Pascal (delphi_edit): sus fuentes y
  sus designers; el resto, el de texto. Vivia en Lsp.Changeset con su
  propia lista; aqui sale de las del motor (novena revision). }
function EsDelMotorPascal(const APath: string): Boolean;

const
  // LAS listas de extensiones del motor: quien pregunte por una extension
  // Delphi las usa. Estaban copiadas en AvisosDeLlaves, FileOps (x4),
  // ProjectUnits y TextEdit (decima revision)
  SOURCE_EXTS: array [0 .. 3] of string = ('.pas', '.dpr', '.dpk', '.inc');
  DESIGNER_EXTS: array [0 .. 1] of string = ('.dfm', '.fmx');
  PROJECT_EXTS: array [0 .. 1] of string = ('.dproj', '.groupproj');
  // el manifiesto de despliegue del IDE: al lado del .dproj y con su nombre
  EXT_MANIFIESTO = '.deployproj';

{ Los designers que puede tener una unidad: uno por DESIGNER_EXTS, al lado y
  con su mismo nombre (la regla del IDE), existan o no, en el orden de la
  lista. La inversa de UnidadDeDesigner (Lsp.DesignerForma): la componian a
  mano, extension a extension, Mcp.Tools.FileOps (el borrado, el mover y su
  gemelo) y Lsp.ProjectUnits (2.2 de la 1.18.0). }
function DesignersDeUnidad(const AUnidad: string): TArray<string>;
{ Si APath es un designer por su extension (DESIGNER_EXTS: .dfm, .fmx), sea
  de texto o binario. EL predicado: estaba escrito a mano con su lista en
  nueve sitios (4.1 de la 1.18.0, al pasarselo al detector). }
function EsRutaDeDesigner(const APath: string): Boolean;
{ Si APath es un estilo de FMX por su extension (.style), de texto o
  binario: el de texto lo lee el parser de los forms (TParser). EL
  predicado: estaba comparado a mano en Lsp.TextEdit y Mcp.Tools.Styles, y
  el escritor necesita saberlo (M4 de la 1.23). }
function EsRutaDeEstilo(const APath: string): Boolean;
{ Si APath es un FUENTE por su extension (SOURCE_EXTS: .pas, .dpr, .dpk,
  .inc): lo que lee dcc, cada uno con su propio BOM (medido el 9-oct-2026,
  tambien un .inc incluido desde un .pas sin BOM). EL predicado, como
  EsRutaDeDesigner: estaba escrito a mano con su lista en cinco sitios. }
function EsRutaDeFuente(const APath: string): Boolean;
{ Si APath es un PROYECTO del IDE por su extension (PROJECT_EXTS: .dproj,
  .groupproj): lo que lleva delphi_config, y ni delphi_edit ni delphi_textedit
  escriben. EL predicado: los dos rechazos se mandaban el uno al otro y
  ninguno a delphi_config (Hermes, dirigido de la 1.20.1). }
function EsRutaDeProyecto(const APath: string): Boolean;
{ Si APath es un fichero que el IDE carga como XML: un proyecto
  (EsRutaDeProyecto) o su manifiesto de despliegue (.deployproj). Lo que de
  ellos escribe el servidor lo juzga antes el parser del IDE (PatchSaveText). }
function EsXmlDelIde(const APath: string): Boolean;
{ Si APath es un manifiesto de despliegue del IDE (EXT_MANIFIESTO), por como
  acaba: tambien el Project de un <Import> ($(MSBuildProjectName).deployproj),
  que no es una ruta. EL predicado: estaba a mano en el build, en la mudanza y
  en EsXmlDelIde (paisaje medido el 23-oct-2026). }
function EsManifiesto(const APath: string): Boolean;
{ ...y el de ADproj, al lado y con su nombre (la regla del IDE). EL
  compositor: estaba escrito tres veces (dos en el build y uno en config). }
function ManifiestoDe(const ADproj: string): string;
{ Si APath es un fichero de DELPHI: lo del motor de Pascal (EsDelMotorPascal:
  fuentes y designers) o un proyecto del IDE (PROJECT_EXTS). Lo que
  delphi_textedit no edita y lo que el changeset no mueve ni borra suelto -
  eso lo hacen delphi_move y delphi_delete enteros (B de la 1.19.2) -. Estaba
  escrito en ExtGate (Lsp.TextEdit); a la segunda, aqui. }
function EsFicheroDeDelphi(const APath: string): Boolean;
{ Las mascaras de fichero de una de esas listas ('.dfm' -> '*.dfm'), para
  recorrer una carpeta con ellas. Las escribian a mano Mcp.Tools.Workspace
  (las de delphi_search y delphi_list), Lsp.Rename (las de designer) y
  Lsp.BuildRunner (las de fuente) (revisor propio de la 4.1, 9-oct-2026). }
function MascarasDe(const AExts: array of string): TArray<string>;
{ Donde cayo un cambio entre AAntes y ADespues, para mover los numeros de
  linea de lo que viene despues: ADesde es la primera linea (1-based) del
  texto de ANTES que queda POR DEBAJO de lo cambiado (prefijo y sufijo
  comunes), y ADelta cuanto se movio. Lo de encima no se mueve. UNA regla
  para la tanda (AplicaTanda) y el commit del changeset: el commit movia todo
  por el cambio del fichero ENTERO y editaba la linea equivocada con COMMIT
  COMPLETE (decima revision). LineaTrasCambio aplica el movimiento (0 = sin
  linea, se queda en 0). }
procedure ZonaDelCambio(const AAntes, ADespues: TArray<string>; out ADesde, ADelta: Integer);
function LineaTrasCambio(ALinea, ADesde, ADelta: Integer): Integer;
{ El texto acaba en un salto de linea (LF, CRLF o un CR suelto). Se miraba
  de dos formas (solo LF en delphi_textedit; octava revision). }
function TieneSaltoFinal(const AText: string): Boolean;
{ El NOMBRE de un salto, el que dicen las respuestas: 'CRLF', 'LF' o 'CR'. }
function NombreDelSalto(const ASalto: string): string;

{ El fichero es un fuente Delphi que EXISTE (.pas/.dpr/.dpk/.inc): '' si lo
  es; si no, por este orden, carpeta (LSP-016), no esta (LSP-011) o no es
  Pascal (LSP-017). UNA regla para las siete tools del LSP: symbols decia
  "no es un fuente ()" de una carpeta y references mandaba un .txt al motor
  (quinta revision). La jaula va antes y la pone quien llama. }
function NoEsFuenteDelphi(const APath: string): string;

{ LO QUE delphi_edit EDITA, en una puerta: '' si APath es un fuente o un form
  de texto; si no, la negativa (una carpeta, otra extension, un binario, una
  copia de la papelera, de __history o de __recovery). La preguntan una
  edicion (ExecutePatch) y la tanda de delphi_edit A LA ENTRADA, para todas
  sus entradas: la rama de bloque de la tanda (ApplyBlockEdit) no pasa por
  ExecutePatch y escribia un .md (medido el 10-oct-2026). La jaula va antes y
  la pone quien llama. }
function FicheroQueNoEditaDelphiEdit(const APath: string): string;

{ EL motor de tandas, escrito UNA vez.

  Aplica un array JSON de ediciones sobre UN fichero, EN ORDEN y TODO O NADA:
  parsea, pre-resuelve los "occurrence" contra el fichero ORIGINAL y los
  arrastra segun las entradas anteriores anaden o quitan lineas, maneja las
  anclas de bloque, acumula el eco y, si una falla, devuelve el fichero byte a
  byte. Lo unico que NO sabe es como se aplica UNA edicion suelta: eso lo pone
  quien llama, y es la unica linea en la que las dos tools se diferencian.

  Por que existe: esto vivia DUPLICADO en Mcp.Tools.DelphiPatch.ApplyEdits
  (delphi_edit) y en Lsp.TextEdit.TextEditsNucleo (delphi_textedit) - 132 y
  140 lineas con 103 identicas, un 78%. Y lo que cambiaba era cosmetico: el
  tipo del registro de argumentos, la llamada al motor de una edicion, y las
  variables renombradas al castellano (One/Una, Failed/Fallo,
  Snapshot/Copia), que es lo que impedia verlas como gemelas al leerlas.

  El precio de esa duplicacion se pago el 2026-09-20: el bug de "occurrence"
  -recontar sobre el fichero ya mutado, escribir en la linea equivocada y
  contestar OK- habia que arreglarlo DOS veces, y la segunda solo aparecio
  porque la sonda de verificacion uso por casualidad la tool que no se habia
  tocado. Con un solo motor, esta familia entera tiene una sola puerta. }
type
  TAplicaUnaEdicion = reference to function(const AOld, ANew: string;
    AAtLine, AToLine: Integer; ADelete: Boolean): string;

function AplicaTanda(const APath, AEditsJson: string;
  const AAplicaUna: TAplicaUnaEdicion): string;

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
                  devolverlas (Lsp.Guard.EnCasaDeEntregables: su temporal, la
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

type
  { Un valor que EscribeClaveDelIde pone en una clave del IDE: texto o entero }
  TValorDelIde = record
    Nombre: string;
    Texto: string;
    Entero: Integer;
    EsEntero: Boolean;
  end;

function ValorDeTexto(const ANombre, ATexto: string): TValorDelIde;
function ValorEntero(const ANombre: string; AEntero: Integer): TValorDelIde;

{ LA puerta de escribir del REGISTRO del IDE, la gemela de EscribeBytes con
  el IDE como lugar: AValores en la clave SOFTWARE\Embarcadero\BDS\<AVersion>\
  <ASubclave> del usuario (se crea si no esta; sus otros valores no se tocan).
  La que ya estaba se exporta ANTES a la casa del servidor con reg.exe - el
  exportador de Windows: abrir la copia la devuelve - por el nombrador de las
  copias del IDE (FicheroDeClaveDelIde), y la que ya dice esos valores ni se
  escribe ni se copia (A4). Devuelve la copia, '' si no hubo. Lanza si no pudo
  copiar o escribir: sin copia no se toca (V10, 24-oct-2026: los asientos de
  SDKs y perfiles se pisaban y se borraban sin copia). }
function EscribeClaveDelIde(const AVersion, ASubclave: string;
  const AValores: array of TValorDelIde): string;
{ ...y BORRAR una clave del IDE entera (con sus subclaves), exportada antes
  igual. '' si no estaba. Lanza si no pudo copiar o borrar. }
function BorraClaveDelIde(const AVersion, ASubclave: string): string;

{ Un fichero de las caches del servidor (la configuracion fabricada para el
  motor, las tablas del disenador) por la puerta, con la casa como lugar, en
  UTF-8 con BOM. Si no se pudo (otro hilo la esta leyendo) y el fichero que
  esta ya dice ese mismo texto, vale el que esta; si no - otra cache, o
  la puerta que niega el sitio -, se lanza. Vivia en Lsp.Casa con su propia
  pregunta de "dentro". }
procedure EscribeEnCasaDelServidor(const AFichero, ATexto: string);

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
  el disco no cuenta (el ensayo de un create tras un delete del mismo lote). }
procedure PatchSaveText(const APath, AText, AEncName: string; AEnsayo: Boolean = False;
  ANuevo: Boolean = False);
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

{ El "eol" de quien crea un fichero: '' si vale (crlf, lf, o vacio = crlf); si
  no, la negativa. UNA regla para delphi_textedit y delphi_edit createunit: la
  segunda aceptaba "mac" y creaba en CRLF (tercera revision, 27-sep-2026). }
function EolDesconocido(const AEol: string): string;
{ ...y su inversa: el salto que ese "eol" pide (#10 con lf; #13#10 con crlf o
  vacio). Los dos create lo traducian a mano en cinco sitios, cada uno con su
  SameText(..., 'lf') (S1, A38 de la 1.23); su nombre, NombreDelSalto. }
function SaltoPedido(const AEol: string): string;

{ Lo escrito, releido del disco para el eco de verificacion. Si otro proceso
  lo coge justo despues y no se puede releer, la escritura YA se hizo: se
  devuelven los bytes escritos y ANota lo dice. Salia INTERNAL con el cambio
  aplicado, y quien obedece repetia una edicion ya hecha (verificacion de la
  tercera ronda, medido). Nunca lanza. }
function RelecturaDe(const APath: string; const AEscrito: TArray<Byte>;
  out ANota: string): TArray<Byte>;

{ ReadNumbered para el eco de lo que se acaba de escribir: si no se puede
  releer, lo dice en vez de lanzar (la escritura ya se hizo). }
function EcoNumerado(const APath: string; AFrom, ATo: Integer): string;

{ Los MODOS de una llamada de delphi_edit / delphi_textedit que no combinan:
  con mas de uno, la negativa (INVALID_PARAM); '' si hay uno o ninguno. Se
  descartaba uno en silencio y se contestaba OK (adduses+removeuses solo
  anadia; edits+old solo aplicaba la tanda; quinta revision). UNA regla para
  las dos tools: cada una dice que modos le llegaron. }
function ModosQueNoCombinan(const AModos: array of string): string;

{ Un "content" de unit que no vale: sin "unit X;", con otro nombre que el
  del fichero, o sin "end." (la negativa; '' si vale). UNA regla para
  delphi_create y delphi_edit createunit: la segunda creaba Nueva.pas con
  "unit Otra;" contestando CREATED (quinta revision). }
function ContenidoDeUnitNoValido(const AUnitName, AContent: string): string;

{ AMsg y detras, en su linea, el aviso EDIT-091 de cada comentario de llave
  con otra llave dentro en ANuevo -el fuente ENTERO que el agente acaba de
  escribir en APath-. Para los que escriben un
  fuente ENTERO con el content del agente (delphi_create, delphi_edit
  createunit): solo lo auditaban los motores de edicion, y una unit nueva
  con el ejemplo de un comentario entre llaves no compilaba sin que nadie lo
  dijera (6-oct-2026, Lsp.Listas: E2065 tres veces). }
function ConAvisosDeLlaves(const AMsg, APath, ANuevo: string): string;

{ Encoding for NEW Delphi files, honouring the IDE's configured default
  (Tools > Options > Editor): 'utf8-bom' when the IDE is set to UTF-8,
  the machine's ANSI page (EncName(ekAnsi), 'cp1252' on a Western Windows)
  when ANSI. }
function NewFileEncName: string;
{ La codificacion en que NACE un fichero, la de todo el que crea uno: un
  fuente o un form, la del IDE (NewFileEncName; un form la ajusta
  EncDeFormNuevo, y una ANSI que no cabe, EncAlEscribir al escribir); el XML
  del IDE (EsXmlDelIde: proyecto, grupo, manifiesto), UTF-8 con BOM, como lo
  escriben el IDE y nuestro generador del manifiesto; lo demas, UTF-8 sin BOM
  (git no quita un BOM: un .gitignore con el romperia su primera regla). Eran
  tres reglas: delphi_create, el create de un changeset - que escribia un
  .dproj SIN BOM - y los de delphi_edit y delphi_textedit (A21 de la 1.23). }
function EncDeFicheroNuevo(const APath: string): string;

{ Makes a recoverable copy of a file into __delphi-patch\<date>\ before it is
  overwritten (once per file per day). Returns a note / the backup path.
  Exposed so binary writers (delphi_upload) can be non-destructive too. }
function BackupFile(const APath: string): string;
{ La copia DIARIA que BackupFile hace de un fichero (__delphi-patch\<dia>\
  <nombre>, sin sello): el nombrador, para quien tenga que quitarla porque la
  escritura que la dejo se deshizo (el move de una unit que no acaba). }
function CopiaDiariaDe(const APath: string): string;
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
{ LA pregunta de esos dos escritores, para quien la tiene que hacer ANTES de
  lo que tarda o de lanzar a otro: '' = se colocaria en ADestino; si no, la
  negativa que daria al colocar, y una CARPETA donde va el fichero (el
  renombre la tomaba por "otro proceso lo tiene" tras cinco reintentos). La
  hacia a mano delphi_adb antes del logcat (media: sin la carpeta) y
  delphi_styles build no la hacia: el conversor y brcc32 escribian el
  derivado ellos mismos (1.18.2, 2s). }
function ColocacionDenegada(const ADestino: string; ALugar: TLugarDeTexto = ltJaula): string;
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

type
  { EL lint de un form de texto, sus cinco partes; cada llamador lo presenta a
    su manera (el lint de delphi_designer, lo que sigue a cada escritura del
    disenador, lo que sigue a delphi_edit). Estaba escrito tres veces y el
    parser del IDE habia entrado en dos: delphi_edit sobre un .fmx no le
    preguntaba, la puerta del 8-oct (revisor 2 de la noche, M-B). }
  TLintDeForm = record
    Parser: string;              // DSGN-123, o '' si el parser del IDE lo lee
    Propiedades: TArray<string>; // las propiedades contra la tabla del framework
    Notas: TArray<string>;       // lo que la tabla no pudo comprobar (terceros)
    Falta: TFaltaTabla;          // sin tabla: por que
    Enlace: TArray<string>;      // el form contra su clase (Lsp.DesignerBinding)
    // las lineas que la tabla dejo SIN juicio (sin hoja de tipo: lo que la
    // clase guarda por codigo), lo que el LECTOR del IDE dijo de ellas al
    // cargar el form (con ALector) y por que no se le pudo preguntar
    // (DSGN-061 de la 1.20)
    SinJuez: Integer;
    Lector: TArray<string>;
    SinLector: string;
  end;

{ El lint del form ADfm con el TEXTO ATexto (lo que dice o dira el disco, en
  AEnc): la tabla del Delphi activo (Lsp.DesignerMeta, con su espera), el
  form contra su clase y EL parser del IDE con esos bytes (AJuzga=False en un
  binario, que ya paso su conversion). Con ALector, si la tabla no encontro
  nada y dejo lineas sin juicio, el form entero al LECTOR del IDE
  (Lsp.FormRender.LoQueNoCargaElIde, el juez de set): lo piden el lint y el
  juicio de lo escrito; designer set/insert/delete tienen el suyo. Nunca
  lanza. }
function LintDeForm(const ADfm, ATexto, AEnc: string; AJuzga: Boolean;
  AEsperaMs: Cardinal = ESPERA_TABLA_MS; ALector: Boolean = False): TLintDeForm;

{ Los avisos de una respuesta del motor (ExecutePatch, ExecuteTextEdit): las
  lineas desde el primer aviso marcado *** (la marca va detras de la
  etiqueta: MsgCuerpo) hasta el final, que es donde el motor los pone
  (detras del eco), con lo que cada uno lleva debajo - la lista de
  propiedades de EDIT-076, la del binding. Lo leen la tanda y el changeset,
  que resumen cada edicion en una linea: los dos se quedaban solo con las
  lineas *** (revisor 2 de la noche, B-8). }
function AvisosDelMotor(const ARespuesta: string): TArray<string>;

{ El juicio de un form de texto ESCRITO (ATexto, en AEnc), como avisos de una
  edicion: la nota EDIT-084 y lo que dice DesignerLint (el parser del IDE, las
  propiedades, el enlace con su clase, la nota de form ancho). Vacio si APath
  no es un designer. Lo hacen los escritores en cada edicion suelta, y la
  tanda y el changeset UNA vez al final (AplazaJuicioDeForm). }
function JuicioDeForm(const APath, ATexto, AEnc: string): TArray<string>;
{ El juicio de lo que escribir APath ALCANZA: el de su form si es un designer
  (JuicioDeForm), o el de los forms de su UNIDAD si es un .pas: solo su enlace
  con la clase - el .pas lo rompe tambien; el texto del form, su parser y sus
  propiedades no cambiaron - y sin la nota EDIT-084, que decia "edited" de un
  form que nadie toco (en vivo tras el H6 de la 1.18.2). Cada linea de un form
  de la unidad lleva su ruta delante. AOmite: los forms que no se juzgan aqui
  (el changeset juzga por si mismo el que tambien escribio). Un delphi_edit
  suelto de un .pas que rompia el enlace no decia nada (punto 7). EL juicio
  de los escritores sueltos, de la tanda y del changeset. }
function JuicioDeLoEscrito(const APath, ATexto, AEnc: string;
  const AOmite: TArray<string> = nil): TArray<string>;
{ Lo que el LECTOR del IDE dice del form APath tal como quedo en disco,
  cuando la tabla calla (LintDeForm con ALector): la cabecera EDIT-127 y sus
  lineas, o nada. Se pide FUERA del cerrojo de escritura (EnterFileEdit): el
  lector es un proceso que tarda segundos, y dentro paraba las escrituras de
  todos - como el juez del orden del disenador (revisor 5 de la noche, A3).
  Por eso no va en JuicioDeLoEscrito, que corre dentro: lo piden las tools
  que escriben forms al acabar (delphi_edit, el changeset, upload).
  DSGN-061 de la 1.20. Nunca lanza. }
function AvisosDelLector(const APath: string): TArray<string>;
{ ARespuesta (la de una escritura de APath) con AvisosDelLector detras, si
  APath es un form y no fue un fallo. }
function ConAvisosDelLector(const ARespuesta, APath: string): string;
{ Una edicion SUELTA cuyo ancla trae VARIAS lineas es un BLOQUE: la tanda de
  UNA entrada, la que el propio EDIT-001 mandaba escribir. Hermes tropezo con
  esa negativa 14 veces (12 salieron en la llamada siguiente) y Claude dos el
  16-oct: una llamada perdida cada vez, para algo que el motor ya sabia hacer
  (EDIT-001 de la 1.20). Devuelve la tanda en JSON con lo que trae la suelta:
  new (delete = un new vacio: el bloque se quita, como en edits) y atline
  (donde empieza). '' si no es eso - una linea, un fragmento, delete con new -
  y la suelta sigue su camino. Con toline no hay bloque que valga: EDIT-020 en
  ANegativa. Lo usan las dos gemelas, delphi_edit y delphi_textedit. }
function TandaDeUnBloque(const AOld, ANew, AFragment: string; AAtLine, AToLine: Integer;
  ADelete: Boolean; out ANegativa: string): string;
{ El SIGNIFICADO de old/new de una edicion suelta o de una entrada de tanda,
  escrito UNA vez (D7 de la auditoria de duplicados, 1.21.4: estaba en los
  dos gemelos y en sus dos tandas, donde ya vivio el bug de occurrence): old
  dado = hay ancla; old dado con new vacio = dejar la linea en blanco
  (legitimo); sin old y con new lo caza la puerta de reescritura entera del
  motor. test_paisaje vigila que nadie lo vuelva a escribir. }
procedure SignificadoDeOldNew(const AOld, ANew: string; out AHasOld, AHasNew: Boolean);
{ LA regla de delete:true, la de las dos gemelas y la de cada entrada de una
  tanda, de una linea o de un bloque: el ancla (old) o, para una linea EN
  BLANCO, su numero (atline), y sin "new": lo que se borra no se sustituye.
  '' si vale. Estaba en ExecutePatch (EDIT-056/057) y en TextEditNucleo con
  otro codigo (TEXT-003) y SIN lo de new: delphi_textedit borraba la linea y
  tiraba new, y en un bloque de una tanda delete no se leia y el bloque pasaba
  a ser new (Fable, revision de la 1.22.2). }
function DeleteDeLineaDenegado(AHasOld: Boolean; const AOld, ANew: string; AAtLine: Integer): string;
{ Con "fragment", lo que NO puede venir en la misma llamada - el primero que
  venga: old, delete, toline, y los modos propios de quien llama (createunit,
  restore, insert; create; occurrence en una tanda), ya decididos en
  AModosPropios -, para que FragmentoALinea lo niegue por su nombre. '' si
  nada. La escalera estaba en ExecutePatch, en TextEditNucleo y en la tanda
  (D7). }
function OtroModoConFragmento(AHasOld: Boolean; const AOldLine: string; ADelete: Boolean;
  AToLine: Integer; const AModosPropios: string): string;
{ La nota de un fichero EN DISCO que es UTF-8 sin BOM y que dcc lee en ANSI
  (READ-008 de un fuente, READ-009 de un form), por la puerta de leer y EL
  detector: la de delphi_read, para quien no lo lee entero (designer lint).
  '' si no es el caso o no se puede leer. }
function NotaDeUtf8SinBomDe(const APath: string): string;
{ LA nota de codificacion de un form en disco (encodingNote): la de uno ANCHO
  (UTF-16/32, DSGN-121: el IDE no lo carga ni dcc lo compila, y la salida es
  to-text) o, si no, la de uno SIN BOM cuyos bytes son UTF-8 (READ-009: el IDE
  y dcc lo leen en ANSI); '' si nada que decir o no se puede leer. La
  componian tres emisores (lint y los escritores del disenador, preview y el
  lint de delphi_edit/tanda/changeset) y dos sin READ-009 (W9 del revisor de
  cierre de la 1.18.2). La del ancho la dicen ya solo quienes escriben el
  TEXTO; el disenador lo niega (FormAnchoQueNoCarga). }
function NotaDeCodificacionDeForm(const APath: string): string;
{ LA negativa de los comandos del disenador que necesitan que el IDE cargue
  el form (lint, preview, to-binary, insert, set, delete): si APath es un form
  de texto ancho (Lsp.DesignerBin.FormAncho) y EL parser lo niega con sus
  bytes tal cual, leidos por la puerta (LeeBytes), DSGN-122 con lo que dijo;
  si no, ''. El parser decide (norma 6) y el BOM solo dice la causa.
  Convertirlo antes de preguntar era lo que hacia que lint diera CLEAN y
  preview dibujara lo que el IDE no abre (A28 de la 1.23). Lo que la puerta
  no deja leer no se niega aqui: lo dice el comando que sigue. }
function FormAnchoQueNoCarga(const APath: string): string;
{ Mientras dure (True ... False, anidable, de ESTE hilo: las llamadas HTTP van
  a la vez), los escritores no juzgan el form en cada edicion: el juicio es
  del fichero ENTERO, como la estructura, y lo hace quien agrupa sobre lo que
  quedo escrito (H6 de Hermes, 1.18.2: cada entrada juzgaba su estado
  intermedio, y un renombre .dfm + .pas por changeset daba DSGN-021 "Fix it
  before deploying" de un form que acababa limpio). }
procedure AplazaJuicioDeForm(AAplaza: Boolean);

{ La codificacion en que nace un form NUEVO (APath .dfm/.fmx; otra cosa
  devuelve AEnc sin mirar): AEnc, la que eligio quien escribe (la del IDE),
  si EL parser del IDE lee ATexto en ella; si no, UTF-8 con BOM si en esa si
  lo lee - con el IDE en ANSI un nombre de form acentuado nacia ilegible y
  desde entonces toda escritura del disenador daba DSGN-125 -; si no lo lee
  en ninguna, AEnc y AError con lo que dice el parser (ALinea, ACita): quien
  escribe decide si eso niega o avisa. Los dos escritores de un form nuevo:
  delphi_create (revisor 2 de la noche, B-7) y el create de un changeset (su
  gemelo, revisor 3, M-3). }
function EncDeFormNuevo(const APath, ATexto, AEnc: string; out AError: string;
  out ALinea: Integer; out ACita: string): string;

{ El nombre ORIGINAL de una copia de la papelera, o '' si ese nombre no lleva
  sello. Solo tiene sentido DENTRO de __delphi-patch.

  delphi_delete aparca los ficheros como "UFicha.pas-215825250": el sello de
  hora va DETRAS de la extension, que es lo que impide que dos borrados del
  mismo fichero se pisen... y lo que rompe a todo el que mire la extension.
  Quita tambien los sellos ENCADENADOS ("-215825250-215841305"), que es lo que
  deja restaurar algo ya restaurado.

  Medido el 2026-09-20 usando el servidor como cliente: TRES sintomas, UNA
  causa, y cada uno se habria "arreglado" por su lado en el sitio equivocado.
  - delphi_list includetrash=true ensenaba las copias de seguridad y NO lo
    BORRADO, que es justo lo que promete: la mascara *.pas no casa contra
    "UFicha.pas-215825250".
  - restaurar la unit de un formulario dejaba el .dfm dentro de la papelera:
    el camino de "esto es una unit" mira la extension, leia ".pas-215825250" y
    no entraba. Quedaba una unit sin su designer, que el IDE ya no abre.
  - restaurar hacia una copia de la copia DENTRO de la papelera, con el sello
    doblado. }
function TrashOriginalName(const AName: string): string;

{ EL NOMBRADOR de la papelera. Un solo sitio compone, un solo sitio lee, y el
  lector (TrashOriginalName) es la INVERSA de este.

  Por que existe, medido el 2026-09-20 contestando a David: habia TRES sitios
  componiendo rutas dentro de __delphi-patch con TRES convenciones distintas -
  "UFicha.pas-215825250" al borrar, "UMain.pas" a secas al editar, y
  "UMain.pas.antes-restaurar-221530" al restaurar-. El lector solo entendia la
  primera, asi que la copia previa a un restore ni la encontraba
  includetrash (la mascara *.pas-* no casa con ".pas.antes-restaurar-") ni se
  podia restaurar bien. Se habia arreglado el borde y dejado el punto.

  La regla: el sello SIEMPRE es '-hhnnsszzz' detras del nombre completo, y lo
  que distingue una copia de otra es la CARPETA, no el nombre. Asi el lector
  sirve para todas y una copia nueva no puede inventarse una convencion. }

{ El nombre de una copia: el nombre real + el sello. La unica forma. }
function TrashStampedName(const AName: string): string;

const
  { Los CAJONES de la papelera de un dia (TrashDayDir): en que carpeta cae una
    copia sellada. El nombre lo pone TrashStampedName; lo que distingue una
    copia de otra es su cajon, no su nombre. Estaban escritos a mano
    ('deleted' en Mcp.Tools.FileOps, 'before-restore' en el restore). }
  CAJON_BORRADOS = 'deleted';                  // delete, changeset delete, la copia previa de move
  CAJON_ANTES_DE_RESTAURAR = 'before-restore'; // lo que habia antes de un restore
  CAJON_SUSTITUIDOS = 'replaced';              // lo que habia antes de pisar un fichero ENTERO
  CAJON_CORRUPTOS = 'corrupt';                 // la subida que no casa con su sha256 (UPLOAD-011)

{ La ruta de una copia SELLADA de APath en el cajon ACajon de su papelera,
  por la puerta de escribir sobre la ruta REAL (lanza la negativa): un
  __delphi-patch que fuera un enlace se llevaba la copia FUERA de la jaula
  (quinta revision). Vivia en Mcp.Tools.FileOps, donde Lsp.Changeset no la
  alcanzaba, y el restore la escribia aparte, a mano. }
function TrashPathFor(const APath, ACajon: string): string;

{ Guarda el contenido ACTUAL de APath (un fichero) sellado en ACajon, con su
  marca de dueno, y devuelve la ruta de la copia ('' si no habia fichero).
  Para todo lo que PISA o BORRA un fichero entero: la copia de BackupFile es
  UNA por fichero y dia -la version previa al primer cambio-, asi que lo
  escrito despues se perdia al sustituirlo o borrarlo (sexta revision, medido:
  changeset delete tras dos ediciones dejo solo la de la manana). Lanza si no
  se puede: pisar sin copia no se hace. }
function GuardaContenidoActual(const APath: string;
  const ACajon: string = CAJON_SUSTITUIDOS): string;

{ Deja "<copia>.by" con el agente que la tiro; sin identidad, nada. }
procedure WriteOwnerMarker(const ATrash: string);
{ El agente dueno de una copia, '' si no consta. }
function TrashOwner(const APath: string): string;

implementation

uses
  System.Math,
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.IOUtils,
  System.JSON,
  // AplicaTanda: el motor de tandas vive aqui desde 2026-09-20
  System.SyncObjs,
  System.Generics.Collections,
  System.RegularExpressions,
  Winapi.Windows,
  Winapi.ActiveX, // CoInitializeEx: COM en el hilo de la llamada, como Lsp.Chm
  Winapi.msxml, // MSXML 6, el parser del IDE: el juez de lo que se escribe como XML
  Lsp.Guard,
  Lsp.Discovery,
  Lsp.Texts,
  MCPServer.Serializer, // MotivoEntero / MotivoBooleano: la regla de un parametro, UNA
  Lsp.DesignerBin,
  Lsp.DesignerForma, // EsDesignerFmx: de que marco es un designer
  Lsp.DesignerBinding,
  Lsp.ProjectUnits,
  Lsp.NetDrives,
  Lsp.Pascal, // LlavesAnidadas, VistaPascal: el lexico Pascal de la casa
  Lsp.PascalDecl, // EL lector de clases (insert=metodo)
  Lsp.Regex,
  Lsp.Scaffold,
  Lsp.Rutas,
  Lsp.Lugares, // LugaresDelIde: lo que las puertas admiten del IDE
  Lsp.Casa,
  Lsp.Settings,
  Lsp.Identidad,
  Lsp.TodoONada,
  Lsp.Args,
  Lsp.ShaCache, // Sha256DeBytes: la huella del origen de una llamada
  Lsp.Mascara,
  System.Character,
  Lsp.Client,
  Lsp.FormRender, // LoQueNoCargaElIde: el lector del IDE juzga lo que la tabla no (LintDeForm)
  System.Win.Registry, // EscribeClaveDelIde: la puerta del registro del IDE
  Lsp.BuildRunner,     // RunCaptured: reg.exe, la copia de una clave
  Lsp.ProcessLaunch;   // EnComillas: los argumentos de esa linea

const
  MAX_EDITS = 50; // entradas de una tanda
  { LOS campos de una entrada de "edits": los que la tanda lee y los que
    dice EDIT-012. Estaban escritos dos veces (la comprobacion y el
    mensaje), y las descripciones de delphi_edit y delphi_textedit los
    nombran: test_docs_tokens los saca de EDIT-012 y mira que las dos los
    digan todos (4-oct-2026). }
  CAMPOS_DE_UNA_EDICION: array [0 .. 6] of string = ('old', 'new', 'atline',
    'toline', 'delete', 'occurrence', 'fragment');
  MAX_READ_LINES = 400;
  // las directivas de la CABECERA de una rutina: DIRECTIVAS_DE_RUTINA, del
  // lexico (Lsp.Pascal); aqui habia otra lista, sin noreturn ni unsafe
  // SOURCE_EXTS / DESIGNER_EXTS / PROJECT_EXTS: en el interface

var
  GLock: TCriticalSection;

var
  GIdeUtf8Loaded: Boolean = False;
  GIdeUtf8: Boolean = False;

{ The IDE's configured default encoding, cached (registry, active install). }
function IdeWantsUtf8: Boolean;
var
  Info: TRadStudioInfo;
begin
  if not GIdeUtf8Loaded then
  begin
    Info := DiscoverRadStudio;
    if Info.Found then
      GIdeUtf8 := IdeDefaultUtf8(Info.Version);
    GIdeUtf8Loaded := True;
  end;
  Result := GIdeUtf8;
end;

function NewFileEncName: string;
begin
  if IdeWantsUtf8 then
    Result := 'utf8-bom'
  else
    Result := EncName(ekAnsi);
end;

function EncDeFicheroNuevo(const APath: string): string;
begin
  if EsDelMotorPascal(APath) then
    Result := NewFileEncName
  else if EsXmlDelIde(APath) then
    Result := 'utf8-bom'
  else
    Result := 'utf8';
end;

function LeadingWhite(const S: string): string;
var
  I: Integer;
begin
  I := 1;
  while (I <= Length(S)) and ((S[I] = ' ') or (S[I] = #9)) do
    Inc(I);
  Result := Copy(S, 1, I - 1);
end;

function SangriaDeLaLineaEn(const ATexto: string; APos: Integer): string;
var
  Ini: Integer;
begin
  Ini := APos;
  while (Ini > 1) and not CharInSet(ATexto[Ini - 1], [#10, #13]) do
    Dec(Ini);
  Result := LeadingWhite(Copy(ATexto, Ini, APos - Ini));
end;

function SangraComoLaLinea(const ALinea, AAncla: string;
  const ANuevas: TArray<string>): TArray<string>;
var
  Sangria: string;
  I: Integer;
begin
  Result := Copy(ANuevas);
  Sangria := LeadingWhite(ALinea);
  if (Length(Result) = 0) or (LeadingWhite(Result[0]) <> '') or
     (Length(LeadingWhite(AAncla)) >= Length(Sangria)) then
    Exit;
  for I := 0 to High(Result) do
    if Result[I] <> '' then
      Result[I] := Sangria + Result[I];
end;

function EtiquetaDeCodificacion(K: TEncKind; AEsAscii: Boolean): string;
begin
  if AEsAscii and (K in [ekUtf8, ekAnsi]) then
    Result := MsgText(SF_TEXT_ASCII_COMPATIBLES)
  else
    Result := EncName(K);
end;

function DetectEnc(const B: TBytes; AEsDesigner: Boolean): TEncKind;
begin
  // el BOM de UTF-8 y los de UTF-16 y UTF-32, por EL lector de un BOM (Codificacion).
  // UTF-16 solo por BOM: sin el, ningun fuente Delphi es UTF-16 (el IDE lo
  // escribe siempre con marca) y adivinarlo por ceros seria otro detector.
  if KindDeBom(B, Result) then
    Exit;
  // un form de texto sin BOM: ANSI (PaginaAnsi, la de la maquina), como lo leen dcc y el parser de forms
  // (medido 9-oct-2026; 4.1 de la 1.18.0). Lo que ya esta se lee y se
  // escribe con los mismos bytes, y un acento nuevo va como dcc lo lee
  if AEsDesigner then
    Exit(ekAnsi);
  // Pure ASCII without BOM is ambiguous: honour the encoding the IDE is
  // configured to use (Tools > Options > Editor). Guessing the other way
  // writes the first new accent in the wrong codec and the IDE shows
  // mojibake - in BOTH directions (measured). Para un FUENTE o un texto (M4) esto es solo
  // como se lee: en que se ESCRIBE su primer caracter no ASCII lo decide
  // EncAlEscribir, como el IDE al guardar (4.1 de la 1.18.0)
  if not HayByteAlto(B) then
  begin
    if IdeWantsUtf8 then
      Exit(ekUtf8);
    Exit(ekAnsi);
  end;
  // UTF-8 cuando TODO byte alto forma secuencias validas (estricto: el juez de
  // la RTL, TEncoding.UTF8.IsBufferValid); si no, ANSI. Asi deciden el IDE
  // (detecta un UTF-8 sin BOM: medido el 9-oct-2026) y TFile.ReadAllText. Una
  // regla propia de "UTF-8 danado" contradecia a los dos y dejaba sin editar
  // un ANSI legitimo (revisor propio de la 4.1; David: "si hay juez lo
  // seguimos hasta que se demuestre que el juez es tonto")
  if ValidUtf8(B, 0) then
    Result := ekUtf8
  else
    Result := ekAnsi;
end;

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
    if SameText(GOrigenes[I].Ruta, APath) then
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
    if SameText(GOrigenes[I].Ruta, APath) then
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

function Measure(const B: TBytes): TMetrics;
var
  I, Start: Integer;
  K: TEncKind;
  Cuerpo: TBytes;
begin
  Result := Default(TMetrics);
  Result.Bytes := Length(B);
  // El BOM es fontaneria del fichero, no texto: contar sus bytes como
  // "acentos" confundia la cuenta que ve el agente (medido). Cuantos bytes
  // son lo dice el MISMO detector que decide la codificacion, no otro if.
  K := DetectEnc(B);
  Cuerpo := B;
  Start := PreambleLen(K);
  if K in ENC_ANCHAS then
  begin
    // En UTF-16 (y UTF-32) cada caracter son dos (cuatro) bytes: un 0D 00 0A 00 no es un CRLF
    // byte a byte. Se mide el cuerpo en UTF-8, las mismas cuentas que un
    // fichero utf8 (un acento = 2 bytes altos); HighCount hace lo mismo.
    Cuerpo := EncodeText(DecodeBytes(B, K), ekUtf8, False); // medir, no escribir
    Start := 0;
  end;
  for I := Start to High(Cuerpo) do
  begin
    if Cuerpo[I] = 13 then
      Inc(Result.CR)
    else if Cuerpo[I] = 10 then
    begin
      Inc(Result.LF);
      if (I > 0) and (Cuerpo[I - 1] = 13) then
        Inc(Result.CRLF);
    end
    else if Cuerpo[I] > 127 then
      Inc(Result.High);
    if (I + 2 <= High(Cuerpo)) and (Cuerpo[I] = $EF) and (Cuerpo[I + 1] = $BF) and (Cuerpo[I + 2] = $BD) then
      Inc(Result.Corruption);
  end;
  Result.Loose := Result.LF - Result.CRLF;
end;

function Summary(const M: TMetrics): string;
begin
  // "saltos" and not "lineas": this counts LINE BREAKS, and a file whose last
  // line ends in one has one more line than it has breaks. Calling it lines
  // put "lineas=38" three words away from "Lineas 1-39 de 39" in the same
  // answer, and the reader had to decide which of the two was lying
  // (measured 2026-08-25). Neither was: they counted different things.
  // los saltos son LF y CR suelto: un fichero de solo CR decia breaks=0
  Result := MsgFmt(SF_EDIT_METRICAS_FMT,
    [M.Bytes, M.LF + M.CR - M.CRLF, M.CRLF, M.Loose, M.High, M.Corruption]);
end;

{ Lo que dicen los contadores en las respuestas (la cabecera de una lectura,
  el eco de una escritura): cuando no hay nada que mirar -sin U+FFFD, sin CR
  suelto, un solo tipo de salto- basta 'audit=clean' con los acentos; los
  contadores enteros (Summary), solo cuando algo no cuadra. Iban siempre,
  dos veces en cada edicion (revisor de tokens, 4-oct-2026). }
function Limpio(const M: TMetrics): Boolean;
begin
  Result := (M.Corruption = 0) and (M.CR = M.CRLF) and ((M.Loose = 0) or (M.CRLF = 0));
end;

function Auditoria(const M: TMetrics): string;
begin
  if Limpio(M) then
    Result := MsgFmt(SF_EDIT_AUDITORIA_LIMPIA_FMT, [M.High])
  else
    Result := Summary(M);
end;

// El antes y el despues de una escritura: una linea si los dos estan limpios
function AuditoriaAntesYDespues(const AAntes, ADespues: TMetrics): string;
begin
  if Limpio(AAntes) and Limpio(ADespues) then
    Result := '  ' + Auditoria(ADespues)
  else
    Result := MsgFmt(SF_EDIT_ANTES_DESPUES_FMT, [Summary(AAntes), Summary(ADespues)]);
end;

{ Lines (1-based) carrying a mojibake signature: a UTF-8 lead byte followed
  by a continuation byte, "read" as ANSI chars (e.g. 'A-tilde+3' for 'o
  acute'). Measured: models IMITATE corrupt context in their new text. }
function MojibakeLines(const T: string): TArray<Integer>;
var
  L: TList<Integer>;
  Lines: TArray<string>;
  I, J, B1, B2: Integer;

  // De que byte pudo salir C al leer mal UTF-8: su byte ANSI (la regla
  // del codificador, ByteCp) y, si no tiene, el de la lectura Latin-1, que
  // da cada byte de 80 a FF tal cual (la E acentuada mayuscula es U+00C3 U+0089;
  // la tipografia E2 80 xx, U+00E2 U+0080 ...). Son dos preguntas: unirlas en ByteCp
  // dejo de ver ese mojibake (revisor propio, 9-oct-2026). Hasta FF: en una
  // maquina que no es 1252 la o con tilde leida en Latin-1 (U+00C3 U+00B3) no
  // tiene byte ANSI y se escribia sin aviso (medido el 24-oct-2026 con el
  // servidor en la 1251); en la 1252, de A0 a FF las dos dan el mismo byte
  function ByteLeido(C: Char): Integer;
  begin
    Result := ByteCp(C);
    if (Result < 0) and (Ord(C) >= $80) and (Ord(C) <= $FF) then
      Result := Ord(C);
  end;

begin
  L := TList<Integer>.Create;
  try
    Lines := SplitToLines(T); // el troceador de todos (el CR suelto es salto)
    for I := 0 to High(Lines) do
      for J := 1 to Length(Lines[I]) - 1 do
      begin
        B1 := ByteLeido(Lines[I][J]);
        B2 := ByteLeido(Lines[I][J + 1]);
        if (B1 >= $C2) and (B1 <= $F4) and (B2 >= $80) and (B2 <= $BF) then
        begin
          L.Add(I + 1);
          Break;
        end;
      end;
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

procedure EnterFileEdit;
begin
  GLock.Enter;
end;

procedure LeaveFileEdit;
begin
  GLock.Leave;
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

function EcoNumerado(const APath: string; AFrom, ATo: Integer): string;
begin
  try
    Result := ReadNumbered(APath, AFrom, ATo);
  except
    on E: Exception do
      Result := MsgFmt(SN_EDIT_RELECTURA_FALLIDA_FMT, [MaskDriveText('', E.Message)]);
  end;
end;

function ContenidoDeUnitNoValido(const AUnitName, AContent: string): string;
var
  Nombre: string;
  Ini, Largo: Integer;
begin
  Result := '';
  // la cabecera (EL lector: CabeceraDeUnit) y el end., los del CODIGO: con
  // su regex sobre el texto, un 'unit Vieja;' comentado encima negaba la
  // unit por su nombre y un end. comentado pasaba por el final (revision de
  // la 1.10.0, medido con delphi_create kind=unit content=)
  if not CabeceraDeUnit(AContent, Nombre, Ini, Largo) then
    Exit(MsgText(SR_CREATE_CONTENT_NOUNIT));
  if not MismoIdentificador(Nombre, AUnitName) then // (Lsp.Pascal: tambien la caja de un acento)
    Exit(MsgFmt(SR_CREATE_CONTENT_NAME_FMT, [Nombre, AUnitName]));
  if Length(EndsConPunto(CodigoPascal(AContent))) = 0 then
    Exit(MsgText(SR_CREATE_CONTENT_NOEND));
end;

function ModosQueNoCombinan(const AModos: array of string): string;
var
  Presentes: TArray<string>;
  M: string;
begin
  Result := '';
  Presentes := [];
  for M in AModos do
    if M <> '' then
      Presentes := Presentes + [M];
  if Length(Presentes) > 1 then
    Result := MsgFmt(SR_EDIT_MODOS_NO_COMBINAN_FMT, [string.Join(' + ', Presentes)]);
end;

function EolDesconocido(const AEol: string): string;
begin
  Result := '';
  if (AEol <> '') and not MatchText(AEol, ['crlf', 'lf']) then
    Result := MsgFmt(SR_TEXT_EOL_FMT, [AEol]);
end;

function SaltoPedido(const AEol: string): string;
begin
  if SameText(AEol.Trim, 'lf') then
    Result := #10
  else
    Result := #13#10;
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
{ La causa de un rename o un movimiento que Windows nego con ACodigo, por la
  regla de todas (MotivoDelSistema: ocupado SYS-027, acceso denegado
  SYS-028); otro codigo, con el texto de Windows. Se decia "otro proceso lo
  tiene" de CUALQUIER codigo (septima revision). }
function MotivoDeRenombre(const APath: string; ACodigo: DWORD): string;
begin
  Result := MotivoDelSistema(TPath.GetFileName(APath) + ': ' + SysErrorMessage(ACodigo));
  if Result = '' then
    Result := MsgFmt(SR_EDIT_RENAME_ATOMICO_FALLIDO_FMT,
      [TPath.GetFileName(APath), ACodigo, SysErrorMessage(ACodigo).Trim]);
end;

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
  // rebota: se reintenta unos instantes antes de decir que algo lo tiene
  // (verificacion de la tercera ronda: cuatro EDIT-106 con varias sesiones,
  // todos del propio servidor; reintentar funcionaba)
  var Renombrado := False;
  var Codigo: DWORD := 0;
  for var Intento := 1 to 5 do
  begin
    Renombrado := MoveFileEx(PChar(ATmp), PChar(Destino), MOVEFILE_REPLACE_EXISTING);
    if Renombrado then
      Break;
    // el codigo de Windows ANTES de borrar el temporal (despues salia 0)
    Codigo := GetLastError;
    if (Codigo <> ERROR_ACCESS_DENIED) and (Codigo <> ERROR_SHARING_VIOLATION) and
       (Codigo <> ERROR_LOCK_VIOLATION) then
      Break;
    Sleep(100);
  end;
  if not Renombrado then
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

procedure AtomicWrite(const APath: string; const B: TBytes);
var
  Tmp, Motivo: string;
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
  Tmp := TemporalDeSustitucion(APath);
  TFile.WriteAllBytes(Tmp, B);
  SustituyePorRenombre(Tmp, APath);
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

{ El nucleo de ColocaProducto y ColocaContenido: ALocal <> '' mueve ese
  fichero; si no, escribe ABytes. }
procedure Coloca(const ADestino, ALocal: string; const ABytes: TBytes;
  ALugar: TLugarDeTexto);
var
  Motivo, Dir, DirLocal, Tmp, Copia, Ancestro: string;
  Nuestro, Colocado: Boolean;
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
  Nuestro := (ALocal = '') or EnTemporal(ALocal) or SameText(DirLocal, Dir);
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
    // lo que se cree para colocarlo se quita si al final no se coloca
    Ancestro := PrimerAncestroQueExiste(Dir);
    CrearCarpeta(Dir);
    if SameText(DirLocal, Dir) then
      Tmp := ALocal // ya junto al destino (el zip en proceso): un solo rename, con sus reintentos
    else
    begin
      Tmp := TemporalDeSustitucion(ADestino);
      if ALocal = '' then
        TFile.WriteAllBytes(Tmp, ABytes)
      // de la temporal: puede ser otro volumen, tambien con la misma letra
      // (un punto de montaje); MoveFileEx copia cuando hace falta y no lo
      // decide por el TEXTO de la raiz, como TFile.Move
      else if not MoveFileEx(PChar(ALocal), PChar(Tmp), MOVEFILE_COPY_ALLOWED) then
        raise Exception.Create(MotivoDeRenombre(ADestino, GetLastError));
    end;
    // la copia sellada de lo que habia y el rename, sin que otro escritor se
    // cuele entre los dos (dos empaquetados al mismo out= sellaban la misma
    // copia y el zip de en medio se perdia: sexta revision)
    Copia := GuardaContenidoActual(ADestino);
    try
      SustituyePorRenombre(Tmp, ADestino); // si falla, borra el temporal
    except
      // la copia sellada de algo que no se sustituyo no se queda
      if Copia <> '' then
      begin
        try
          BorraLoNuestro(Copia);
          if TFile.Exists(MarcaDeDueno(Copia)) then
            BorraLoNuestro(MarcaDeDueno(Copia));
        except
        end;
      end;
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
  Coloca(ADestino, ALocal, nil, ALugar);
end;

procedure ColocaContenido(const ADestino: string; const ABytes: TBytes;
  ALugar: TLugarDeTexto);
begin
  Coloca(ADestino, '', ABytes, ALugar);
end;

function DesignersDeUnidad(const AUnidad: string): TArray<string>;
begin
  Result := [];
  for var E in DESIGNER_EXTS do
    Result := Result + [ChangeFileExt(AUnidad, E)];
end;

function EsRutaDeDesigner(const APath: string): Boolean;
begin
  Result := MatchText(TPath.GetExtension(APath), DESIGNER_EXTS);
end;

function EsRutaDeEstilo(const APath: string): Boolean;
begin
  Result := SameText(TPath.GetExtension(APath), '.style');
end;

function EsRutaDeFuente(const APath: string): Boolean;
begin
  Result := MatchText(TPath.GetExtension(APath), SOURCE_EXTS);
end;

function EsRutaDeProyecto(const APath: string): Boolean;
begin
  Result := MatchText(TPath.GetExtension(APath), PROJECT_EXTS);
end;

function EsXmlDelIde(const APath: string): Boolean;
begin
  Result := EsRutaDeProyecto(APath) or EsManifiesto(APath);
end;

function EsManifiesto(const APath: string): Boolean;
begin
  Result := APath.Trim.EndsWith(EXT_MANIFIESTO, True);
end;

function ManifiestoDe(const ADproj: string): string;
begin
  Result := TPath.ChangeExtension(ADproj, EXT_MANIFIESTO);
end;

function EsFicheroDeDelphi(const APath: string): Boolean;
begin
  Result := EsDelMotorPascal(APath) or EsRutaDeProyecto(APath);
end;

function MascarasDe(const AExts: array of string): TArray<string>;
begin
  Result := [];
  for var E in AExts do
    Result := Result + ['*' + E];
end;

function CopiaDiariaDe(const APath: string): string;
begin
  // Esta copia NO lleva sello a proposito: es una por fichero y dia, la
  // version previa al primer cambio del dia. Pero la CARPETA la pone el
  // nombrador, como todas.
  Result := TPath.Combine(TrashDayDir(APath, ''), TPath.GetFileName(APath));
end;

{ Makes the pre-edit copy (once per file per day). Returns a note. }
function BackupFile(const APath: string): string;
var
  Dir, DayDir, Dest, Motivo: string;
begin
  Dir := CarpetaDePapelera(APath);
  Dest := CopiaDiariaDe(APath);
  DayDir := TPath.GetDirectoryName(Dest);
  // Lo que DEVUELVE esta funcion es para ENSENARLO (el "copia=" del eco de
  // delphi_edit, la respuesta de delphi_upload), nunca para volver a abrir
  // el fichero: por eso la ruta sale enmascarada, desde el unico sitio que
  // la compone. delphi_edit esta EXENTO del filtro de salida -su eco es
  // contenido literal del disco-, y esto no es eco: es una ruta NUESTRA, y
  // salia con la letra REAL del servidor. Mismo fallo que el "CREADO" de
  // delphi_textedit, en otro emisor de la misma tool; se me escapo el
  // 2026-09-21 por buscar el identificador en vez del FORMATO, y lo canto
  // la propia tool al cortar un release.
  //
  // OJO A DONDE VA LA MASCARA: solo en lo que SALE. Enmascarar la variable
  // Dest antes de usarla deja el TFile.Exists y el TFile.Copy apuntando a
  // una unidad virtual que no existe en el disco - es decir, se carga la
  // copia de seguridad entera. Escrito aqui porque lo hice al primer
  // intento, el mismo dia.
  // La copia se escribe JUNTO al fichero: el fichero y su carpeta de copias
  // pasan la puerta, esta por la ruta REAL (un __delphi-patch que fuera un
  // junction llevaria la copia a donde apunte).
  // la MISMA pregunta que hara el escritor, con el +R incluido: si se va a
  // negar, que se niegue antes de dejar la copia diaria (decima revision)
  Motivo := SustitucionDenegada(APath);
  if Motivo = '' then
    Motivo := EscrituraDenegada(DayDir);
  // la copia es LEER el fichero (un enlace duro: GUARD-041). La segunda
  // barrera: quien edita ya lo leyo por la puerta de leer
  if Motivo = '' then
    Motivo := EnlaceDuroIlegible(APath);
  if Motivo <> '' then
    raise Exception.Create(Motivo);
  if TFile.Exists(Dest) then
    Exit(MsgText(SF_EDIT_COPIA_YA_EXISTIA));
  CrearCarpeta(DayDir);
  // "Existe?" y "copia" no son un solo gesto: dos escrituras del mismo fichero
  // a la vez pasaban las dos por el if y la segunda moria con "Cannot create
  // file ... already exists", RECHAZANDO una edicion perfectamente valida
  // (medido 2026-09-20: era la causa dominante de las ediciones perdidas). La
  // copia ya esta hecha por el otro y vale igual: es la version PREVIA al
  // primer cambio del dia, que es justo lo que promete.
  try
    TFile.Copy(APath, Dest);
  except
    on E: Exception do
      if TFile.Exists(Dest) then
        Exit(MsgText(SF_EDIT_COPIA_YA_EXISTIA))
      else
        raise;
  end;
  PurgeOldBackups(Dir);
  Result := MaskDriveText('', Dest);
end;

function CuantasLineasReales(const ALines: TArray<string>): Integer;
begin
  Result := Length(ALines);
  if (Result > 0) and (ALines[Result - 1] = '') then
    Dec(Result); // la fantasma que deja el salto final
end;

function SplitToLines(const T: string): TArray<string>;
begin
  Result := ConSalto(T, #10).Split([#10]); // el normalizador de todos
end;

function SplitToLinesConSalto(const T: string; out ASaltos: TArray<string>): TArray<string>;
var
  I, N, Ini, K: Integer;
begin
  // primera pasada: cuantas lineas (los mismos cortes que SplitToLines)
  N := 1;
  I := 1;
  while I <= Length(T) do
  begin
    if T[I] = #13 then
    begin
      Inc(N);
      if (I < Length(T)) and (T[I + 1] = #10) then
        Inc(I);
    end
    else if T[I] = #10 then
      Inc(N);
    Inc(I);
  end;
  SetLength(Result, N);
  SetLength(ASaltos, N);
  K := 0;
  Ini := 1;
  I := 1;
  while I <= Length(T) do
  begin
    if (T[I] = #13) or (T[I] = #10) then
    begin
      Result[K] := Copy(T, Ini, I - Ini);
      if (T[I] = #13) and (I < Length(T)) and (T[I + 1] = #10) then
      begin
        ASaltos[K] := #13#10;
        Inc(I);
      end
      else
        ASaltos[K] := T[I];
      Inc(K);
      Ini := I + 1;
    end;
    Inc(I);
  end;
  Result[K] := Copy(T, Ini, MaxInt);
  ASaltos[K] := '';
end;

function UneConSusSaltos(const ALineas, ASaltos: TArray<string>): string;
var
  Sb: TStringBuilder;
  I: Integer;
  Salto: string;
begin
  Sb := TStringBuilder.Create;
  try
    for I := 0 to High(ALineas) do
    begin
      Sb.Append(ALineas[I]);
      if I <= High(ASaltos) then
      begin
        Salto := ASaltos[I];
        // Un CR suelto delante de una linea VACIA que acaba en LF se leeria
        // como UN CRLF, y esa linea desapareceria: sale como CRLF. Un texto
        // troceado no tiene esa vecindad; la crea quien cambia lineas, y la
        // inversa tiene que volver a trocearse igual (revisor propio de la
        // 1.18.2, medido: "a\rX\n\nb" sin X perdia la linea en blanco)
        if (Salto = #13) and (I < High(ALineas)) and (ALineas[I + 1] = '') and
           (I + 1 <= High(ASaltos)) and (ASaltos[I + 1] = #10) then
          Salto := #13#10;
        Sb.Append(Salto);
      end;
    end;
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

function CambiaLineasEnSuTexto(const ATexto: string; ALinea, ACuantas: Integer;
  const ANuevas: TArray<string>; const ASalto: string): string;
var
  L, S, NL, NS: TArray<string>;
  I, Ultima: Integer;
  Cierre: string;
begin
  // con la fantasma del salto final: la ultima, '' y sin salto
  L := SplitToLinesConSalto(ATexto, S);
  // un tramo fuera del texto es un fallo de quien llama, no algo que leer
  // fuera del array en silencio (el servidor no compila con range checking);
  // insertar detras de la fantasma tampoco es un sitio
  if (ALinea < 0) or (ACuantas < 0) or (ALinea + ACuantas > Length(L)) or
     ((ACuantas = 0) and (ALinea = Length(L)) and (L[High(L)] = '')) then
    raise EArgumentOutOfRangeException.CreateFmt('CambiaLineasEnSuTexto(%d, %d)',
      [ALinea, ACuantas]);
  // Lo que el tramo deja IGUAL al principio y al final no se toca: un bloque
  // con old == new no reescribe nada, e insertar detras de un ancla no le
  // cambia su salto (revisor propio de la 1.18.2). La ultima linea del texto
  // (salto '') no entra: es la que decide el salto final
  var Nuevas := ANuevas;
  while (ACuantas > 0) and (Length(Nuevas) > 0) and (S[ALinea] <> '') and
        (Nuevas[0] = L[ALinea]) do
  begin
    Inc(ALinea);
    Dec(ACuantas);
    Delete(Nuevas, 0, 1);
  end;
  while (ACuantas > 0) and (Length(Nuevas) > 0) and (S[ALinea + ACuantas - 1] <> '') and
        (Nuevas[High(Nuevas)] = L[ALinea + ACuantas - 1]) do
  begin
    Dec(ACuantas);
    SetLength(Nuevas, Length(Nuevas) - 1);
  end;
  if (ACuantas = 0) and (Length(Nuevas) = 0) then
    Exit(ATexto); // nada cambia
  Ultima := ALinea + ACuantas - 1;
  NL := Copy(L, 0, ALinea);
  NS := Copy(S, 0, ALinea);
  if Length(Nuevas) > 0 then
  begin
    // el salto con que acaba el tramo: el de la ultima que se va; si no se va
    // ninguna, las nuevas entran delante de ALinea con el dominante
    if ACuantas > 0 then
      Cierre := S[Ultima]
    else
      Cierre := ASalto;
    // detras de la ultima linea de un texto sin salto final: esa lo gana y
    // las nuevas acaban sin el (sigue sin salto final)
    if (ACuantas = 0) and (ALinea > 0) and (NS[ALinea - 1] = '') then
    begin
      NS[ALinea - 1] := ASalto;
      Cierre := '';
    end;
    for I := 0 to High(Nuevas) do
    begin
      NL := NL + [Nuevas[I]];
      if I < High(Nuevas) then
        NS := NS + [ASalto]
      else
        NS := NS + [Cierre];
    end;
  end
  else if (ACuantas > 0) and (S[Ultima] = '') and (ALinea > 0) then
    // se van las ultimas de un texto sin salto final: la de delante pierde el
    // suyo y el texto sigue sin salto final
    NS[ALinea - 1] := '';
  NL := NL + Copy(L, Ultima + 1, MaxInt);
  NS := NS + Copy(S, Ultima + 1, MaxInt);
  Result := UneConSusSaltos(NL, NS);
end;

function EmpalmaEnSuTexto(const ATexto: string; ADesde, ALargo: Integer;
  const ANuevo, ASalto: string): string;
var
  L, S, Nuevas: TArray<string>;
  I, Off, Ini, Fin, ColIni, ColFin: Integer;
  Trozo: string;
begin
  // las lineas de la vista en LF (los cortes de SplitToLines); este troceador
  // da UNA linea para un texto vacio, y SplitToLines ninguna: un vault_append
  // a una nota vacia daba SYS-009 (revisor propio de la 1.18.2)
  L := SplitToLinesConSalto(ATexto, S);
  // la linea y la columna de cada punta del tramo: la posicion de un salto es
  // el final de su linea (el salto se queda si el tramo no lo cruza)
  Off := 0;
  Ini := -1;
  Fin := -1;
  ColIni := 0;
  ColFin := 0;
  for I := 0 to High(L) do
  begin
    if (Ini < 0) and (ADesde <= Off + Length(L[I])) then
    begin
      Ini := I;
      ColIni := ADesde - Off;
    end;
    if (Fin < 0) and (ADesde + ALargo <= Off + Length(L[I])) then
    begin
      Fin := I;
      ColFin := ADesde + ALargo - Off;
    end;
    Inc(Off, Length(L[I]) + 1);
  end;
  if (Ini < 0) or (Fin < Ini) then
    raise EArgumentOutOfRangeException.CreateFmt('EmpalmaEnSuTexto(%d, %d)', [ADesde, ALargo]);
  Trozo := Copy(L[Ini], 1, ColIni) + ANuevo + Copy(L[Fin], ColFin + 1, MaxInt);
  // un trozo vacio es UNA linea en blanco, no ninguna (eso seria borrarla)
  if Trozo = '' then
    Nuevas := ['']
  else
    Nuevas := SplitToLines(Trozo);
  Result := CambiaLineasEnSuTexto(ATexto, Ini, Fin - Ini + 1, Nuevas, ASalto);
end;

function LineasQueSeQuedan(const AAntes, ADespues: TArray<string>): TArray<Integer>;
const
  MAX_CAMBIOS = 1000; // mas que esto en medio es reescribir: el medio, nuevo
var
  N, M, Pre, Suf, NA, NB, MaxD, Off, D, DFin, K, X, Y, KAntes, XAntes, YAntes: Integer;
  V, Vd: TArray<Integer>;
  Trazas: TArray<TArray<Integer>>;
begin
  N := Length(AAntes);
  M := Length(ADespues);
  SetLength(Result, M);
  for var I := 0 to M - 1 do
    Result[I] := -1;
  // lo igual delante y detras, sin buscar
  Pre := 0;
  while (Pre < N) and (Pre < M) and (AAntes[Pre] = ADespues[Pre]) do
  begin
    Result[Pre] := Pre;
    Inc(Pre);
  end;
  Suf := 0;
  while (Suf < N - Pre) and (Suf < M - Pre) and (AAntes[N - 1 - Suf] = ADespues[M - 1 - Suf]) do
  begin
    Result[M - 1 - Suf] := N - 1 - Suf;
    Inc(Suf);
  end;
  // el medio: AAntes[Pre .. Pre+NA-1] contra ADespues[Pre .. Pre+NB-1]
  NA := N - Pre - Suf;
  NB := M - Pre - Suf;
  if (NA = 0) or (NB = 0) then
    Exit; // solo entraron lineas, o solo se fueron
  // Myers (1986): V[K + Off] es la X mas lejana de la diagonal K con D cambios.
  // La de antes de cada paso se guarda, de -(D+1) a D+1, para volver por el camino
  MaxD := NA + NB;
  if MaxD > MAX_CAMBIOS then
    MaxD := MAX_CAMBIOS;
  Off := MaxD + 1;
  SetLength(V, 2 * MaxD + 3);
  Trazas := nil;
  DFin := -1;
  D := 0;
  while (DFin < 0) and (D <= MaxD) do
  begin
    Trazas := Trazas + [Copy(V, Off - D - 1, 2 * D + 3)];
    K := -D;
    while (DFin < 0) and (K <= D) do
    begin
      if (K = -D) or ((K <> D) and (V[K - 1 + Off] < V[K + 1 + Off])) then
        X := V[K + 1 + Off] // desde la diagonal de arriba: una linea que entra
      else
        X := V[K - 1 + Off] + 1; // desde la de abajo: una que se va
      Y := X - K;
      while (X < NA) and (Y < NB) and (AAntes[Pre + X] = ADespues[Pre + Y]) do
      begin
        Inc(X);
        Inc(Y);
      end;
      V[K + Off] := X;
      if (X >= NA) and (Y >= NB) then
        DFin := D;
      Inc(K, 2);
    end;
    Inc(D);
  end;
  if DFin < 0 then
    Exit; // demasiados cambios: el medio entero, nuevo
  // de vuelta, de (NA, NB) al principio: las diagonales son las que se quedan
  X := NA;
  Y := NB;
  for D := DFin downto 0 do
  begin
    Vd := Trazas[D]; // V[J] de antes del paso D en Vd[J + D + 1]
    K := X - Y;
    if (K = -D) or ((K <> D) and (Vd[K + D] < Vd[K + D + 2])) then
      KAntes := K + 1
    else
      KAntes := K - 1;
    XAntes := Vd[KAntes + D + 1];
    YAntes := XAntes - KAntes;
    while (X > XAntes) and (Y > YAntes) do
    begin
      Dec(X);
      Dec(Y);
      Result[Pre + Y] := Pre + X;
    end;
    X := XAntes;
    Y := YAntes;
  end;
end;

function ReescribeConSusSaltos(const AAntes, ANuevo: string): string;
var
  LA, LN, CA, CN: TArray<string>;
  Siguen: TArray<Integer>;
  Salto: string;
  I, J, IDebajo, JDebajo: Integer;
begin
  // un texto vacio no tiene lineas que conservar (y SplitToLines no le da
  // ninguna, donde el compositor ve una)
  if AAntes = '' then
    Exit(ANuevo);
  // las lineas de CambiaLineasEnSuTexto, con la fantasma del salto final
  LA := SplitToLines(AAntes);
  LN := SplitToLines(ANuevo);
  // la ultima de cada uno solo casa con la ultima del otro: es la que decide el
  // salto final, y un tramo detras de la fantasma no es un sitio
  CA := Copy(LA);
  CN := Copy(LN);
  if Length(CA) > 0 then
    CA[High(CA)] := #0 + CA[High(CA)];
  if Length(CN) > 0 then
    CN[High(CN)] := #0 + CN[High(CN)];
  Siguen := LineasQueSeQuedan(CA, CN);
  Salto := SaltoDominante(AAntes);
  Result := AAntes;
  // cada tramo entre dos que se quedan, de abajo arriba (lo de encima no se
  // mueve), por EL compositor de quien cambia lineas
  IDebajo := Length(LN);
  JDebajo := Length(LA);
  for I := High(LN) downto -1 do
  begin
    if I >= 0 then
    begin
      J := Siguen[I];
      if J < 0 then
        Continue;
    end
    else
      J := -1;
    if (IDebajo - I > 1) or (JDebajo - J > 1) then
      Result := CambiaLineasEnSuTexto(Result, J + 1, JDebajo - J - 1,
        Copy(LN, I + 1, IDebajo - I - 1), Salto);
    IDebajo := I;
    JDebajo := J;
  end;
end;

function TieneSalto(const AText: string): Boolean;
begin
  Result := (Pos(#10, AText) > 0) or (Pos(#13, AText) > 0);
end;

function ConSalto(const AText, ASalto: string): string;
begin
  Result := AText.Replace(#13#10, #10).Replace(#13, #10);
  if ASalto <> #10 then
    Result := Result.Replace(#10, ASalto);
end;

function EsDelMotorPascal(const APath: string): Boolean;
begin
  Result := EsRutaDeFuente(APath) or EsRutaDeDesigner(APath);
end;

procedure ZonaDelCambio(const AAntes, ADespues: TArray<string>; out ADesde, ADelta: Integer);
var
  Pre, Suf: Integer;
begin
  ADelta := Length(ADespues) - Length(AAntes);
  Pre := 0;
  while (Pre < Length(AAntes)) and (Pre < Length(ADespues)) and (AAntes[Pre] = ADespues[Pre]) do
    Inc(Pre);
  Suf := 0;
  while (Suf < Length(AAntes) - Pre) and (Suf < Length(ADespues) - Pre) and
        (AAntes[High(AAntes) - Suf] = ADespues[High(ADespues) - Suf]) do
    Inc(Suf);
  ADesde := Length(AAntes) - Suf + 1;
end;

function LineaTrasCambio(ALinea, ADesde, ADelta: Integer): Integer;
begin
  Result := ALinea;
  if (ALinea > 0) and (ALinea >= ADesde) then
    Result := ALinea + ADelta;
end;

function LineasDelTexto(const AText: string): TArray<string>;
begin
  Result := SplitToLines(AText);
  SetLength(Result, CuantasLineasReales(Result));
end;

function SaltoDominante(const AText: string): string;
var
  I, Crlf, Lf, Cr: Integer;
begin
  Crlf := 0;
  Lf := 0;
  Cr := 0;
  I := 1;
  while I <= Length(AText) do
  begin
    if AText[I] = #13 then
    begin
      if (I < Length(AText)) and (AText[I + 1] = #10) then
      begin
        Inc(Crlf);
        Inc(I);
      end
      else
        Inc(Cr);
    end
    else if AText[I] = #10 then
      Inc(Lf);
    Inc(I);
  end;
  if (Lf > Crlf) and (Lf >= Cr) then
    Result := #10
  else if (Cr > Crlf) and (Cr > Lf) then
    Result := #13
  else
    Result := #13#10; // el de Windows, tambien sin ningun salto aun
end;

function TieneSaltoFinal(const AText: string): Boolean;
begin
  Result := AText.EndsWith(#10) or AText.EndsWith(#13);
end;

function NombreDelSalto(const ASalto: string): string;
begin
  if ASalto = #13#10 then
    Result := 'CRLF'
  else if ASalto = #13 then
    Result := 'CR'
  else
    Result := 'LF';
end;

function LineaEsLaDelAncla(const ALinea, AAncla: string): Boolean;
begin
  // la sangria no cuenta a NINGUNO de los dos lados desde el 9-oct-2026 (era
  // "la linea TERMINA en el ancla": la sangria del ancla contaba como minima
  // y una tanda escribio en silencio la linea equivocada); el final tampoco
  // desde A15: contaba en el ancla de una linea de Pascal y no en sus bloques
  // ni en delphi_textedit
  Result := ALinea.Trim = AAncla.Trim;
end;

function LineasDondeCasaElAncla(const ALines: TArray<string>;
  const AAncla: string): TArray<Integer>;
var
  I: Integer;
begin
  Result := [];
  for I := 0 to High(ALines) do
    if LineaEsLaDelAncla(ALines[I], AAncla) then
      Result := Result + [I];
end;

{ Unas lineas (0-based) como las lee el agente: 1-based, "4, 6". Lo dicen las
  negativas de un ancla repetida. }
function ListaDeLineas(const AIdx: TArray<Integer>): string;
var
  I: Integer;
begin
  Result := '';
  for I in AIdx do
    Result := Result + IfThen(Result <> '', ', ') + IntToStr(I + 1);
end;

function LineaElegida(const AHits: TArray<Integer>; AAtLine: Integer;
  out AIdx: Integer): string;
var
  I: Integer;
begin
  Result := '';
  AIdx := -1;
  if (AAtLine <= 0) and (Length(AHits) = 1) then
  begin
    AIdx := AHits[0];
    Exit;
  end;
  // un atline que no es el de la unica ocurrencia se niega tambien: se
  // ignoraba y se editaba la otra linea (quinta revision)
  for I in AHits do
    if I + 1 = AAtLine then
      AIdx := I;
  if AIdx >= 0 then
    Exit;
  if AAtLine <= 0 then
    Result := MsgFmt(SR_EDIT_ANCLA_NO_UNICA_FMT, [Length(AHits), ListaDeLineas(AHits)])
  else
    Result := MsgFmt(SR_EDIT_LINEA_ESTA_ESE_ANCLA_FMT, [AAtLine, ListaDeLineas(AHits)]);
end;

function LineaEnBlancoDenegada(const ALines: TArray<string>;
  AReales, AAtLine: Integer; const AFichero: string): string;
begin
  Result := '';
  if (AAtLine < 1) or (AAtLine > AReales) then
    Exit(MsgFmt(SR_EDIT_LINEA_EN_BLANCO_NO_EXISTE_FMT, [AFichero, AReales, AAtLine]));
  // la misma pregunta que despues elige la linea: la de la regla del motor
  if not LineaEsLaDelAncla(ALines[AAtLine - 1], '') then
    Exit(MsgFmt(SR_EDIT_LINEA_NO_EN_BLANCO_FMT, [AAtLine, AFichero,
      CitaDeLinea(AAtLine, Copy(ALines[AAtLine - 1].Trim, 1, 90))]));
end;

function DecodeSourceBytes(const B: TArray<Byte>; AEsDesigner: Boolean): string;
begin
  Result := DecodeBytes(B, DetectEnc(B, AEsDesigner));
end;

function LooksBinaryBytes(const B: TArray<Byte>): Boolean;
var
  I: Integer;
begin
  if DetectEnc(B) in ENC_ANCHAS then
    Exit(False);
  for I := 0 to Min(Length(B), 65536) - 1 do
    if B[I] = 0 then
      Exit(True);
  Result := False;
end;

{ Una antiguedad en palabras para un agente: "12 min", "3 h 05 min",
  "2 dias". Para la vista previa de restore. }
function EdadLegible(ADias: Double): string;
var
  Mins: Int64;
begin
  Mins := Round(ADias * 24 * 60);
  if Mins < 0 then
    Mins := 0;
  if Mins < 60 then
    Result := MsgFmt(SF_EDIT_EDAD_MIN_FMT, [Mins])
  else if Mins < 24 * 60 then
    Result := MsgFmt(SF_EDIT_EDAD_HORAS_MIN_FMT, [Mins div 60, Mins mod 60])
  else
    Result := MsgFmt(SF_EDIT_EDAD_DIAS_FMT, [Mins div (24 * 60)]);
end;

function TrashStampedName(const AName: string): string;
begin
  Result := AName + '-' + FormatDateTime('hhnnsszzz', Now);
end;

function TrashPathFor(const APath, ACajon: string): string;
var
  Veto: string;
begin
  Result := TPath.Combine(TrashDayDir(APath, ACajon),
    TrashStampedName(TPath.GetFileName(SinBarraFinal(APath))));
  // Un nombre NUEVO siempre: el sello sale de Now, que avanza a golpes de
  // ~15 ms, y dos sustituciones del mismo fichero en el mismo golpe (to-binary
  // y enseguida to-text) tenian el mismo nombre: la copia no pisa y la segunda
  // operacion fallaba (la puerta 18 lo cazo; septima revision). Se espera al
  // sello siguiente: el formato no cambia y su lector (TrashOriginalName)
  // tampoco.
  var Espera := 0;
  while (TFile.Exists(Result) or TDirectory.Exists(Result)) and (Espera < 100) do
  begin
    Sleep(5);
    Inc(Espera);
    Result := TPath.Combine(TrashDayDir(APath, ACajon),
      TrashStampedName(TPath.GetFileName(SinBarraFinal(APath))));
  end;
  // La papelera es un DESTINO: por la puerta de escribir, sobre la ruta REAL.
  Veto := EscrituraDenegada(TPath.GetDirectoryName(Result));
  if Veto = '' then
    Veto := EscrituraDenegada(Result);
  if Veto <> '' then
    raise Exception.Create(Veto);
end;

procedure WriteOwnerMarker(const ATrash: string);
var
  Who: string;
begin
  Who := CurrentAgent;
  if Who = '' then
    Exit;
  try
    // por LA puerta de escribir, en UTF-8 (un agente ASCII da los mismos
    // bytes de siempre): en ASCII un nombre no ASCII salia con '?' y no
    // casaba con su dueno al purgar (P3-L1 de la 1.18.0); TrashOwner lo lee
    // con el detector
    EscribeTexto(MarcaDeDueno(ATrash), Who, ltJaula, ekUtf8);
  except
    // a missing marker just means "nobody's": never fatal
  end;
end;

function TrashOwner(const APath: string): string;
begin
  Result := '';
  try
    if TFile.Exists(MarcaDeDueno(APath)) then
      Result := LeeTexto(MarcaDeDueno(APath), [ltJaula]).Trim([' ', #9, #13, #10, #$FEFF]);
  except
    Result := '';
  end;
end;

function GuardaContenidoActual(const APath, ACajon: string): string;
begin
  Result := '';
  if not TFile.Exists(APath) then
    Exit;
  // Quien guarda la copia va a PISAR o BORRAR el fichero entero: si tiene
  // el atributo de solo lectura, se dice aqui, antes de copiar nada. Es el
  // sitio de todos (upload, cuarentena, disenador, adb, escritorio,
  // package, changeset delete, restore): package decia "alguien lo tiene
  // abierto, reintenta" y dejaba copia (septima revision, medido)
  var Motivo := SoloLecturaDenegado(APath);
  if Motivo <> '' then
    raise Exception.Create(Motivo);
  // de un temporal no se restaura nada (la regla del borrado): su copia
  // dejaba una papelera DENTRO de la temporal (septima revision)
  if EnTemporal(APath) then
    Exit;
  // ...y la copia es LEER el fichero: un enlace duro con un nombre que la
  // sesion no lee no se copia, y sin copia no se pisa (medido el
  // 20-oct-2026: upload y el .res de styles build metian en la papelera los
  // bytes del fichero de fuera de las raices)
  Motivo := EnlaceDuroIlegible(APath);
  if Motivo <> '' then
    raise Exception.Create(Motivo);
  Result := TrashPathFor(APath, ACajon); // la puerta, o la negativa
  CrearCarpeta(TPath.GetDirectoryName(Result));
  TFile.Copy(APath, Result);
  WriteOwnerMarker(Result);
end;

function TrashOriginalName(const AName: string): string;
var
  M: TMatch;
begin
  Result := AName;
  // hhnnsszzz = 9 digitos. En bucle, porque restaurar una copia restaurada
  // encadena sellos.
  while True do
  begin
    M := TRegEx.Match(Result, '^(.+)-\d{9}$');
    if not M.Success then
      Break;
    Result := M.Groups[1].Value;
  end;
  if Result = AName then
    Result := '';
end;

function ReescrituraDenegada(const APath: string; const B: TArray<Byte>;
  out K: TEncKind): string;
begin
  K := DetectEnc(B, EsRutaDeDesigner(APath));
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

var
  R: string;
begin
  Result := False;
  // solo lo absoluto: una relativa se resolveria contra la carpeta de
  // trabajo del proceso (System32 en el servicio)
  if not EsRutaAbsoluta(APath.Trim) then
    Exit;
  case ALugar of
    // del IDE: primero lo que se mide sin leer; los sysroots de sus .sdk (que
    // piden leerlos) solo si no cae ahi
    ltIde:
      begin
        R := Real;
        // los que nombra un .sdk, solo para LEER: un .sdk no decide donde
        // escribe el servidor (medida M3: la libX.so iba a lo que listase)
        Result := (R <> '') and (EnAlgunLugar(R, LugaresDelIde(AParaEscribir)) or
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

function LeeTexto(const APath: string; ALugares: TLugaresDeTexto): string;
var
  Enc: string;
begin
  Result := LeeTexto(APath, ALugares, Enc);
end;

const
  // cuantas copias de UN fichero del IDE se guardan: politica de la casa, no
  // hay juez. Repetir get-sdk tras actualizar el destino (lo que manda su
  // descripcion) copia el .sdk cada vez, y ide-copias crecia sin limite
  // (revisor de P3)
  COPIAS_DEL_IDE_POR_FICHERO = 10;

{ La copia en la casa de algo del IDE que se va a pisar o borrar: ANombre la
  nombra (CopiaDelIde: la ruta de un fichero, o FicheroDeClaveDelIde para una
  clave del registro) y AGuarda la escribe en la ruta que se le da - copiar el
  fichero, exportar la clave -. Luego, las mas viejas de ese nombre fuera.
  Lanza si no se pudo: sin copia no se toca. Era el cuerpo de
  CopiaAntesDePisar, solo para ficheros (V10: el registro, sin copia). }
function GuardaCopiaDelIde(const ANombre: string; const AGuarda: TProc<string>): string;
var
  Motivo: string;
  Copias: TArray<string>;
begin
  Result := CopiaDelIde(ANombre);
  Motivo := LugarDeEscrituraDenegado(Result, ltCasa);
  if Motivo <> '' then
    raise Exception.Create(Motivo);
  CrearCarpeta(TPath.GetDirectoryName(Result));
  AGuarda(Result);
  // las mas viejas de ESE fichero fuera, por la puerta de borrar de la casa.
  // La purga nunca para lo que se iba a hacer (la copia ya esta), y la que
  // se acaba de hacer no se borra aunque el reloj haya vuelto atras (el
  // sello es la hora local: el cambio de hora repite una)
  try
    Copias := CopiasDelIde(ANombre);
  except
    Copias := nil;
  end;
  for var I := 0 to Length(Copias) - COPIAS_DEL_IDE_POR_FICHERO - 1 do
    if not SameText(Copias[I], Result) then
      try
        BorraFichero(Copias[I], ltCasa);
      except
      end;
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

function ValorDeTexto(const ANombre, ATexto: string): TValorDelIde;
begin
  Result := Default(TValorDelIde);
  Result.Nombre := ANombre;
  Result.Texto := ATexto;
end;

function ValorEntero(const ANombre: string; AEntero: Integer): TValorDelIde;
begin
  Result := Default(TValorDelIde);
  Result.Nombre := ANombre;
  Result.Entero := AEntero;
  Result.EsEntero := True;
end;

{ La clave AClave (bajo HKCU) exportada a ACopia por reg.exe, el exportador
  de Windows: un .reg que se devuelve abriendolo. Lanza si no quedo. }
procedure ExportaClaveDelIde(const AClave, ACopia: string);
var
  Sistema: array[0..MAX_PATH] of Char;
  Dir, Salida: string;
  Codigo: Cardinal;
begin
  // reg.exe POR SU RUTA, la de System32, donde el agente no escribe: un
  // programa nunca se busca por su nombre a secas (CLAUDE.md, 13-oct-2026);
  // cada argumento por EL compositor (EnComillas), sin shell
  SetString(Dir, Sistema, GetSystemDirectory(Sistema, Length(Sistema)));
  // sin la carpeta del sistema, 'reg.exe' a secas se buscaria en la actual
  if Dir = '' then
    raise Exception.Create(MsgFmt(SR_IDE_CLAVE_SIN_COPIA_FMT, [AClave, SysErrorMessage(GetLastError)]));
  Salida := RunCaptured(EnComillas(TPath.Combine(Dir, 'reg.exe')) + ' export ' +
    EnComillas('HKCU\' + AClave) + ' ' + EnComillas(ACopia) + ' /y', 30000, Codigo);
  if (Codigo <> 0) or not TFile.Exists(ACopia) then
    raise Exception.Create(MsgFmt(SR_IDE_CLAVE_SIN_COPIA_FMT, [AClave, Salida.Trim]));
end;

{ La clave abierta en R ya dice AValores: cada uno esta, con su tipo y su dato. }
function ClaveYaDice(R: TRegistry; const AValores: array of TValorDelIde): Boolean;
begin
  for var V in AValores do
    try
      if not R.ValueExists(V.Nombre) then
        Exit(False);
      if V.EsEntero then
      begin
        if (R.GetDataType(V.Nombre) <> rdInteger) or (R.ReadInteger(V.Nombre) <> V.Entero) then
          Exit(False);
      end
      else if not (R.GetDataType(V.Nombre) in [rdString, rdExpandString]) or
        (R.ReadString(V.Nombre) <> V.Texto) then
        Exit(False);
    except
      Exit(False); // lo que no se lee no es igual
    end;
  Result := True;
end;

function EscribeClaveDelIde(const AVersion, ASubclave: string;
  const AValores: array of TValorDelIde): string;
var
  R: TRegistry;
  Clave: string;
begin
  Result := '';
  Clave := ClaveDelIde(AVersion, ASubclave);
  R := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    R.RootKey := HKEY_CURRENT_USER;
    if R.OpenKey('\' + Clave, False) then
    begin
      if ClaveYaDice(R, AValores) then
        Exit;
      R.CloseKey;
      Result := GuardaCopiaDelIde(FicheroDeClaveDelIde(AVersion, ASubclave),
        procedure(ACopia: string)
        begin
          ExportaClaveDelIde(Clave, ACopia);
        end);
    end;
    if not R.OpenKey('\' + Clave, True) then
      raise Exception.Create(MsgFmt(SR_IDE_CLAVE_NO_ESCRITA_FMT, [Clave]));
    for var V in AValores do
      if V.EsEntero then
        R.WriteInteger(V.Nombre, V.Entero)
      else
        R.WriteString(V.Nombre, V.Texto);
    R.CloseKey;
  finally
    R.Free;
  end;
end;

function BorraClaveDelIde(const AVersion, ASubclave: string): string;
var
  R: TRegistry;
  Clave: string;
begin
  Result := '';
  Clave := ClaveDelIde(AVersion, ASubclave);
  R := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    R.RootKey := HKEY_CURRENT_USER;
    if not R.KeyExists('\' + Clave) then
      Exit;
    Result := GuardaCopiaDelIde(FicheroDeClaveDelIde(AVersion, ASubclave),
      procedure(ACopia: string)
      begin
        ExportaClaveDelIde(Clave, ACopia);
      end);
    if not R.DeleteKey('\' + Clave) then
      raise Exception.Create(MsgFmt(SR_IDE_CLAVE_NO_ESCRITA_FMT, [Clave]));
  finally
    R.Free;
  end;
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
  Motivo, Tmp: string;
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
  Tmp := TemporalDeSustitucion(APath);
  try
    TFile.WriteAllBytes(Tmp, ABytes);
  except
    // a medias no se queda: un temporal suelto no lo ve nadie para borrarlo
    System.SysUtils.DeleteFile(Tmp);
    raise;
  end;
  SustituyePorRenombre(Tmp, APath); // si no puede, borra el temporal y lanza
end;

function EscribeTexto(const APath, ATexto: string; ALugar: TLugarDeTexto;
  AK: TEncKind; AEstricto: Boolean): string;
begin
  Result := EscribeBytes(APath, EncodeText(ATexto, AK, AEstricto), ALugar);
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

procedure PatchSaveText(const APath, AText, AEncName: string; AEnsayo: Boolean = False;
  ANuevo: Boolean = False);
var
  K: TEncKind;
  B, Antes: TBytes;
  Existe: Boolean;
  TextoAntes: string;
begin
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
    BackupFile(APath); // new files have nothing to back up
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

function NthOccurrenceLine(const APath, AAnchor: string; AN: Integer): Integer;
var
  Lines: TArray<string>;
  Enc: string;
  I, Seen: Integer;
begin
  Result := 0;
  if (AN <= 0) or (AAnchor.Trim = '') then
    Exit;
  try
    Lines := LineasDelTexto(PatchLoadText(APath, Enc)); // los saltos como el motor (CR tambien)
  except
    Exit;
  end;
  // con la regla del motor que va a aplicar la edicion (LineaEsLaDelAncla):
  // contaba con otra y "  foo;  " era una ocurrencia que el motor no veia
  // (EDIT-062; novena revision)
  Seen := 0;
  for I in LineasDondeCasaElAncla(Lines, AAnchor) do
  begin
    Inc(Seen);
    if Seen = AN then
      Exit(I + 1);
  end;
end;

{ La pista de por que AOld no es una linea del fichero. ADentro = esta
  contenido en alguna linea (entonces no es que no aparezca: es un trozo). }
function PistaAncla(const ALines: TArray<string>; const AOld: string;
  out ADentro: Boolean): string;
var
  I, N, Mejor, MejorLen, Tope, K: Integer;
  Objetivo, Lt: string;
begin
  Result := '';
  ADentro := False;
  Objetivo := AOld.Trim;
  if Objetivo = '' then
    Exit;
  // 1. un U+FFFD que ninguna linea tiene: el ancla salio de una lectura que
  // rompio los acentos, y eso es lo que hay que arreglar (A15: se negaba
  // antes de buscar y solo en delphi_edit, asi que una linea que lo lleva de
  // verdad no se podia editar). La misma linea con otros blancos alrededor ya
  // no es una pista: los dos extremos no cuentan (LineaEsLaDelAncla)
  if Pos(#$FFFD, Objetivo) > 0 then
  begin
    var EnElFichero := False;
    for I := 0 to High(ALines) do
      if Pos(#$FFFD, ALines[I]) > 0 then
        EnElFichero := True;
    if not EnElFichero then
      Exit(#10 + MsgText(SN_ANCLA_LLEVA_FFFD));
  end;
  // 2. un TROZO de una o mas lineas
  N := 0;
  for I := 0 to High(ALines) do
    if ALines[I].Contains(Objetivo) then
    begin
      Inc(N);
      if N <= 5 then
        Result := Result + #10'  ' + CitaDeLinea(I + 1, ALines[I]);
    end;
  if N > 0 then
  begin
    ADentro := True;
    if N > 5 then
      Result := Result + #10 + MsgFmt(SF_EDIT_PISTA_Y_MAS_FMT, [N - 5]);
    Exit(#10 + MsgText(SN_ANCLA_CONTIENEN) + Result);
  end;
  // 3. la linea real que mas se le parece por el principio
  Mejor := -1;
  MejorLen := 0;
  for I := 0 to High(ALines) do
  begin
    Lt := ALines[I].Trim;
    if Lt = '' then
      Continue;
    Tope := Length(Lt);
    if Length(Objetivo) < Tope then
      Tope := Length(Objetivo);
    K := 0;
    while (K < Tope) and (Lt[K + 1] = Objetivo[K + 1]) do
      Inc(K);
    if K > MejorLen then
    begin
      MejorLen := K;
      Mejor := I;
    end;
  end;
  if (Mejor >= 0) and (MejorLen >= 12) then
    Result := #10 + MsgFmt(SN_ANCLA_PARECIDA_FMT, [Mejor + 1]) +
      #10'  ' + CitaDeLinea(Mejor + 1, ALines[Mejor]);
end;

function AnclaPerdida(const ALines: TArray<string>;
  const AOld, AFichero: string): string;
var
  Dentro: Boolean;
  Pista: string;
begin
  Pista := PistaAncla(ALines, AOld, Dentro);
  if Dentro then
    Result := MsgFmt(SR_ANCLA_DENTRO_FMT, [AFichero]) + Pista
  else
    Result := MsgFmt(SR_ANCLA_NO_ESTA_FMT, [AFichero, AOld]) + Pista + #10 +
      MsgText(SN_ANCLA_COPIALA);
end;

{ EL escaneo del bloque, escrito una vez. Devuelve el indice 0-based donde
  empieza la ocurrencia pedida (-1 si no esta) y cuantas hay en total. Lo usan
  ApplyBlockEdit y NthBlockLine: escribirlo dos veces era precisamente como
  nacio el bug de "occurrence" que este release arregla. }
function BuscaBloque(const ALines, AOldLines: TArray<string>;
  AOccurrence: Integer; out ACuantas: Integer): Integer;
var
  I, J, Vistas: Integer;
  Ok: Boolean;
begin
  Result := -1;
  ACuantas := 0;
  Vistas := 0;
  for I := 0 to Length(ALines) - Length(AOldLines) do
  begin
    Ok := True;
    for J := 0 to High(AOldLines) do
      if not LineaEsLaDelAncla(ALines[I + J], AOldLines[J]) then
      begin
        Ok := False;
        Break;
      end;
    if Ok then
    begin
      Inc(ACuantas);
      Inc(Vistas);
      if (AOccurrence > 0) and (Vistas = AOccurrence) then
      begin
        Result := I;
        ACuantas := 1;
        Exit;
      end;
      if AOccurrence = 0 then
        Result := I;
    end;
  end;
end;

{ Normaliza un ancla de bloque: sin CRLF y sin la linea vacia final que pone
  el editor de quien llama. }
function LineasDelAncla(const AOld: string): TArray<string>;
begin
  Result := SplitToLines(AOld); // el troceador del motor: un CR suelto es salto
  while (Length(Result) > 1) and (Result[High(Result)].Trim = '') do
    SetLength(Result, Length(Result) - 1);
end;

function NthBlockLine(const APath, AOld: string; AN: Integer): Integer;
var
  Enc: string;
  Cuantas: Integer;
begin
  Result := 0;
  if AN <= 0 then
    Exit;
  try
    var Idx := BuscaBloque(
      SplitToLines(PatchLoadText(APath, Enc)),
      LineasDelAncla(AOld), AN, Cuantas);
    if Idx >= 0 then
      Result := Idx + 1; // 1-based, como atline
  except
    Result := 0;
  end;
end;

function LineasDeNew(const ANew: string): TArray<string>;
var
  S: string;
begin
  S := ConSalto(ANew, #10);
  if S.EndsWith(#10) then
    S := S.Substring(0, S.Length - 1);
  Result := S.Split([#10]);
  if Length(Result) = 0 then
    Result := [''];  // '' es una linea vacia, no ninguna
end;

// El aviso (no bloquea) para un comentario de llave con otra llave dentro que
// TOCA lo escrito en un fuente Pascal. ATexto: el fichero RESULTANTE entero;
// ADesde: el indice (0-based) de la primera linea escrita y ACuantas cuantas
// (0 = la edicion solo quito: se mira la juntura, la de antes y la de
// despues). Miraba solo el texto nuevo, y una linea escrita en MEDIO de un
// comentario de llaves de varias lineas -con un {$I} citado, o una llave- no
// avisaba: la llave que lo abre estaba en otra linea (medido el 9-oct-2026,
// en la suelta y en la tanda; dcc dio E2029). UN sitio para los dos motores
// de delphi_edit (el de una linea y el de bloque) y para los que crean.
function AvisosDeLlaves(const APath, ATexto: string; ADesde, ACuantas: Integer): TArray<string>;
var
  Fines: TArray<Integer>;
begin
  Result := [];
  if not EsRutaDeFuente(APath) then // (.lpr no llegaba: ExecutePatch lo niega)
    Exit;
  var Desde := ADesde;         // 0-based
  var Hasta := ADesde + ACuantas - 1;
  var Inicios := LlavesAnidadas(ATexto, Fines); // 1-based
  for var K := 0 to High(Inicios) do
    if ACuantas <= 0 then
    begin
      // solo se quito: el que ABARCA la juntura (empieza en la de arriba o
      // antes y acaba en la de abajo o despues), que es el que el borrado
      // pudo formar; uno viejo pegado a ella no (revisor de la noche, B-1)
      if (Inicios[K] - 1 <= ADesde - 1) and (Fines[K] - 1 >= ADesde) then
        Result := Result + [MsgFmt(SN_AVISO_LLAVE_ANIDADA_FMT, [Inicios[K]])];
    end
    else if (Inicios[K] - 1 <= Hasta) and (Fines[K] - 1 >= Desde) then
      Result := Result + [MsgFmt(SN_AVISO_LLAVE_ANIDADA_FMT, [Inicios[K]])];
end;

function ConAvisosDeLlaves(const AMsg, APath, ANuevo: string): string;
begin
  Result := AMsg;
  for var Aviso in AvisosDeLlaves(APath, ANuevo, 0, MaxInt) do
    Result := Result + #10 + Aviso;
end;

function DesignerLint(const APath, ATexto, AEnc: string): TArray<string>; forward;

threadvar
  // >0 dentro de una tanda o un changeset sobre un form: ver
  // AplazaJuicioDeForm (interface). Por hilo, como GOrigenes
  GJuicioDeFormAplazado: Integer;

procedure AplazaJuicioDeForm(AAplaza: Boolean);
begin
  if AAplaza then
    Inc(GJuicioDeFormAplazado)
  else if GJuicioDeFormAplazado > 0 then
    Dec(GJuicioDeFormAplazado);
end;

function JuicioDeForm(const APath, ATexto, AEnc: string): TArray<string>;
begin
  Result := [];
  if not EsRutaDeDesigner(APath) then
    Exit;
  Result := [MsgText(SN_EDIT_DESIGNER_FORMATO_TEXTO)] + DesignerLint(APath, ATexto, AEnc);
end;

function JuicioDeLoEscrito(const APath, ATexto, AEnc: string;
  const AOmite: TArray<string>): TArray<string>;
begin
  Result := JuicioDeForm(APath, ATexto, AEnc);
  if not SameText(ExtractFileExt(APath), '.pas') then
    Exit;
  for var Df in DesignersDeUnidad(APath) do
  begin
    var Omitido := False;
    for var O in AOmite do
      if SameText(O, Df) then
        Omitido := True;
    if Omitido or not TFile.Exists(Df) then
      Continue;
    try
      // por EL lector de designers: un binario se leia como texto y no se
      // juzgaba (W4 del revisor de cierre de la 1.18.2)
      var EncF, TextoDf: string;
      if TextoDeDesigner(Df, TextoDf, EncF) <> '' then
        Continue; // un binario danado: lo dice quien lo lea, no esta escritura
      var Enlace := DesignerBindingWarnings(Df, LineasDelTexto(TextoDf));
      if Length(Enlace) > 0 then
        for var L in [MsgText(SN_DESIGNER_BINDING_LINT_HEADER)] + Enlace do
          Result := Result + [MaskDriveText('', Df) + ': ' + L];
    except
      // un form que no se relee no tumba lo ya escrito
    end;
  end;
end;

function ApplyBlockEdit(const APath, AOld, ANew: string;
  AOccurrence: Integer; AAtLine: Integer): string;
var
  Enc, Text, Eol: string;
  Lines, OldLines, NewLines: TArray<string>;
  I, J, Hit, Count: Integer;
begin
  Text := PatchLoadText(APath, Enc);
  Eol := SaltoDominante(Text); // el de todos (era otra copia de "CRLF si hay alguno")
  Lines := SplitToLines(Text); // un CR suelto es salto (daba EDIT-098 en un
                               // fichero de solo CR; octava revision)
  OldLines := LineasDelAncla(AOld);
  if Length(OldLines) < 2 then
    Exit(MsgText(SR_PATCH_BLOCK_SHORT));
  if AAtLine > 0 then
  begin
    // Linea YA resuelta por quien llama. Una tanda la resuelve contra el
    // fichero ORIGINAL y la arrastra segun las entradas anteriores anaden o
    // quitan lineas; volver a contar ocurrencias aqui, sobre el fichero ya
    // mutado, es el bug de "occurrence" por su tercera puerta - la de las
    // anclas de BLOQUE, que se quedo abierta cuando se cerraron las otras
    // dos (2026-09-20). Aqui solo se comprueba que el bloque SIGUE ahi.
    Hit := AAtLine - 1;
    Count := 1;
    if (Hit < 0) or (Hit + Length(OldLines) > Length(Lines)) then
      Hit := -1
    else
      for J := 0 to High(OldLines) do
        if not LineaEsLaDelAncla(Lines[Hit + J], OldLines[J]) then
        begin
          Hit := -1;
          Break;
        end;
  end
  else
    Hit := BuscaBloque(Lines, OldLines, AOccurrence, Count);
  if Hit < 0 then
  begin
    // Y QUE linea del bloque no esta, con la misma pista que un ancla de
    // una linea: "no encuentro el bloque" a secas mandaba a comparar
    // todas a ojo.
    var Falta := '';
    for J := 0 to High(OldLines) do
    begin
      var Esta := False;
      for I := 0 to High(Lines) do
        if LineaEsLaDelAncla(Lines[I], OldLines[J]) then
        begin
          Esta := True;
          Break;
        end;
      if not Esta then
      begin
        var Dentro: Boolean;
        Falta := #10 + MsgFmt(SN_BLOQUE_LINEA_FALTA_FMT, [J + 1, OldLines[J].Trim]) +
          PistaAncla(Lines, OldLines[J], Dentro);
        Break;
      end;
    end;
    Exit(MsgFmt(SR_PATCH_BLOCK_MISSING_FMT,
      [Length(OldLines), OldLines[0].Trim]) + Falta);
  end;
  if Count > 1 then
    Exit(MsgFmt(SR_PATCH_BLOCK_AMBIGUOUS_FMT, [Count, OldLines[0].Trim]));
  NewLines := LineasDeNew(ANew);
  // El compositor de todos (CambiaLineasEnSuTexto): las lineas nuevas sobre
  // las del bloque, cada linea de fuera con SU salto y el salto final tal
  // cual. Montado a mano, un bloque que llegaba a la ultima linea de un
  // fichero sin salto final se lo anadia (decima revision), y unido con el
  // dominante un fichero mixto salia entero a ese salto (1.18.2). Un new
  // vacio quita el bloque: no deja una linea en blanco
  var Nuevas := NewLines;
  if (Length(NewLines) = 1) and (NewLines[0] = '') then
    Nuevas := nil;
  var Joined := CambiaLineasEnSuTexto(Text, Hit, Length(OldLines), Nuevas, Eol);
  // Nada cambia (el bloque ya dice eso): no se escribe ni se copia, y se
  // dice, como la edicion de una linea. Reescribia el fichero identico y
  // la tanda contestaba APPLIED (septima revision: la tercera puerta)
  if Joined = Text then
    Exit(MsgFmt(SN_EDIT_SIN_CAMBIOS_FMT, [Hit + 1, TPath.GetFileName(APath)]));
  PatchSaveText(APath, Joined, Enc);
  Result := MsgFmt(SN_PATCH_BLOCK_OK_FMT, [Length(OldLines), Hit + 1]);
  // el fichero que queda, y lo escrito en el: las lineas nuevas desde Hit (un
  // new vacio quita el bloque: solo la juntura)
  var Escritas := Length(NewLines);
  if (Escritas = 1) and (NewLines[0] = '') then
    Escritas := 0;
  for var Aviso in AvisosDeLlaves(APath, Joined, Hit, Escritas) do
    Result := Result + #10 + Aviso;
  // (el form lo juzga quien agrupa, una vez, sobre lo que quedo escrito: su
  // unico llamador es AplicaTanda, que siempre aplaza - H6; el juicio que
  // habia aqui era codigo muerto, W11 del revisor de cierre)
end;

function FragmentoALinea(const APath, AFrag, ANew: string; AAtLine: Integer;
  const AOtros: string; out AOld, ANewLine: string): string;
var
  Enc, Linea: string;
  Lines: TArray<string>;
  Veces, P: Integer;
begin
  Result := '';
  AOld := '';
  ANewLine := '';
  if AOtros <> '' then
    Exit(MsgFmt(SR_FRAG_MIXED_FMT, [AOtros]));
  if AAtLine <= 0 then
    Exit(MsgText(SR_FRAG_NEEDS_ATLINE));
  // (un U+FFFD no se niega aqui: el que la linea lleva se cambia como otro
  // caracter, y el de una lectura rota lo dice la negativa de "no esta", E3
  // de A15)
  if AFrag = '' then
    Exit(MsgText(SR_FRAG_EMPTY));
  if TieneSalto(AFrag) or TieneSalto(ANew) then
    Exit(MsgText(SR_FRAG_MULTILINE));
  // new == fragment ya no es un error (EDIT-009): la linea sale igual y el
  // motor lo dice como la edicion suelta, UNCHANGED (EDIT-113)
  // Los rechazos de aqui ENSENAN la linea: que no sea la de un fichero que
  // este token no puede leer. La puerta ya lo mira; esto es el cinturon.
  Result := ReadPathDenied(APath);
  if Result <> '' then
    Exit;
  if not TFile.Exists(APath) then
    Exit(NoEsFichero(APath, MsgFmt(SR_PATCH_EDITS_NOFILE_FMT, [APath])));
  Lines := LineasDelTexto(PatchLoadText(APath, Enc));
  if AAtLine > Length(Lines) then
    Exit(MsgFmt(SR_FRAG_BEYOND_FMT,
      [AAtLine, TPath.GetFileName(APath), Length(Lines)]));
  Linea := Lines[AAtLine - 1];
  Veces := 0;
  P := Pos(AFrag, Linea);
  while P > 0 do
  begin
    Inc(Veces);
    P := Pos(AFrag, Linea, P + 1); // solapadas tambien cuentan: "aa" en "aaa"
  end;
  if Veces = 0 then
    Exit(MsgFmt(SR_FRAG_NOTFOUND_FMT, [AFrag, AAtLine, CitaDeLinea(AAtLine, Linea)]) +
      IfThen(Pos(#$FFFD, AFrag) > 0, #10 + MsgText(SN_ANCLA_LLEVA_FFFD)));
  if Veces > 1 then
    Exit(MsgFmt(SR_FRAG_SEVERAL_FMT, [AFrag, Veces, AAtLine, CitaDeLinea(AAtLine, Linea)]));
  P := Pos(AFrag, Linea);
  AOld := Linea;
  ANewLine := Copy(Linea, 1, P - 1) + ANew +
    Copy(Linea, P + Length(AFrag), MaxInt);
end;

function RangoHasta(const APath: string;
  ATarget0, AToLine, ATotal: Integer; out AFin: Integer): string;
begin
  Result := '';
  AFin := ATarget0;      // sin rango, el ancla es ella sola
  if AToLine <= 0 then
    Exit;
  if AToLine - 1 < ATarget0 then
    Exit(MsgFmt(SR_RANGE_BACKWARDS_FMT, [AToLine, ATarget0 + 1]));
  if AToLine > ATotal then
    Exit(MsgFmt(SR_RANGE_BEYOND_FMT,
      [AToLine, TPath.GetFileName(APath), ATotal]));
  // Un rango de la primera a la ultima es "vaciame el fichero" por otra
  // puerta, y estas tools ya rechazan reescribirlo entero. La puerta de al
  // lado es justo donde se cuelan los agujeros (medido tres veces el
  // 2026-09-20), asi que se cierra aqui, con el mismo criterio.
  if (ATarget0 = 0) and (AToLine >= ATotal) then
    Exit(MsgFmt(SR_RANGE_WHOLE_FMT, [ATotal]));
  AFin := AToLine - 1;
end;

{ Un campo entero de una entrada de "edits", por la MISMA regla que un
  parametro de la llamada (TMCPSerializer.MotivoEntero): 0 si no viene o es
  null. Se valida antes en el repaso de claves, asi que aqui ya vale. }
function EnteroDeEntrada(O: TJSONObject; const AClave: string): Integer;
var
  V: TJSONValue;
  I64: Int64;
begin
  Result := 0;
  V := O.Values[AClave];
  if (V = nil) or (V is TJSONNull) then
    Exit;
  if TMCPSerializer.MotivoEntero(V, High(Integer), I64) = '' then
    Result := Integer(I64);
end;

{ El booleano de una entrada, por la misma regla (MotivoBooleano). }
function BooleanoDeEntrada(O: TJSONObject; const AClave: string): Boolean;
var
  V: TJSONValue;
begin
  Result := False;
  V := O.Values[AClave];
  if (V = nil) or (V is TJSONNull) then
    Exit;
  if TMCPSerializer.MotivoBooleano(V, Result) <> '' then
    Result := False;
end;

const
  // la sangria de lo que va DEBAJO de una fila de la tanda: las lineas de su
  // negativa y el eco de la linea releida
  SANGRIA_FILA = '     ';

{ Una fila de la tanda que no es un OK: '  N: texto' (la entrada que cayo y
  sus avisos), con los saltos del texto sangrados (ConSalto), no pegados con
  blancos: una cita del disco ('  15|texto') es una linea suya, y el
  enmascarador la deja tal cual (4-oct-2026). Sin salto final: quien la
  escribe pone un #10 (con AppendLine, CRLF en Windows, el eco mezclaba los
  dos; test_round34). Los cuatro sitios de la tanda que la escribian llevaban
  cada uno su forma, y uno la llevaba en el catalogo. }
function FilaDeEntrada(N: Integer; const ATexto: string): string;
begin
  Result := Format('  %d: %s', [N, ConSalto(ATexto, #10 + SANGRIA_FILA)]);
end;

{ La ESTRUCTURA de un fuente despues de escribirlo: '' si sigue en pie, o el
  aviso. EDIT-085: tenia su end. y ya no tiene ninguno. EDIT-086: lo que hay
  detras del PRIMER end. - el final: el compilador no lee mas alla - ha
  cambiado y no esta vacio (un end. pegado a media unidad, codigo escrito
  detras). Los end. son los del CODIGO (un end. comentado contaba, la cuenta
  salia 2 y no se miraba nada: censo del lexico, 2-oct-2026), por EL lector
  (Lsp.Pascal.EndsConPunto: el que iba solo en su linea hacia gritar BROKEN
  STRUCTURE sobre un 'program P; begin end.' que compila, 10-oct-2026). Y
  RELATIVA: lo que ya estaba detras (notas sin comentar) no avisa mientras no
  cambie; avisaba en cada edicion de ese fichero y en una tanda que no
  escribia nada, con la orden de deshacer (revisor 8, 10-oct-2026). La
  pregunta la edicion suelta (DoEdit) sobre lo que acaba de escribir y la
  tanda (AplicaTanda) sobre el fichero ENTERO al acabar: una entrada que abre
  un (* y la siguiente que lo cierra dejaban a mitad de tanda un estado roto
  que el fichero final no tiene (2.5 de la 1.18.0). }
function AvisoDeEstructura(const AAntes, ADespues: string): string;
begin
  Result := '';
  var VistaAntes := CodigoPascal(AAntes);
  var VistaDespues := CodigoPascal(ADespues);
  var EA := EndsConPunto(VistaAntes);
  var ED := EndsConPunto(VistaDespues);
  if Length(EA) = 0 then
    Exit;
  if Length(ED) = 0 then
    Exit(MsgFmt(SN_EDIT_ESTRUCTURA_ROTA_END_FMT, [0]));
  var Detras := Copy(VistaDespues, ED[0].Fin, MaxInt).Trim;
  if (Detras <> '') and (Detras <> Copy(VistaAntes, EA[0].Fin, MaxInt).Trim) then
    Result := MsgText(SN_EDIT_ESTRUCTURA_ROTA_ULTIMA);
end;

function IniciosDelAncla(const ALines: TArray<string>; const AAncla: string): TArray<Integer>;
var
  Ancla: TArray<string>;
  K, Inicio, Cuantas: Integer;
begin
  Ancla := LineasDelAncla(AAncla); // normalizada: sin la linea vacia final
  if Length(Ancla) = 1 then
    Exit(LineasDondeCasaElAncla(ALines, Ancla[0]));
  Result := [];
  K := 1;
  repeat
    Inicio := BuscaBloque(ALines, Ancla, K, Cuantas);
    if Inicio >= 0 then
      Result := Result + [Inicio];
    Inc(K);
  until (Inicio < 0) or (K > 500);
end;

{ La guarda de occurrence (David, 9-oct-2026): con un ancla que TRAE
  sangria, la linea que eligio occurrence -contando sin la sangria- tiene que
  llevar ESA sangria, comparada exacta (un tabulador no son cuatro espacios).
  Si no, la negativa con las candidatas: la de occurrence y las coincidencias
  del MOTOR (la regla de cada tool; en un bloque, sus inicios) que llevan la
  sangria del ancla, cada una con su numero de occurrence, para contestar a la
  primera. Nunca se escribe en la "probable": la sangria como desempate
  callado seria adivinar otra vez. La sangria la dice la primera linea CON
  TEXTO del ancla (una en blanco no lleva). Con una sola coincidencia no hay
  nada que elegir y no salta (como la misma edicion sin occurrence). '' = pasa. }
function GuardaDeSangria(const ALines: TArray<string>; const AAncla: string;
  AEntrada, ANth, ALinea: Integer): string;
var
  Ancla: TArray<string>;
  Inicios: TArray<Integer>;
  Sangria, Lista, Resto: string;
  J, K, N: Integer;
begin
  Result := '';
  if (AAncla = '') or (ALinea < 1) or (ALinea > Length(ALines)) then
    Exit;
  Ancla := LineasDelAncla(AAncla);
  J := 0;
  while (J < High(Ancla)) and (Ancla[J].Trim = '') do
    Inc(J);
  Sangria := '';
  if Ancla[J].Trim <> '' then
    Sangria := LeadingWhite(Ancla[J]);
  if (Sangria = '') or (ALinea - 1 + J > High(ALines)) or
     (LeadingWhite(ALines[ALinea - 1 + J]) = Sangria) then
    Exit;
  // todas las coincidencias del motor, en su orden: el de occurrence (el
  // ancla normalizada: una de una linea que acaba en salto no casaba con
  // nada cruda, y la negativa era la de un bloque corto; revisor propio)
  Inicios := IniciosDelAncla(ALines, AAncla);
  if Length(Inicios) <= 1 then
    Exit;
  // cada una citada por su linea CON TEXTO (la J del ancla): la primera de un
  // bloque que empieza en blanco no orientaba nada; y las que no caben en la
  // lista, con sus K, que si no no se pueden elegir (revisor propio)
  N := 0;
  Lista := '';
  Resto := '';
  for K := 0 to High(Inicios) do
    if (Inicios[K] + J <= High(ALines)) and (LeadingWhite(ALines[Inicios[K] + J]) = Sangria) then
    begin
      Inc(N);
      if N <= 5 then
        Lista := Lista + '  ' + MsgFmt(SF_PATCH_SANGRIA_CANDIDATA_FMT,
          [Inicios[K] + J + 1, K + 1, CitaDeLinea(Inicios[K] + J + 1, ALines[Inicios[K] + J])]) + #10
      else
        Resto := Resto + IfThen(Resto <> '', ', ') + IntToStr(K + 1);
    end;
  if N > 5 then
    Lista := Lista + MsgFmt(SF_PATCH_SANGRIA_MAS_FMT, [N - 5, Resto]) + #10;
  if N = 0 then
    Lista := MsgText(SF_PATCH_SANGRIA_NINGUNA);
  Result := MsgFmt(SR_PATCH_OCCURRENCE_SANGRIA_FMT, [AEntrada, ANth, ALinea + J,
    '  ' + MsgFmt(SF_PATCH_SANGRIA_CANDIDATA_FMT, [ALinea + J, ANth,
      CitaDeLinea(ALinea + J, ALines[ALinea - 1 + J])]),
    Lista.TrimRight([#10])]);
end;

function AplicaTanda(const APath, AEditsJson: string;
  const AAplicaUna: TAplicaUnaEdicion): string;
var
  Arr: TJSONArray;
  V: TJSONValue;
  Obj: TJSONObject;
  Foto: TFotoDeFicheros;
  Sb: TStringBuilder;
  Una, Anc, Nue: string;
  N, Fallo, EnLinea: Integer;
  Borra, Aplazado: Boolean;
begin
  Aplazado := False;
  V := TJSONObject.ParseJSONValue(AEditsJson);
  // Un cliente que codifica dos veces manda el array como CADENA JSON
  // (hermes, 25-sep-2026): se desenvuelve UNA vez. Lo que siga sin ser un
  // array se rechaza diciendo cuanto llego y como empieza, no solo "no es
  // array", que llevaba al cliente a reenviar lo mismo en bucle.
  if V is TJSONString then
  begin
    Una := TJSONString(V).Value;
    V.Free;
    V := TJSONObject.ParseJSONValue(Una);
  end;
  if not (V is TJSONArray) then
  begin
    V.Free;
    Exit(MsgFmt(SR_PATCH_EDITS_JSON_FMT,
      [Length(AEditsJson), Copy(AEditsJson.Trim, 1, 60)]));
  end;
  Arr := TJSONArray(V);
  // El cerrojo de escritura para la tanda ENTERA: la rama de bloque escribia
  // sin el, y dos agentes sobre el mismo fichero perdian ediciones con OK
  // (tercera revision, 27-sep-2026, medido en vivo). Recursivo: la edicion
  // suelta que se llama por dentro lo vuelve a tomar sin bloquearse.
  EnterFileEdit;
  try
    if Arr.Count = 0 then
      Exit(MsgText(SR_PATCH_EDITS_EMPTY));
    if Arr.Count > MAX_EDITS then
      Exit(MsgFmt(SR_PATCH_EDITS_TOOMANY_FMT, [MAX_EDITS]));
    if not TFile.Exists(APath) then
      Exit(NoEsFichero(APath, MsgFmt(SR_PATCH_EDITS_NOFILE_FMT, [APath])));
    Foto.Toma([APath]); // la red: el fichero antes de nada
    Sb := TStringBuilder.Create;
    try
      // "occurrence" se resuelve AQUI, UNA VEZ, contra el fichero ORIGINAL, y
      // despues se ARRASTRA segun cada entrada aplicada anade o quita lineas.
      // Recontarlo dentro del bucle, sobre el fichero YA MUTADO, es justo lo
      // contrario de lo que promete la descripcion del parametro ("los
      // numeros de linea SE MUEVEN y occurrence no"): pedir las ocurrencias
      // 1, 2 y 3 dejaba la 2 y la 3 INTERCAMBIADAS, y borrar la 1 y la 2
      // borraba la 1 y la 3 - contestando "OK" a todo. Escribir en el sitio
      // equivocado y decir que fue bien es la peor forma de fallar que tiene
      // una tool de escritura.
      var Ocurr: TArray<Integer>;
      SetLength(Ocurr, Arr.Count);
      // El final de un RANGO es un numero de linea, o sea que se mueve
      // exactamente igual que los demas: se arrastra en el mismo bucle de
      // abajo. Dejarlo fijo seria el bug de "occurrence" otra vez, ahora
      // llevandose por delante lineas que no eran.
      var Hasta: TArray<Integer>;
      SetLength(Hasta, Arr.Count);
      // el fichero de ANTES de la tanda, leido una vez: el de la guarda de
      // sangria y el de las anclas sin desempate (nil si no se puede leer)
      var LineasAntes: TArray<string> := nil;
      try
        var EncG: string;
        LineasAntes := LineasDelTexto(PatchLoadText(APath, EncG));
      except
        LineasAntes := nil;
      end;
      for N := 0 to Arr.Count - 1 do
      begin
        Ocurr[N] := 0;
        Hasta[N] := 0;
        if Arr.Items[N] is TJSONObject then
        begin
          var O2 := TJSONObject(Arr.Items[N]);
          // Un campo que no existe se leia y se tiraba. Se compara SIN ignorar
          // mayusculas a proposito: "Old" tampoco lo lee nadie mas abajo, asi
          // que tampoco puede pasar por bueno.
          for var Par in O2 do
          begin
            // sin ignorar mayusculas: MatchStr, no MatchText
            if not MatchStr(Par.JsonString.Value, CAMPOS_DE_UNA_EDICION) then
              Exit(MsgFmt(SR_PATCH_EDIT_KEY_FMT,
                [N + 1, Par.JsonString.Value, string.Join(', ', CAMPOS_DE_UNA_EDICION)]));
            // un "new" que llega como objeto se leia como '' y la linea
            // quedaba en blanco contestando OK (tercera revision, medido)
            if MatchStr(Par.JsonString.Value, ['old', 'new', 'fragment']) and
               not (Par.JsonValue is TJSONString) and not (Par.JsonValue is TJSONNull) then
              Exit(MsgFmt(SR_PATCH_EDIT_NO_TEXTO_FMT,
                [N + 1, Par.JsonString.Value]));
            // y los enteros y el booleano, por la regla de un parametro: se
            // leian con un valor por defecto ("delete":"yes" dejaba la linea
            // en blanco, "toline":-1 se ignoraba) contestando OK
            if not (Par.JsonValue is TJSONNull) then
            begin
              var MotivoValor := '';
              if MatchStr(Par.JsonString.Value, ['atline', 'toline', 'occurrence']) then
              begin
                var I64: Int64;
                MotivoValor := TMCPSerializer.MotivoEntero(Par.JsonValue, High(Integer), I64);
              end
              else if Par.JsonString.Value = 'delete' then
              begin
                var B: Boolean;
                MotivoValor := TMCPSerializer.MotivoBooleano(Par.JsonValue, B);
              end;
              if MotivoValor <> '' then
                Exit(MsgFmt(SR_PATCH_EDIT_VALOR_FMT,
                  [N + 1, Par.JsonString.Value, MotivoValor]));
            end;
          end;
          Hasta[N] := EnteroDeEntrada(O2, 'toline');
          var Nth := EnteroDeEntrada(O2, 'occurrence');
          var Anc2 := O2.GetValue<string>('old', '');
          // occurrence cuenta el TEXTO de un ancla: una linea en blanco no lo
          // tiene, y "aparece 0 veces" enganaba (revisor de la noche, B-3)
          if (Nth > 0) and (Anc2.Trim = '') and (O2.GetValue<string>('fragment', '') = '') then
            Exit(MsgFmt(SR_PATCH_OCURRENCIA_SIN_TEXTO_FMT, [N + 1]));
          if (EnteroDeEntrada(O2, 'atline') = 0) and (Nth > 0) then
          begin
            // Las de BLOQUE tambien: era la tercera puerta del mismo bug y
            // se quedo abierta cuando se cerraron las de una linea.
            if Anc2.Contains(#10) then
              Ocurr[N] := NthBlockLine(APath, Anc2, Nth)
            else
              Ocurr[N] := NthOccurrenceLine(APath, Anc2, Nth);
            // Pedir la ocurrencia 5 de algo que aparece 3 veces devolvia 0,
            // el motor lo leia como "sin desempate" y la edicion caia en la
            // PRIMERA. El parametro que existe para no equivocarse de sitio
            // te llevaba al sitio equivocado, contestando OK.
            if Ocurr[N] = 0 then
            begin
              var Hay := 0;
              while Hay < 500 do
              begin
                var Sig: Integer;
                if Anc2.Contains(#10) then
                  Sig := NthBlockLine(APath, Anc2, Hay + 1)
                else
                  Sig := NthOccurrenceLine(APath, Anc2, Hay + 1);
                if Sig = 0 then
                  Break;
                Inc(Hay);
              end;
              var Cabeza := PrimerTrozo(Anc2, [#10]).Trim;
              Exit(MsgFmt(SR_PATCH_OCCURRENCE_FMT, [N + 1, Nth,
                Cabeza.Substring(0, Min(60, Length(Cabeza))), Hay]));
            end;
            // ...y si el ancla trae sangria, la linea elegida lleva ESA: si no,
            // se dicen las candidatas y no se escribe (la guarda de sangria,
            // David 9-oct-2026; las mismas lineas que cuenta NthOccurrenceLine)
            var Guarda := GuardaDeSangria(LineasAntes, Anc2, N + 1, Nth, Ocurr[N]);
            if Guarda <> '' then
              Exit(Guarda);
          end;
          // ...y SIN desempate, el ancla se juzga tambien en el fichero de
          // ANTES de la tanda, el que leyo el agente y donde cuenta
          // occurrence: repetida ahi, la entrada escribia en la que quedase
          // unica cuando le tocaba, contestando OK ("x" en las lineas 4 y 6,
          // la 1 cambia la 6 por occurrence y la 2, sin desempate, caia en la
          // 4: P2 de A15, medido contra r1222af). La que no esta ahi la crea
          // una entrada anterior: se juzga cuando le toque. La primera se
          // juzga en ese mismo fichero, y su negativa es la del motor (EDIT-077,
          // la de un bloque EDIT-015, que dice como desempatar)
          if (N > 0) and (EnteroDeEntrada(O2, 'atline') = 0) and (Nth = 0) and
             (Anc2.Trim <> '') and (O2.GetValue<string>('fragment', '') = '') then
          begin
            var Donde := IniciosDelAncla(LineasAntes, Anc2);
            if Length(Donde) > 1 then
              Exit(MsgFmt(SR_PATCH_ANCLA_REPETIDA_FMT,
                [N + 1, Length(Donde), ListaDeLineas(Donde)]));
          end;
        end;
      end;
      // Dos entradas que apuntan a la MISMA linea. occurrence cuenta sobre el
      // fichero de ANTES de la tanda (por eso no se mueve con las entradas
      // anteriores): pedir "occurrence 1" dos veces, esperando que la segunda
      // sea la siguiente aparicion, deja a la segunda sin ancla a mitad de
      // tanda con un mensaje que no explicaba nada (me paso dos veces el
      // 24-sep-2026 usando el servidor como agente). Se rechaza en la puerta.
      for N := 0 to Arr.Count - 1 do
        for var M := 0 to N - 1 do
          if (Ocurr[N] > 0) and (Ocurr[N] = Ocurr[M]) then
            Exit(MsgFmt(SR_PATCH_OCCURRENCE_DUP_FMT, [M + 1, N + 1, Ocurr[N]]));
      N := 0;
      Fallo := 0;
      var Avisos: TArray<string> := [];
      var SinCambios := 0; // entradas que el motor contesto EDIT-113
      var Causa := ''; // la negativa de la entrada que cayo: da el resultado
      // La ESTRUCTURA (EDIT-085/086) es del fichero entero: la de cada entrada
      // se aparta y se juzga UNA vez al acabar, del original al final
      // (AvisoDeEstructura). Si al final no se puede releer, valen las de
      // las entradas, como antes.
      var DeEstructura: TArray<string> := [];
      var TextoAntes := '';
      try
        var EncAntes: string;
        TextoAntes := PatchLoadText(APath, EncAntes);
      except
        TextoAntes := '';
      end;
      // el juicio del FORM, como el de la estructura, del fichero entero: las
      // entradas no lo hacen, y se hace UNA vez al acabar (H6, abajo). Siempre:
      // un .pas alcanza los forms de su unidad, y a que alcanza lo sabe
      // JuicioDeLoEscrito (una tanda de un .pas juzgaba cada entrada)
      Aplazado := True;
      if Aplazado then
        AplazaJuicioDeForm(True);
      for V in Arr do
      begin
        Inc(N);
        if not (V is TJSONObject) then
        begin
          Fallo := N;
          Sb.Append(FilaDeEntrada(N, MsgText(SF_EDIT_NO_ES_OBJETO))).Append(#10);
          Break;
        end;
        Obj := TJSONObject(V);
        // antes de cada entrada: si otro proceso cambio el fichero desde la
        // anterior, el deshacer no se lo llevara (TFotoDeFicheros.Vigila)
        Foto.Vigila(APath);
        Anc := Obj.GetValue<string>('old', '');
        Nue := Obj.GetValue<string>('new', '');
        // El antes, para saber DONDE cambio y CUANTO y arrastrar lo pendiente.
        // Se toma para las DOS ramas: antes solo lo hacia la de una linea,
        // porque la de bloque salia por Continue justo encima del arrastre -
        // asi que un bloque que anadia o quitaba lineas NO desplazaba las
        // ocurrencias pendientes. Con las dos ramas juntas el agujero se ve;
        // separadas no se veia.
        var EncTmp: string;
        var AntesL: TArray<string>;
        try
          AntesL := SplitToLines(PatchLoadText(APath, EncTmp));
        except
          AntesL := nil;
        end;
        // Ancla de VARIAS lineas: se sustituye el bloque entero. La regla de
        // "una linea" protege a una edicion suelta, donde un ancla larga es
        // una ocasion larga de equivocarse; dentro de una tanda, donde quien
        // llama sustituye un cuerpo que acaba de copiar, era trabajo puro.
        // MODO FRAGMENTO: la entrada se convierte AQUI, contra el fichero
        // tal como esta en este momento de la tanda, en un ancla de linea
        // completa - y de ahi para abajo es una entrada como las demas.
        var Frag := Obj.GetValue<string>('fragment', '');
        if Frag <> '' then
        begin
          // lo que choca con fragment, por LA escalera (OtroModoConFragmento)
          var Otros := OtroModoConFragmento(Anc <> '', Anc, BooleanoDeEntrada(Obj, 'delete'),
            Hasta[N - 1], IfThen(EnteroDeEntrada(Obj, 'occurrence') > 0, 'occurrence', ''));
          var NueLinea: string;
          var Mal: string;
          // lee el fichero: una excepcion aqui (otro proceso lo tiene) es el
          // fallo de ESTA entrada, con su deshacer; se escapaba sin el
          // (tercera revision, 27-sep-2026)
          try
            Mal := FragmentoALinea(APath, Frag, Nue,
              EnteroDeEntrada(Obj, 'atline'), Otros, Anc, NueLinea);
          except
            on E: Exception do
              Mal := MsgExcepcion(E.ClassName, E.Message);
          end;
          if Mal <> '' then
          begin
            Fallo := N;
            Causa := Mal;
            Sb.Append(FilaDeEntrada(N, Mal)).Append(#10);
            Break;
          end;
          Nue := NueLinea;
        end;
        var EsBloque := Anc.Contains(#10);
        if EsBloque and (Hasta[N - 1] > 0) then
        begin
          Fallo := N;
          Causa := MsgText(SR_RANGE_WITH_BLOCK);
          Sb.Append(FilaDeEntrada(N, MsgText(SR_RANGE_WITH_BLOCK))).Append(#10);
          Break;
        end;
        // Una excepcion es un fallo como otro cualquiera: se saltaba el
        // deshacer y la entrada anterior quedaba escrita - lo mismo que se
        // arreglo en el commit de un changeset y quedo aqui sin arreglar
        // (segunda revision, 27-sep-2026, medido por dos agentes)
        try
          // el atline de la entrada gana, en las dos ramas: el de un BLOQUE no
          // llegaba a ApplyBlockEdit - se ignoraba y, con occurrence, el bloque
          // se contaba sobre el fichero YA mutado (la tercera puerta del bug de
          // occurrence, abierta por atline; revisor propio, 9-oct-2026)
          EnLinea := EnteroDeEntrada(Obj, 'atline');
          if EnLinea = 0 then
            EnLinea := Ocurr[N - 1]; // resuelto arriba y ya desplazado
          Borra := BooleanoDeEntrada(Obj, 'delete');
          if EsBloque then
          begin
            // delete en un bloque, por LA regla de delete: el bloque se va
            // entero y sin new (no se leia, y el bloque pasaba a ser new)
            Una := '';
            if Borra then
              Una := DeleteDeLineaDenegado(True, Anc, Nue, EnLinea);
            if Una = '' then
              Una := ApplyBlockEdit(APath, Anc, Nue,
                EnteroDeEntrada(Obj, 'occurrence'), EnLinea);
          end
          else
          begin
            // el final del rango cuenta como su principio: con atline las dos
            // son lineas del fichero tal como lo dejaron las entradas de antes
            // (atline no se arrastra) y el toline va tal cual lo dio el agente;
            // sin atline, el principio sale del fichero de antes de la tanda y
            // el final se arrastro con el. Con el arrastrado contra un atline
            // tal cual, atline=14 toline=15 tras una insercion de dos lineas
            // borraba hasta la 17 y contestaba APPLIED (revisor de version de
            // la 1.18.0, medido)
            var Fin := Hasta[N - 1];
            if EnteroDeEntrada(Obj, 'atline') > 0 then
              Fin := EnteroDeEntrada(Obj, 'toline');
            Una := AAplicaUna(Anc, Nue, EnLinea, Fin, Borra);
          end;
        except
          on E: Exception do
            Una := MsgExcepcion(E.ClassName, E.Message);
        end;
        var Eco := '';
        if (AntesL <> nil) and not EsFallo(Una) then
        try
          var DespuesL := SplitToLines(PatchLoadText(APath, EncTmp));
          var Delta := Length(DespuesL) - Length(AntesL);
          // La primera linea que difiere: de ahi para abajo todo se mueve, y
          // ademas es DONDE cayo esta edicion.
          var Cambio := 0;
          while (Cambio < Length(AntesL)) and (Cambio < Length(DespuesL)) and
                (AntesL[Cambio] = DespuesL[Cambio]) do
            Inc(Cambio);
          // lo de DEBAJO de lo cambiado se mueve (la regla de todos,
          // ZonaDelCambio: la primera linea distinta sola no veia una
          // insercion cuya primera linea nueva era la vieja)
          if Delta <> 0 then
          begin
            var Desde, DeltaZ: Integer;
            ZonaDelCambio(AntesL, DespuesL, Desde, DeltaZ);
            for var K := N to High(Ocurr) do
            begin
              Ocurr[K] := LineaTrasCambio(Ocurr[K], Desde, DeltaZ);
              Hasta[K] := LineaTrasCambio(Hasta[K], Desde, DeltaZ);
            end;
          end;
          // EL ECO DE VERIFICACION, releido del disco. Una edicion suelta lo
          // devuelve desde siempre; una TANDA solo decia "OK: <ancla>", que
          // es lo que PEDISTE, no lo que PASO. Y la propia tool recomienda
          // tandas para refactorizar, que es justo cuando hace mas falta: con
          // el bug de "occurrence" escribiendo en la linea equivocada, un
          // agente no tenia forma de enterarse (medido 2026-09-20). Es una
          // cita del disco (CitaDeLinea), recortada: verificacion, no un ancla
          // para copiar (eso es delphi_read)
          // la ultima de SplitToLines, vacia, es lo que va detras del ultimo
          // salto: no es una linea (delphi_read no la cuenta). Al borrar la
          // ultima linea de un fichero con salto final, el eco citaba ESA
          // como la linea de alli: '3|' (revision de la 1.13.0)
          var Reales := Length(DespuesL);
          if (Reales > 0) and (DespuesL[Reales - 1] = '') then
            Dec(Reales);
          if Cambio < Reales then
            Eco := CitaDeLinea(Cambio + 1, Copy(DespuesL[Cambio].Trim, 1, 90))
          else if Delta < 0 then
            Eco := MsgFmt(SF_EDIT_LINEA_QUITADA_FMT, [Cambio + 1]);
        except
          // si no se puede releer, mejor no tocar lo pendiente
        end;
        // El motor dice RECHAZADO / error cuando se nego; cualquier otra cosa
        // es una edicion aplicada con su auditoria.
        if EsFallo(Una) then
        begin
          Fallo := N;
          Causa := Una;
          // #10, no AppendLine (CRLF en Windows): el mensaje que lo envuelve
          // separa con #10 y el eco salia con los dos (test_round34, 26-sep)
          Sb.Append(FilaDeEntrada(N, Una)).Append(#10);
          Break;
        end;
        Foto.Anota(APath); // lo que dejo esta entrada: lo unico que el deshacer da por suyo
        // Los avisos del motor (*** ... ***) no se pierden al resumir la
        // edicion en una linea: en una tanda no llegaban al agente. EL lector
        // de los avisos de una respuesta (AvisosDelMotor), con lo que cada uno
        // lleva debajo
        // (el juicio del form, y su nota de form ancho, no van aqui: se hacen
        // una vez al final, H6)
        for var LA in AvisosDelMotor(Una) do
          if EsMsg(LA, SN_EDIT_ESTRUCTURA_ROTA_END_FMT) or
             EsMsg(LA, SN_EDIT_ESTRUCTURA_ROTA_ULTIMA) then
            DeEstructura := DeEstructura + [FilaDeEntrada(N, LA)]
          else
            Avisos := Avisos + [FilaDeEntrada(N, LA)];
        // lo PEDIDO: en modo fragmento, el fragmento que tecleo el agente (Anc
        // es ya la linea entera del disco que encontro FragmentoALinea, y la
        // fila la mostraba como si la hubiera pedido; revision del 4-oct-2026)
        var Pedido := Anc;
        if Frag <> '' then
          Pedido := Frag;
        if EsMsg(Una, SN_EDIT_SIN_CAMBIOS_FMT) then
        begin
          // no cambio nada: se dice, no se cuenta como OK (sexta revision)
          Inc(SinCambios);
          Una := MsgFmt(SF_EDIT_SIN_CAMBIOS_ANCLA_FMT,
            [N, Pedido.Trim.Substring(0, Min(70, Length(Pedido.Trim)))]);
        end
        else if EsBloque then
          Una := MsgFmt(SF_EDIT_OK_BLOQUE_LINEAS_FMT,
            [N, Length(LineasDelAncla(Anc))])
        else
          Una := MsgFmt(SF_EDIT_OK_ANCLA_FMT,
            [N, Pedido.Trim.Substring(0, Min(70, Length(Pedido.Trim)))]);
        // EL ECO, en una linea SUYA ('N| texto', la forma de las citas del
        // disco: el enmascarador deja tal cual en una negativa -un ROLLBACK-
        // las lineas que empiezan por 'N|') mientras enmascara la de lo
        // pedido. En la misma fila se enmascaraba entera y '[^\s:]' volvia
        // '[^\srv0:]' (4-oct-2026); partir la fila en el lector abria la
        // excepcion a cualquier texto del agente (revision). Es verificacion,
        // recortada: no es un ancla para copiar, eso es delphi_read.
        if Eco <> '' then
          Una := Una + '  ->'#10 + SANGRIA_FILA + Eco;
        Sb.Append(Una).Append(#10);
      end;
      if Fallo > 0 then
      begin
        var NoVolvio := Foto.Restaura; // todo o nada, byte a byte
        Result := MsgConCausa(SR_PATCH_EDITS_ROLLED_FMT, Causa,
          [Fallo, Arr.Count, Sb.ToString.TrimRight]);
        // lo que no volvio MANDA: la cabecera decia "todo volvio" y el
        // aviso iba detras (tercera revision)
        if NoVolvio <> '' then
          Result := MsgFmt(SR_FOTO_NO_VOLVIO_FMT, [NoVolvio, Sb.ToString.TrimRight]);
        Exit;
      end;
      if (Length(DeEstructura) > 0) and (TextoAntes = '') then
        Avisos := Avisos + DeEstructura
      // y en un fuente, sin aviso de ninguna entrada tambien: una de BLOQUE no
      // pregunta por la estructura (ApplyBlockEdit) y una tanda de bloques que
      // dejaba el fichero sin su end. no decia nada (medido el 10-oct-2026)
      else if (Length(DeEstructura) > 0) or ((TextoAntes <> '') and EsRutaDeFuente(APath)) then
      try
        var EncDespues: string;
        var Final := AvisoDeEstructura(TextoAntes, PatchLoadText(APath, EncDespues));
        if Final <> '' then
          Avisos := Avisos + [Final];
      except
        Avisos := Avisos + DeEstructura;
      end;
      // el juicio del FORM (DesignerLint: el parser del IDE, las propiedades, el
      // enlace con su clase y la nota de form ancho, DSGN-121) es del fichero
      // ENTERO: UNA vez, sobre lo que quedo escrito. Cada entrada juzgaba su
      // estado intermedio y un bloque movido en dos pasos daba DSGN-021 de un
      // form que acababa limpio (H6 de Hermes, 1.18.2); la nota de form ancho
      // se perdia en los avisos de las entradas (B1) y va con el
      // ...y solo si se ESCRIBIO: una tanda sin cambios decia EDIT-114 y
      // despues EDIT-084 "edited" o el DSGN-021 de un form que ya estaba roto
      // (W2 del revisor de cierre de la 1.18.2, medido; DoEdit no juzga un
      // EDIT-113)
      if Aplazado and (SinCambios < Arr.Count) then
      try
        var EncF: string;
        Avisos := Avisos + JuicioDeLoEscrito(APath, PatchLoadText(APath, EncF), EncF);
      except
        // un form que no se relee no tumba una tanda ya escrita
      end;
      if SinCambios = Arr.Count then
        Result := MsgFmt(SN_PATCH_EDITS_SIN_CAMBIOS_FMT,
          [Arr.Count, TPath.GetFileName(APath)])
      else
        Result := MsgFmt(SN_PATCH_EDITS_OK_FMT,
          [Arr.Count, TPath.GetFileName(APath), Sb.ToString.TrimRight]);
      if Length(Avisos) > 0 then
        Result := Result + #10 + string.Join(#10, Avisos);
    finally
      Sb.Free;
    end;
  finally
    if Aplazado then
      AplazaJuicioDeForm(False);
    LeaveFileEdit;
    Arr.Free;
  end;
end;

function NoEsFuenteDelphi(const APath: string): string;
begin
  if not TFile.Exists(APath) then
    Exit(NoEsFichero(APath, MsgFmt(SR_LSP_NO_FILE_FMT, [APath])));
  Result := '';
  if not EsRutaDeFuente(APath) then // la lista de la unit
    Exit(MsgFmt(SR_LSP_NOT_SOURCE_FMT, [TPath.GetFileName(APath)]));
  // ...y que se le pueda NOMBRAR al motor: su uri es UTF-8 y medio caracter
  // (un sustituto suelto, por EL lector) no cabe en ella. Con uno en el
  // nombre de una carpeta el motor contestaba de otra ruta: null en definition
  // y hover, LSP-003 en references, "0 errores" en diagnostics (medido el
  // 14-oct, punto 4 de la 1.18.2). LA negativa, la del nombrador (que ademas
  // la lanza a quien le pida esa uri: W5 del revisor de cierre)
  Result := TLspClient.RutaSinUri(TPath.GetFullPath(APath));
end;

function PositionOutOfRange(const APath: string; ALine, AChar: Integer): string;
var
  Lines: TArray<string>;
  Enc: string;
begin
  Result := '';
  if (ALine < 0) or (AChar < 0) then
    Exit(MsgFmt(SR_LSP_NEGATIVE_FMT, [ALine, AChar]));
  // Una ruta que no esta llegaba al motor y volvia como "Error executing
  // tool: File not found", que en las reglas de este servidor significa "me
  // he roto por dentro" y no era el caso (2026-08-25).
  Result := NoEsFuenteDelphi(APath);
  if Result <> '' then
    Exit;
  try
    Lines := LineasDelTexto(PatchLoadText(APath, Enc)); // como delphi_read
  except
    Exit;
  end;
  if ALine >= Length(Lines) then
    Exit(MsgFmt(SR_LSP_LINE_RANGE_FMT,
      [ALine, TPath.GetFileName(APath), Length(Lines), Length(Lines) - 1]))
  else if AChar > Length(Lines[ALine]) then
    Exit(MsgFmt(SR_LSP_CHAR_RANGE_FMT,
      [AChar, ALine, ALine + 1, Length(Lines[ALine]), Lines[ALine].Trim]));
end;

function PosicionQueNoSePregunta(const APath: string; ALine, AChar: Integer): string;
begin
  Result := ReadPathDenied(APath);
  if Result = '' then
    Result := PositionOutOfRange(APath, ALine, AChar);
end;

{ READ-007 entero: que unos bytes no cuadran con su codificacion, con la
  primera linea que no cuadra (la que lleva U+FFFD) y, en un UTF-8, como seria
  esa linea en la otra lectura posible, para que el agente vea las dos y lo
  arregle en el IDE (David, 9-oct-2026). '' si los bytes vuelven iguales.
  ALineas: las del texto leido en K. }
function NotaDeIdaYVuelta(const B: TArray<Byte>; K: TEncKind;
  const ALineas: TArray<string>): string;
var
  I: Integer;
  Otras: TArray<string>;
begin
  Result := '';
  if BytesVuelvenIgual(B, K) then
    Exit;
  Result := MsgFmt(SN_READ_BYTES_NO_VUELVEN_FMT, [EncName(K)]);
  for I := 0 to High(ALineas) do
    if Pos(#$FFFD, ALineas[I]) > 0 then
    begin
      Result := Result + #10'  ' + MsgFmt(SF_READ_PRIMERA_NO_CUADRA_FMT,
        [CitaDeLinea(I + 1, ALineas[I])]);
      if K in [ekUtf8, ekUtf8Bom] then
      begin
        Otras := LineasDelTexto(DecodeBytes(Copy(B, PreambleLen(K), MaxInt), ekAnsi));
        if I <= High(Otras) then
          Result := Result + #10'  ' + MsgFmt(SF_READ_OTRA_LECTURA_FMT,
            [EncName(ekAnsi), CitaDeLinea(I + 1, Otras[I])]);
      end;
      Break;
    end;
  Result := Result + #10;
end;

{ READ-008 (regla 5 de la 1.18.0, David 9-oct-2026): un FUENTE en UTF-8 sin
  BOM con acentos lo ensena bien el IDE y lo compila mal dcc (como ANSI); se
  dice al LEERLO, con la salida del IDE - al escribirlo solo lo decia una
  edicion suelta y no una tanda, un adduses o un changeset (revisor propio
  de r5): una nota de un sitio, no de unos escritores si y otros no. '' si
  no es el caso. K: la que dijo EL detector de B. Un form no: sin BOM se lee
  en ANSI, como dcc. Ni en una maquina cuya ANSI es UTF-8 (la opcion "UTF-8
  para todo el mundo" de Windows): alli dcc lo lee bien. Y solo si los
  acentos estan en lo que LEE dcc - el codigo, sus cadenas y sus directivas
  (la ruta de un $I) -, por EL lexico Pascal: solo los COMENTARIOS no
  llegan al programa, y la nota salia en fuentes que no tenian nada que
  arreglar (r5-L8 de la 1.18.0). OJO: la vista conserva las cadenas, y
  CodigoPascal las blanquea - con el, un acento en una cadena no daria la
  nota (medido); y con BlankComments, que blanquea las directivas, uno en
  la ruta de un $I tampoco (revisor de la tanda, TR-B1). }
function NotaDeUtf8SinBom(const APath: string; K: TEncKind; const B: TArray<Byte>): string;
begin
  Result := '';
  if (K = ekUtf8) and (PaginaAnsi <> CP_UTF8) and EsRutaDeFuente(APath) and HayByteAlto(B) and
     not IsAscii(VistaPascal(DecodeBytes(B, K), [cpCodigo, cpCadena, cpDirectiva])) then
    Result := MsgFmt(SN_READ_UTF8_SIN_BOM_FMT, [EncName(ekAnsi)])
  // ...y un FORM sin BOM se lee en ANSI, como el IDE y dcc: si sus bytes son
  // UTF-8 - lo dice EL detector sin la regla de los forms -, lo que se ve
  // (la o partida en dos letras) es lo que tendra el programa, y lint daba
  // CLEAN (medido con dcc el 13-oct, testsserver\mide-dfm)
  else if (K = ekAnsi) and (PaginaAnsi <> CP_UTF8) and EsRutaDeDesigner(APath) and HayByteAlto(B) and
     (DetectEnc(B, False) = ekUtf8) then
  begin
    Result := MsgFmt(SN_READ_FORM_UTF8_SIN_BOM_FMT, [EncName(ekAnsi)]);
    // ...con las DOS lecturas de su primera linea con letras de mas alla de
    // ASCII: un ANSI de verdad puede casar con UTF-8 por azar y el detector no
    // lo separa; quien lee si (W3 del revisor de cierre de la 1.18.2)
    var Ansi := LineasDelTexto(DecodeBytes(B, ekAnsi));
    var Utf8 := LineasDelTexto(DecodeBytes(B, ekUtf8));
    for var I := 0 to Min(High(Ansi), High(Utf8)) do
      if not IsAscii(Ansi[I]) then
      begin
        Result := Result +
          #10'  ' + MsgFmt(SF_READ_OTRA_LECTURA_FMT, [EncName(ekAnsi), CitaDeLinea(I + 1, Ansi[I])]) +
          #10'  ' + MsgFmt(SF_READ_OTRA_LECTURA_FMT, [EncName(ekUtf8), CitaDeLinea(I + 1, Utf8[I])]);
        Break;
      end;
  end;
end;

function NotaDeUtf8SinBomDe(const APath: string): string;
begin
  try
    var B := LeeBytes(APath, [ltJaula]);
    Result := NotaDeUtf8SinBom(APath, DetectEnc(B, EsRutaDeDesigner(APath)), B);
  except
    Result := ''; // una nota no tumba nada
  end;
end;

function NotaDeCodificacionDeForm(const APath: string): string;
var
  K: TEncKind;
begin
  Result := '';
  try
    if FormAncho(APath, K) then
      Result := NotaDeFormAncho(ExtractFileName(APath), EncName(K));
    if Result = '' then
      Result := NotaDeUtf8SinBomDe(APath);
  except
    Result := ''; // una nota no tumba nada
  end;
end;

function FormAnchoQueNoCarga(const APath: string): string;
var
  K: TEncKind;
  Linea: Integer;
begin
  Result := '';
  if not FormAncho(APath, K) then
    Exit;
  try
    var Dijo := ErrorDelParserDeForm(LeeBytes(APath, [ltJaula]), Linea);
    if Dijo <> '' then
      Result := MsgFmt(SR_DSGN_FORM_ANCHO_NO_CARGA_FMT, [ExtractFileName(APath), EncName(K), Dijo]);
  except
    Result := ''; // lo que la puerta no deja leer lo dice el comando que sigue
  end;
end;

function ReadNumbered(const APath: string; AFrom, ATo: Integer): string;
var
  B: TBytes;
  K: TEncKind;
  M: TMetrics;
  Text, Eol, Body: string;
  Denied: string;
  Lines: TArray<string>;
  IniL, FinL, I: Integer;
  Sb: TStringBuilder;
  Cut, NotaBin, NotaVuelta, NotaUtf8: string;
begin
  Denied := ReadPathDenied(APath); // reading may enter the library zone
  if Denied <> '' then
    Exit(Denied);
  if not TFile.Exists(APath) then
  begin
    // "No esta" y "no es un fichero" son cosas distintas, y contestar la
    // primera cuando pasa la segunda manda al agente a buscar una ruta que
    // tiene delante: delphi_read sobre la raiz del repo contestaba "no
    // existe" de una carpeta con 20 entradas (medido 2026-09-20). Y el
    // prefijo era "RECHAZADO:", que por la regla 11 de las convenciones
    // significa "no insistas, cambia de camino"; un nombre mal escrito es
    // "corrige y repite", o sea "error:".
    if TDirectory.Exists(APath) then
      Exit(MsgFmt(SR_LSP_IS_FOLDER_FMT, [APath]));
    Exit(MsgFmt(SR_LSP_NO_FILE_FMT, [APath]));
  end;
  B := TFile.ReadAllBytes(APath);
  // Un .dfm BINARIO se lee al vuelo como texto ("Ver como texto" del IDE,
  // Lsp.DesignerBin) y se dice: un form legacy dejaba ciego al agente
  // (Hermes, 2026-09-24). Editarlo pide to-text; leerlo, no.
  NotaBin := '';
  if EsRutaDeDesigner(APath) and IsBinaryDesignerBytes(B) then
  begin
    NotaBin := DesignerBinaryToText(B, Text);
    if NotaBin <> '' then
      Exit(MsgEnvuelve(SR_RECHAZADO_FMT, NotaBin));
    B := TEncoding.UTF8.GetBytes(Text);
    NotaBin := MsgText(SN_READ_BINARY_DESIGNER) + #10;
  end;
  // Un binario (un exe, un .res, un .bin.style) no es un texto que numerar:
  // 9 MB de mojibake quemaron un contexto para nada (medido 2026-08-24).
  // La regla es LooksBinaryBytes, la misma que delphi_textedit.
  if LooksBinaryBytes(B) then
    Exit(MsgFmt(SR_EDIT_FICHERO_BINARIO_NUL_FMT, [APath]));
  // (un binario leido al vuelo ya es UTF-8 nuestro: el form de texto sin BOM
  // es el que se lee en ANSI)
  K := DetectEnc(B, EsRutaDeDesigner(APath) and (NotaBin = ''));
  Text := DecodeBytes(B, K);
  M := Measure(B);
  // el salto por la regla de todos (SaltoDominante): esta decia LF de un
  // fichero de solo CR, y en empate LF donde la otra decia CRLF (octava)
  Eol := NombreDelSalto(SaltoDominante(Text));
  // El salto final CIERRA la ultima linea, no abre otra: "a\nb\n" son 2
  // lineas, y se ensenaba una tercera vacia que no existe (quinta revision)
  Lines := LineasDelTexto(Text);
  // lo que los escritores no reescribiran (ReescrituraDenegada) se dice al
  // leerlo, con la primera linea que no cuadra y su otra lectura (9-oct-2026)
  NotaVuelta := NotaDeIdaYVuelta(B, K, Lines);
  NotaUtf8 := NotaDeUtf8SinBom(APath, K, B);
  if NotaUtf8 <> '' then
    NotaVuelta := NotaVuelta + NotaUtf8 + #10;
  // Un fichero VACIO se lee: es un exito con cero lineas. Salia EDIT-100
  // INVALID_PARAM ("from=1 is past the end") (quinta revision)
  if (Length(Lines) = 0) and (AFrom <= 1) then
    Exit(NotaBin + NotaVuelta + MsgFmt(SK_EDIT_LECTURA_VACIO_FMT,
      [TPath.GetFileName(APath), EtiquetaDeCodificacion(K, not HayByteAlto(B)), Eol, Auditoria(M)]));
  IniL := AFrom;
  if IniL < 1 then IniL := 1;
  if IniL > Length(Lines) then
    Exit(MsgFmt(SR_EDIT_DESDE_MAS_ALLA_FINAL_FMT,
      [TPath.GetFileName(APath), EtiquetaDeCodificacion(K, not HayByteAlto(B)), Eol, Auditoria(M),
       Length(Lines), IniL]));
  FinL := ATo;
  if (FinL <= 0) or (FinL > Length(Lines)) then FinL := Length(Lines);
  // A range that runs backwards used to answer with a header and an EMPTY
  // body, which reads as "that stretch of the file is empty" (measured
  // 2026-08-25). It is a typo, and it gets told so.
  if FinL < IniL then
    Exit(MsgFmt(SR_READ_RANGE_FMT, [IniL, ATo, Length(Lines)]));
  Cut := '';
  if FinL - IniL + 1 > MAX_READ_LINES then
  begin
    FinL := IniL + MAX_READ_LINES - 1;
    Cut := #10 + MsgFmt(SN_EDIT_RECORTADO_EN_LINEA_FMT, [FinL, Length(Lines)]);
  end;
  Sb := TStringBuilder.Create;
  try
    for I := IniL to FinL do
      Sb.Append(CitaDeLinea(I, Lines[I - 1])).Append(#10);
    Body := Sb.ToString.TrimRight([#10]);
  finally
    Sb.Free;
  end;
  Result := NotaBin + NotaVuelta + MsgFmt(SK_EDIT_LECTURA_NUMERADA_FMT,
    [TPath.GetFileName(APath), EtiquetaDeCodificacion(K, not HayByteAlto(B)), Eol, Auditoria(M), IniL, FinL,
     Length(Lines), Body, Cut]);
end;

// -------------------------------------------------------------------------
// The edit pipeline (also the primitive that the insert modes call).
// -------------------------------------------------------------------------

function DoEdit(const APath, AOld, ANew: string; AAtLine: Integer;
  AIsDesigner: Boolean; ADelete: Boolean = False;
  AToLine: Integer = 0; AEnsayo: Boolean = False): string; forward;

function FindUniqueLine(const Lines: TArray<string>;
  const APred: TFunc<string, Boolean>; out AIdx: Integer): Boolean;
var
  I, Cnt: Integer;
begin
  Cnt := 0;
  AIdx := -1;
  for I := 0 to High(Lines) do
    if APred(Lines[I]) then
    begin
      Inc(Cnt);
      AIdx := I;
    end;
  Result := Cnt = 1;
end;

function FicheroQueNoEditaDelphiEdit(const APath: string): string;
var
  Ext: string;
begin
  // una carpeta decia "extension '' no soportada"
  Result := CarpetaEnVezDeFichero(APath);
  if Result <> '' then
    Exit;
  Ext := LowerCase(TPath.GetExtension(APath));
  if EsRutaDeProyecto(APath) then
    Exit(MsgFmt(SR_EDIT_FICHERO_DE_PROYECTO_FMT, [TPath.GetFileName(APath)]));
  if not EsRutaDeFuente(APath) and not EsRutaDeDesigner(APath) then
    Exit(MsgFmt(SR_EDIT_EXTENSION_SOPORTADA_ESTA_TOOL_FMT, [Ext]));
  if TFile.Exists(APath) then
  begin
    var B: TArray<Byte>;
    try
      B := LeeBytes(APath, [ltJaula]);
    except
      // cogido por otro proceso: la negativa de la edicion, no un INTERNAL
      on E: Exception do
        Exit(MsgExcepcion(E.ClassName, E.Message));
    end;
    // "esto no es texto" es LooksBinaryBytes, la regla de delphi_read y de
    // delphi_textedit: este motor editaba un .pas con bytes NUL (decima).
    // Un designer binario tiene su negativa propia, que apunta a to-text.
    // Two binary shapes exist (measured with the IDE's own convert.exe):
    // a raw stream starts 'TPF0'; the REAL on-disk binary .dfm/.fmx wraps
    // that stream in a 16-bit resource header whose first byte is $FF
    // (FF 0A 00 + UPPERCASED name + the TPF0 stream at ~offset 19). A text
    // form always begins with object/inherited/inline - never $FF.
    if EsRutaDeFuente(APath) and LooksBinaryBytes(B) then
      Exit(MsgFmt(SR_TEXT_PARECE_BINARIO_FMT, [TPath.GetFileName(APath)]));
    if EsRutaDeDesigner(APath) and IsBinaryDesignerBytes(B) then
      Exit(MsgFmt(SR_EDIT_BINARIO_FIRMA_TPF0_ENVOLTORIO_FMT, [TPath.GetFileName(APath), Ext]));
  end;
  // las copias muertas (la papelera, las del IDE, la marca de dueno, los
  // temporales): la segunda barrera, por LA pregunta de la puerta de escribir
  // y con su codigo. EDIT-065 y EDIT-033 eran el mismo hecho con otro, y no se
  // alcanzaban: la jaula va antes, tambien en una tanda (A10 de la 1.23, medido)
  Result := DeadCopyWriteDenied(APath);
end;

procedure SignificadoDeOldNew(const AOld, ANew: string; out AHasOld, AHasNew: Boolean);
begin
  AHasOld := AOld <> '';
  AHasNew := (ANew <> '') or AHasOld;
end;

function DeleteDeLineaDenegado(AHasOld: Boolean; const AOld, ANew: string; AAtLine: Integer): string;
begin
  Result := '';
  // sin old, solo una linea EN BLANCO por su numero (P3-L9, DoEdit)
  if (not AHasOld or (AOld = '')) and (AAtLine <= 0) then
    Exit(MsgText(SR_EDIT_DELETE_TRUE_NECESITA_OLD));
  if ANew <> '' then
    Exit(MsgText(SR_EDIT_DELETE_TRUE_LLEVA_NEW));
end;

function OtroModoConFragmento(AHasOld: Boolean; const AOldLine: string; ADelete: Boolean;
  AToLine: Integer; const AModosPropios: string): string;
begin
  if AHasOld and (AOldLine <> '') then Result := 'old'
  else if ADelete then Result := 'delete'
  else if AToLine > 0 then Result := 'toline'
  else Result := AModosPropios;
end;

function ExecutePatch(const A: TPatchArgs): string;
var
  Ext: string;
  IsDesigner: Boolean;
  B: TBytes;
  K: TEncKind;
  Text: string;
  Lines, CodeLines: TArray<string>;
  I: Integer;
begin
  GLock.Enter;
  try
    try
      Result := WriteTargetDenied(A.Path); // jaula + carpetas muertas, UNA puerta
      if Result <> '' then
        Exit;
      // Las carpetas muertas (la papelera __delphi-patch, los temporales
      // __delphi-temp, el __history del IDE) no se editan. Su gemela
      // delphi_textedit lo comprobaba desde el principio y esta puerta no:
      // editar dentro de __delphi-temp dejaba el trabajo -y su copia- justo
      // donde la purga del arranque lo borra sin avisar (auditoria
      // 2026-09-21: la regla entro en 1 de los 3 guardianes y delphi_edit
      // era el que faltaba).
      // -> ahora dentro de WriteTargetDenied, arriba (25-sep-2026).
      // lo que delphi_edit edita: UNA puerta, la misma de la tanda
      Result := FicheroQueNoEditaDelphiEdit(A.Path);
      if Result <> '' then
        Exit;
      Ext := LowerCase(TPath.GetExtension(A.Path));
      IsDesigner := EsRutaDeDesigner(A.Path);

      // MODO FRAGMENTO: se resuelve a un ancla de linea completa y sigue
      // por el motor de siempre (ver FragmentoALinea).
      if A.Fragment <> '' then
      begin
        // lo que choca con fragment, por LA escalera (OtroModoConFragmento);
        // los modos propios de delphi_edit, decididos aqui
        var Propios := '';
        if A.CreateUnit_ then Propios := 'createunit'
        else if A.Restore then Propios := 'restore'
        else if A.Insert <> '' then Propios := 'insert';
        var Otros := OtroModoConFragmento(A.HasOld, A.OldLine, A.DeleteLine, A.ToLine, Propios);
        var LineaVieja, LineaNueva: string;
        Result := FragmentoALinea(A.Path, A.Fragment, A.NewText, A.AtLine,
          Otros, LineaVieja, LineaNueva);
        if Result <> '' then
          Exit;
        Exit(DoEdit(A.Path, LineaVieja, LineaNueva, A.AtLine, IsDesigner,
          False, 0));
      end;

      // "toline" solo significa algo con un ancla: en los modos que no van
      // por lineas se rechaza en vez de tragarselo en silencio.
      if A.ToLine > 0 then
      begin
        if A.CreateUnit_ then
          Exit(MsgFmt(SR_RANGE_WRONG_MODE_FMT, ['createunit']));
        if A.Restore then
          Exit(MsgFmt(SR_RANGE_WRONG_MODE_FMT, ['restore']));
        if A.Insert <> '' then
          Exit(MsgFmt(SR_RANGE_WRONG_MODE_FMT, ['insert=' + A.Insert]));
      end;

      // ---------- CREATE UNIT ----------
      if A.CreateUnit_ then
      begin
        if Ext <> '.pas' then
          Exit(MsgText(SR_EDIT_CREATEUNIT_SOLO_CREA_UNITS));
        var MalEol := EolDesconocido(A.Eol);
        if MalEol <> '' then
          Exit(MalEol);
        if TFile.Exists(A.Path) then
          Exit(MsgFmt(SR_EDIT_EXISTE_CREATEUNIT_JAMAS_SOBREESCRIBE_FMT, [TPath.GetFileName(A.Path)]));
        var UnitName := TPath.GetFileNameWithoutExtension(A.Path);
        // Dotted namespaces are legal Delphi and REQUIRED by modern projects
        // (Lsp.BuildRunner, System.SysUtils...): allow Ident(.Ident)*, with
        // EL identificador (Lsp.Pascal): una enye o un acento son legales.
        if not EsIdentificador(UnitName, True) then
          Exit(MsgFmt(SR_EDIT_IDENTIFICADOR_PASCAL_VALIDO_NOMBRE_FMT, [UnitName]));
        // ...y la regla entera de un nombre de unit nuevo (Lsp.Scaffold): una
        // palabra reservada o una unit de la RTL pasaban (revision de paisaje)
        var MalNombre := BadUnitName(UnitName);
        if MalNombre <> '' then
          Exit(MalNombre);
        var Skel: string;
        var Note: string;
        if A.Content <> '' then
        begin
          var MalContenido := ContenidoDeUnitNoValido(UnitName, A.Content);
          if MalContenido <> '' then
            Exit(MalContenido);
          // Whole known content in ONE call (replicating a file you already
          // have beats a create + N anchored patches). EOL normalized to
          // CRLF - the JSON channel often arrives LF-only - and the result
          // is audited below like any other write.
          Skel := ConSalto(A.Content, SaltoPedido(A.Eol));
          if not Skel.EndsWith(#10) then
            Skel := Skel + SaltoPedido(A.Eol);
          Note := MsgText(SF_EDIT_CONTENIDO_APORTADO);
        end
        else
        begin
          Skel := Format('unit %s;'#13#10#13#10'interface'#13#10#13#10 +
            'implementation'#13#10#13#10'end.'#13#10, [UnitName]);
          // eol=lf tambien sin content: decia "LF" y escribia CRLF
          // (verificacion de la tercera ronda)
          Skel := ConSalto(Skel, SaltoPedido(A.Eol));
          Note := MsgText(SF_EDIT_ESQUELETO_ESTANDAR_IDE);
        end;
        CrearCarpeta(TPath.GetDirectoryName(TPath.GetFullPath(A.Path)));
        // New files honour the encoding the IDE is configured to use
        // (NewFileEncName, la regla de todos: aqui habia otra copia), y si
        // esa es la ANSI y el contenido no cabe, UTF-8 con BOM, como el IDE
        // al guardar (EncAlEscribir; 4.1 de la 1.18.0)
        var NewK := EncAlEscribir(A.Path, EncKindOf(EncDeFicheroNuevo(A.Path)), nil, False, Skel);
        var CreadoBytes: TArray<Byte> := nil;
        try
          CreadoBytes := EncodeText(Skel, NewK);
        except
          on E: Exception do
            Exit(MsgEnvuelve(SR_EDIT_AL_CODIFICAR_CONTENIDO_FMT, E.Message));
        end;
        // ...y lo que se escribe tiene que leerse igual (EDIT-122)
        var Cambia := LecturaCambiada(A.Path, CreadoBytes, NewK);
        if Cambia <> '' then
          Exit(Cambia);
        // escribir es otra cosa que codificar: una ruta demasiado larga salia
        // como "no se pudo codificar" (quinta revision)
        try
          AtomicWrite(A.Path, CreadoBytes);
        except
          on E: Exception do
            Exit(MsgEnvuelve(SR_EDIT_NO_SE_ESCRIBIO_FMT, E.Message, [A.Path, E.Message]));
        end;
        var NotaCreada: string;
        var CM := Measure(RelecturaDe(A.Path, CreadoBytes, NotaCreada));
        Exit(ConAvisosDeLlaves(MsgFmt(SK_EDIT_CREADA_UNIT_FMT,
          [TPath.GetFileName(A.Path), UnitName, Note, EncName(NewK),
           NombreDelSalto(SaltoPedido(A.Eol)), Auditoria(CM)]) +
          IfThen(NotaCreada <> '', #10 + NotaCreada, '') + NotaDeNombreTapado(UnitName), A.Path, Skel));
      end;

      if not TFile.Exists(A.Path) then
        Exit(NoEsFichero(A.Path, MsgFmt(SR_PATCH_EDITS_NOFILE_FMT, [A.Path])));

      B := TFile.ReadAllBytes(A.Path);
      // (un designer binario ya lo nego la puerta, FicheroQueNoEditaDelphiEdit)

      // (un BOM de UTF-8 con el cuerpo roto se negaba AQUI, EDIT-038, solo para
      // delphi_edit y tambien para restaurarlo; ahora lo pregunta cada
      // escritor - BytesVuelvenIgual - y restore, que copia bytes, lo cura)
      K := DetectEnc(B, IsDesigner);
      Text := DecodeBytes(B, K);

      // ---------- RESTORE (2 steps) ----------
      if A.Restore then
      begin
        var DirBk := CarpetaDePapelera(A.Path);
        var Src := '';
        if TDirectory.Exists(DirBk) then
        begin
          var Days := TDirectory.GetDirectories(DirBk);
          TArray.Sort<string>(Days);
          for I := High(Days) downto 0 do
          begin
            var Cand := TPath.Combine(Days[I], TPath.GetFileName(A.Path));
            if EsCarpetaDeDia(TPath.GetFileName(Days[I])) and TFile.Exists(Cand) then
            begin
              Src := Cand;
              Break;
            end;
          end;
        end;
        if Src = '' then
          Exit(MsgFmt(SR_EDIT_HAY_COPIA_SOLO_PUEDO_FMT,
            [TPath.GetFileName(A.Path), TrashFolderName]));

        // la copia se LEE por la puerta de leer, y la de antes de restaurar se
        // ESCRIBE por la de escribir, como en BackupFile: un __delphi-patch que
        // fuera un enlace no lleva ni una ni otra fuera (tercera revision)
        var VetoCopia := ReadPathDenied(Src);
        if VetoCopia <> '' then
          Exit(VetoCopia);
        var BkBytes := TFile.ReadAllBytes(Src);
        var NowLines := SplitToLines(Text);
        var BkSet := TDictionary<string, Boolean>.Create;
        var Losses := TStringList.Create;
        try
          for var L in SplitToLines(DecodeBytes(BkBytes, DetectEnc(BkBytes, EsRutaDeDesigner(A.Path)))) do
            BkSet.AddOrSetValue(L, True);
          for I := 0 to High(NowLines) do
            if (NowLines[I].Trim <> '') and not BkSet.ContainsKey(NowLines[I]) then
              Losses.Add('  ' + CitaDeLinea(I + 1, NowLines[I]));

          if not A.Confirm then
          begin
            var Lista: string;
            if Losses.Count = 0 then
              Lista := MsgText(SF_EDIT_NINGUNA_YA_EN_COPIA)
            else
            begin
              var Top := Losses.Count;
              if Top > 25 then Top := 25;
              var SbL := TStringBuilder.Create;
              try
                for I := 0 to Top - 1 do SbL.AppendLine(Losses[I]);
                if Losses.Count > 25 then SbL.Append(MsgFmt(SF_EDIT_Y_MAS_FMT, [Losses.Count - 25]));
                Lista := SbL.ToString.TrimRight;
              finally
                SbL.Free;
              end;
            end;
            // "desde %s" sale al agente y delphi_edit esta EXENTA del filtro de
            // salida: la mascara va A MANO aqui y en el RESTAURADO de abajo,
            // como en BackupFile (la obligacion de la lista, ver Lsp.Mascara).
            // La copia es la PRIMERA del dia de ese fichero y no sabe de quien
            // es: si otro agente lo edito despues, restaurar se lleva TAMBIEN
            // su trabajo. Decision de David (24-sep-2026): no se hace una copia
            // por agente; se dice la hora de la copia y se avisa de los demas.
            // Deshacer con precision es cosa de git (delphi_git).
            // Hora de CREACION de la copia: la de modificacion la hereda del
            // original (TFile.Copy) y puede ser de dias antes.
            var Sello := TFile.GetCreationTime(Src);
            Exit(MsgFmt(SN_EDIT_RESTAURAR_NADA_HECHO_FMT,
              [TPath.GetFileName(A.Path), MaskDriveText('', Src),
               FormatDateTime('yyyy-mm-dd hh:nn', Sello), EdadLegible(Now - Sello),
               Losses.Count, Lista]));
          end;

          // Antes se componia aqui a mano, con OTRA forma de sello
          // (".antes-restaurar-hhnnss"), y por eso el lector de la papelera no
          // la reconocia: ni salia en delphi_list includetrash ni se podia
          // restaurar como es debido. Ahora el sello lo pone el nombrador y
          // lo que distingue a esta copia es su CAJON, no su nombre.
          // Y el hueco que dejaba: esta copia la hace ahora el mismo helper que
          // todo lo que pisa un fichero entero (GuardaContenidoActual).
          var PreCopy: string;
          try
            PreCopy := GuardaContenidoActual(A.Path, CAJON_ANTES_DE_RESTAURAR);
          except
            on E: Exception do
              if EsFallo(E.Message) then
                Exit(E.Message) // la negativa de la puerta, tal cual
              else
                raise;
          end;
          AtomicWrite(A.Path, BkBytes);
          var NotaRest: string;
          var Releido := RelecturaDe(A.Path, BkBytes, NotaRest);
          Exit(MsgFmt(SK_EDIT_RESTAURADO_DESDE_FMT,
            [TPath.GetFileName(A.Path), MaskDriveText('', Src), Auditoria(Measure(Releido)),
             Losses.Count, MaskDriveText('', PreCopy)]) + IfThen(NotaRest <> '', #10 + NotaRest, ''));
        finally
          BkSet.Free;
          Losses.Free;
        end;
      end;

      // ---------- SEMANTIC INSERT ----------
      if A.Insert <> '' then
      begin
        if IsDesigner then
          Exit(MsgText(SR_EDIT_INSERT_SOLO_FUENTES_PASCAL));
        if (A.Insert <> 'rutina-global') and (A.Insert <> 'metodo') then
          Exit(MsgText(SR_EDIT_INSERT_DEBE_SER_RUTINA));
        if A.Code.Trim = '' then
          Exit(MsgText(SR_EDIT_MODO_INSERT_NECESITA_CODE));
        if Length(EndsConPunto(CodigoPascal(A.Code))) > 0 then
          Exit(MsgText(SR_EDIT_BLOQUE_TRAE_END_SOLO));

        CodeLines := SplitToLines(A.Code.TrimRight);
        // EL lexico (Lsp.Pascal): lo que se busca en el bloque se busca en su
        // vista de CODIGO, linea a linea con CodeLines (mismo largo, mismos
        // saltos). Cada lectura llevaba su trozo de la regla: el // de
        // 'http://x' cortaba la firma y la daba por no cerrada, y un parentesis
        // dentro de un comentario descuadraba la cuenta (EDIT-071 falso, sonda
        // del lexico, 2-oct-2026)
        var CodeVista := SplitToLines(CodigoPascal(A.Code.TrimRight));
        var LastLine := '';
        var NoComment := '';
        for I := High(CodeLines) downto 0 do
          if CodeVista[I].Trim <> '' then
          begin
            LastLine := CodeLines[I].Trim;
            NoComment := CodeVista[I].Trim;
            Break;
          end;
        if not TRegEx.IsMatch(NoComment, PATRON_NO_IDENT_ANTES + 'end\s*;$', [roIgnoreCase]) then
        begin
          if TRegEx.IsMatch(NoComment, PATRON_NO_IDENT_ANTES + 'end$', [roIgnoreCase]) then
            Exit(MsgText(SR_EDIT_BLOQUE_TERMINA_END_SIN));
          Exit(MsgFmt(SR_EDIT_ULTIMA_LINEA_BLOQUE_RUTINA_FMT,
            [Copy(LastLine, 1, 80)]));
        end;
        // UNA rutina por INSERT: con dos, la primera se declaraba (o se
        // cualificaba) y la segunda entraba tal cual - una global sin declarar
        // en un insert=metodo, fuera del interface con visible=true - y la
        // respuesta decia "las DOS mitades" (Hermes, validacion de la 1.21.1;
        // medido en produccion). Las cuenta EL lector (Lsp.PascalDecl): las
        // anidadas van dentro de la suya
        var RutinasDelCode := RutinasDeUnBloque(A.Code);
        if Length(RutinasDelCode) > 1 then
          Exit(MsgFmt(SR_EDIT_INSERT_UNA_RUTINA_FMT,
            [Length(RutinasDelCode), string.Join(', ', RutinasDelCode)]));

        // La firma puede ocupar VARIAS lineas y venir precedida de un
        // comentario de documentacion (el estilo de la casa lo hace). Se busca
        // la primera linea que ES una firma - saltando blancos y comentarios -
        // y se sigue hasta el ';' que la CIERRA a profundidad de parentesis 0:
        // dentro de los parentesis el ';' solo separa grupos de parametros.
        // Medido en campo (18-sep): quedarse con la primera linea escribia la
        // declaracion TRUNCADA en la clase y, como esa linea acaba en ';', la
        // comprobacion de cierre la daba por buena - E2029 y cascada de
        // "identificador no declarado" lejos del sitio real, con el informe
        // diciendo "las DOS mitades".
        var IFirmaIni := -1;
        for I := 0 to High(CodeVista) do
          if CodeVista[I].Trim <> '' then
          begin
            IFirmaIni := I;
            Break;
          end;
        // Los ATRIBUTOS ([Test], [TestCase('a', '1,2')]) van delante de la
        // firma, en su linea o en la misma; se dejan en la suya para que la
        // firma empiece donde empieza. En un metodo van con la DECLARACION:
        // medido (sonda, 3-oct-2026), en la implementacion compilan sin aviso
        // y la RTTI no los ve - un [Test] alli es un test que DUnitX no corre.
        // El bloque entero se rechazaba (EDIT-070, visto en la VM 13.2).
        var IAtrIni := IFirmaIni;
        if (IFirmaIni >= 0) and CodeVista[IFirmaIni].TrimLeft.StartsWith('[') then
        begin
          var LA := IFirmaIni;
          var CA := 1;
          var ProfCor := 0;
          var Empieza := False;
          while (LA <= High(CodeVista)) and not Empieza and (ProfCor >= 0) do
          begin
            while CA <= Length(CodeVista[LA]) do
            begin
              var Ch := CodeVista[LA][CA];
              if Ch = '[' then
                Inc(ProfCor)
              else if Ch = ']' then
                Dec(ProfCor)
              else if (ProfCor = 0) and not CharInSet(Ch, [' ', #9]) then
              begin
                Empieza := True;
                Break;
              end;
              if ProfCor < 0 then
                Break;
              Inc(CA);
            end;
            if not Empieza then
            begin
              Inc(LA);
              CA := 1;
            end;
          end;
          // sin firma detras (solo atributos, o un corchete que no cierra): la
          // primera linea util sigue siendo el atributo, y EDIT-070 lo dice
          if Empieza then
          begin
            if Copy(CodeVista[LA], 1, CA - 1).Trim <> '' then
            begin
              // [Test] procedure X; -> el atributo en su linea, la firma en la suya
              Insert(Copy(CodeLines[LA], CA, MaxInt), CodeLines, LA + 1);
              Insert(Copy(CodeVista[LA], CA, MaxInt), CodeVista, LA + 1);
              CodeLines[LA] := Copy(CodeLines[LA], 1, CA - 1).TrimRight;
              CodeVista[LA] := Copy(CodeVista[LA], 1, CA - 1).TrimRight;
              Inc(LA);
            end;
            IFirmaIni := LA;
          end;
        end;
        var AtribLineas := TArray<string>.Create();
        for I := IAtrIni to IFirmaIni - 1 do
          if CodeVista[I].Trim <> '' then
            AtribLineas := AtribLineas + [CodeLines[I].Trim];
        var Firma := '';
        var FirmaCodigo := '';
        if IFirmaIni >= 0 then
        begin
          Firma := CodeLines[IFirmaIni].Trim;
          FirmaCodigo := CodeVista[IFirmaIni].Trim;
        end;
        // 'class procedure/function/constructor/destructor': un metodo de
        // clase (se rechazaba con EDIT-070, como si no fuera una firma). El
        // nombre es EL identificador (Lsp.Pascal): con [A-Za-z_]\w* el de un
        // 'procedure Anadir...' escrito con su enye era 'A', y las dos miradas
        // de "ya existe" buscaban una rutina A (censo del 4-oct-2026)
        var MF := TRegEx.Match(FirmaCodigo,
          '^(class\s+)?(' + PatronPalabraDeRutina + ')\s+(' + PATRON_IDENT + ')\s*([.(;:])?', [roIgnoreCase]);
        if not MF.Success then
          Exit(MsgFmt(SR_EDIT_BLOQUE_NO_EMPIEZA_FIRMA_FMT, [Copy(Firma, 1, 80)]));
        if (MF.Groups[1].Value <> '') and (A.Insert = 'rutina-global') then
          Exit(MsgFmt(SR_EDIT_RUTINA_GLOBAL_DE_CLASE_FMT, [MF.Groups[2].Value.ToLower]));
        if GrupoDe(MF, 4) = '.' then // un grupo opcional (Lsp.Regex)
          Exit(MsgText(SR_EDIT_FIRMA_VIENE_CUALIFICADA_CLASE));
        var IFirmaFin := IFirmaIni;
        var PosCierre := 0;
        var FirmaCerrada := False;
        var ProfPar := 0;
        for I := IFirmaIni to High(CodeLines) do
        begin
          var Ln := CodeVista[I]; // sin cadenas ni comentarios: lo que queda cuenta
          var Col := 0;
          for var Ch in Ln do
          begin
            Inc(Col);
            if Ch = '(' then
              Inc(ProfPar)
            else if Ch = ')' then
              Dec(ProfPar)
            else if (Ch = ';') and (ProfPar <= 0) then
            begin
              FirmaCerrada := True;
              PosCierre := Col;
            end;
            if FirmaCerrada then
              Break;
          end;
          IFirmaFin := I;
          if FirmaCerrada then
            Break;
        end;
        if not FirmaCerrada then
          Exit(MsgFmt(SR_EDIT_FIRMA_NO_CIERRA_FMT, [Copy(Firma, 1, 80)]));
        var FirmaLineas := TArray<string>.Create();
        for I := IFirmaIni to IFirmaFin do
          if I = IFirmaFin then
            FirmaLineas := FirmaLineas + [Copy(CodeLines[I], 1, PosCierre).Trim]
          else
            FirmaLineas := FirmaLineas + [CodeLines[I].Trim];
        // Las DIRECTIVAS detras de la firma (virtual; override; overload;
        // stdcall; static; deprecated 'x'; message WM_X;...). Medido (sonda,
        // 3-oct-2026): en un metodo van SOLO en la declaracion - la
        // implementacion sin ninguna compila, y con 'virtual' es E2070 -; en
        // una rutina global, en las DOS mitades (sin ellas en el interface,
        // E2037). La firma se cortaba en su primer ';': la declaracion salia
        // sin ellas, la implementacion con ellas, y la respuesta decia "las
        // dos mitades".
        var IDirFin := IFirmaFin;
        var PosDirFin := PosCierre;
        var Directivas := '';
        var LD := IFirmaFin;
        var CD := PosCierre + 1;
        while True do
        begin
          // lo siguiente que no es blanco, tambien en las lineas de abajo
          while (LD <= High(CodeVista)) and
                ((CD > Length(CodeVista[LD])) or CharInSet(CodeVista[LD][CD], [' ', #9])) do
            if CD > Length(CodeVista[LD]) then
            begin
              Inc(LD);
              CD := 1;
            end
            else
              Inc(CD);
          if LD > High(CodeVista) then
            Break;
          var MD := TRegEx.Match(Copy(CodeVista[LD], CD, MaxInt), '^' + PATRON_IDENT);
          if not MD.Success or not MatchText(MD.Value, DIRECTIVAS_DE_RUTINA) then
            Break;
          // la directiva llega hasta su ';' (a profundidad de parentesis 0)
          var LFin := LD;
          var CFin := CD;
          var ProfD := 0;
          var Cierra := False;
          while (LFin <= High(CodeVista)) and not Cierra do
          begin
            while CFin <= Length(CodeVista[LFin]) do
            begin
              if CodeVista[LFin][CFin] = '(' then
                Inc(ProfD)
              else if CodeVista[LFin][CFin] = ')' then
                Dec(ProfD)
              else if (CodeVista[LFin][CFin] = ';') and (ProfD <= 0) then
              begin
                Cierra := True;
                Break;
              end;
              Inc(CFin);
            end;
            if not Cierra then
            begin
              Inc(LFin);
              CFin := 1;
            end;
          end;
          if not Cierra then
            Break;
          // su texto ORIGINAL: la cadena de un deprecated 'x' vive ahi
          for var KD := LD to LFin do
          begin
            var Desde := 1;
            if KD = LD then
              Desde := CD;
            var Hasta := Length(CodeLines[KD]);
            if KD = LFin then
              Hasta := CFin;
            Directivas := (Directivas + ' ' + Copy(CodeLines[KD], Desde, Hasta - Desde + 1).Trim).Trim;
          end;
          IDirFin := LFin;
          PosDirFin := CFin;
          LD := LFin;
          CD := CFin + 1;
        end;

        Lines := SplitToLines(Text);
        // la estructura del fichero (uses, cabecera, frontera, la clase, sus
        // secciones, lo que ya esta) se BUSCA en la vista del codigo, alineada
        // con Lines, y se ANCLA en Lines: un 'uses ...;' dentro de un
        // comentario recibia la rutina (INSERT en un .dpr, escrito DENTRO del
        // comentario y contestado como hecho) y un end. comentado negaba la
        // frontera (EDIT-049; sonda del lexico, 2-oct-2026)
        var VistaTexto := CodigoPascal(Text);
        var Codigo := SplitToLines(VistaTexto);

        // A program/library (.dpr) has no interface/implementation: a routine
        // is legal only BETWEEN the uses clause and the main begin..end.
        // Measured in the field (round 2, B3): inserting before 'end.' left
        // the .dpr uncompilable (E2070 + 2xE2029) - the post-write audit sees
        // structure, not grammar, so the placement must be right by design.
        if Ext = '.dpr' then
        begin
          if A.Insert = 'metodo' then
            Exit(MsgText(SR_EDIT_INSERT_METODO_APLICA_DPR));
          var IUses := -1;
          var IAfter := -1;
          for I := 0 to High(Lines) do
            if TRegEx.IsMatch(Codigo[I], '^[ \t]*uses\b', [roIgnoreCase]) then
            begin
              IUses := I;
              Break;
            end;
          if IUses >= 0 then
          begin
            for I := IUses to High(Lines) do
              if Codigo[I].TrimRight.EndsWith(';') then
              begin
                IAfter := I;
                Break;
              end;
          end
          else
          begin
            // detras de la CABECERA, por EL lector (Lsp.Pascal): la queria en
            // una sola linea que acabase en ';' (inventario del 10-oct-2026)
            var Cab: TCabeceraFuente;
            if CabeceraDeFuente(VistaTexto, Cab) and MatchText(Cab.Palabra, ['program', 'library']) then
            begin
              IAfter := LineaDePosicion(VistaTexto, Cab.Fin - 1) - 1;
              // y la linea de su ';' acaba en ';': en un 'program P; begin
              // end.' la rutina caeria detras del end. (se negaba y se niega)
              if not Codigo[IAfter].TrimRight.EndsWith(';') then
                IAfter := -1;
            end;
          end;
          if IAfter = -1 then
            Exit(MsgText(SR_EDIT_ENCUENTRO_FINAL_CABECERA_USES));
          // detras de donde ACABA esa linea: un comentario que se abre en ella
          // y cierra mas abajo se llevaba la rutina DENTRO, contestada como
          // colocada (revision de la 1.10.0, medido)
          IAfter := LineaQueCierra(Lines, IAfter);
          var AnclaDpr := Lines[IAfter];
          var RDpr := DoEdit(A.Path, AnclaDpr,
            AnclaDpr + #10#10 + string.Join(#10, CodeLines), IAfter + 1, False);
          // Si el motor se nego (un caracter que no cabe, la jaula), la
          // respuesta ES esa negativa: envuelta en el "colocada en" salia
          // como exito sin haber escrito nada (revision 27-sep-2026, medido)
          if EsFallo(RDpr) then
            Exit(RDpr);
          var NotaVis := '';
          if A.Visible then
            NotaVis := #10 + MsgText(SF_EDIT_VISIBLE_IGNORADO_PROGRAM);
          Exit(MsgFmt(SK_EDIT_INSERT_RUTINA_DPR_FMT,
            [IAfter + 1, AnclaDpr.Trim, RDpr, NotaVis]));
        end;

        // LA frontera: donde acaban las declaraciones del implementation, por
        // EL lector (Lsp.PascalDecl: initialization, el begin del bloque
        // principal o el end final), si lo que la cierra empieza su linea: con
        // codigo delante en ella ('end; end.') la rutina caeria dentro de lo
        // de delante, y se niega. Si es el end, tiene que ser EL end. final
        // (EndsConPunto, y uno solo: dos son ramas de un IFDEF) - un end que el
        // lector no supo leer no es la frontera. Eran una regex de
        // 'initialization' y otra del end.: una unidad con 'begin ... end.'
        // recibia la rutina DENTRO de ese bloque (revisor 8, 10-oct-2026;
        // medido: E2070)
        var FrontIdx := -1;
        var FoundFront := False;
        var UFront := LeeFuentePascal(Text);
        try
          var PosFront := UFront.FinDeclaraciones;
          if PosFront > 0 then
          begin
            var EndsF := EndsConPunto(VistaTexto);
            var EsEnd := SameText(Copy(VistaTexto, PosFront, 3), 'end');
            FrontIdx := LineaDePosicion(VistaTexto, PosFront) - 1;
            var Atras := PosFront - 1;
            while (Atras >= 1) and not CharInSet(VistaTexto[Atras], [#10, #13]) and (VistaTexto[Atras] <= ' ') do
              Dec(Atras);
            // ...y los 'end.' de DETRAS del final solo cuentan si una directiva
            // puede hacerlos finales (ramas de un IFDEF): dcc no lee nada tras
            // el end. final, y una prosa que decia "end." otra vez negaba el
            // insert (B1 rev8 de la 1.18.2). La directiva, por EL clasificador
            // (ClasesPascal), no por una busqueda de '{$'
            var SoloSuEnd := (Length(EndsF) >= 1) and (EndsF[0].Ini = PosFront);
            if SoloSuEnd and (Length(EndsF) > 1) then
            begin
              var Clases := ClasesPascal(Text);
              for var PosD := PosFront to Length(Text) do
                if Clases[PosD] = cpDirectiva then
                begin
                  SoloSuEnd := False;
                  Break;
                end;
            end;
            FoundFront := ((Atras < 1) or CharInSet(VistaTexto[Atras], [#10, #13])) and
              (not EsEnd or SoloSuEnd);
            // ...y FUERA de todo condicional: una frontera dentro de un {$IFDEF}
            // (un initialization solo de DEBUG) metia la rutina DENTRO del
            // bloque - sin el simbolo, E2065 o una rutina que no existe - y se
            // contestaba que estaba en su sitio (W1 del revisor de cierre de la
            // 1.18.2, medido). Delante del condicional abierto mas externo, si
            // empieza su linea; si no, se niega como cualquier frontera rara
            if FoundFront then
            begin
              var PosIf := PrimerCondicionalAbierto(Copy(Text, 1, PosFront - 1));
              if PosIf > 0 then
              begin
                var AtrasIf := PosIf - 1;
                while (AtrasIf >= 1) and not CharInSet(Text[AtrasIf], [#10, #13]) and (Text[AtrasIf] <= ' ') do
                  Dec(AtrasIf);
                FoundFront := (AtrasIf < 1) or CharInSet(Text[AtrasIf], [#10, #13]);
                FrontIdx := LineaDePosicion(Text, PosIf) - 1;
              end;
            end;
          end;
        finally
          UFront.Free;
        end;
        if not FoundFront then
          Exit(MsgText(SR_EDIT_ENCUENTRO_FRONTERA_FINAL_UNIT));
        var FrontLine := Lines[FrontIdx];

        if A.Insert = 'rutina-global' then
        begin
          // visible=true son DOS escrituras (el cuerpo y la declaracion): si la
          // segunda no se puede, la primera se deshace; salia exito con una
          // nota y la rutina privada (verificacion de la tercera ronda)
          // una rutina con ese nombre que YA esta (global, o la declaracion de
          // un metodo) se AVISA, no se niega: dcc dira si es la misma, y no
          // somos la ninera (David, 23-sep). Se insertaba a ciegas (decima)
          var YaEsta := '';
          var RutinaRe := TRegEx.Create('^\s*' + PatronInicioDeRutina + '\s+' +
            TRegEx.Escape(MF.Groups[3].Value) + '\s*[(;:]', [roIgnoreCase]);
          for I := 0 to High(Codigo) do
            if RutinaRe.IsMatch(Codigo[I]) then
            begin
              YaEsta := #10 + MsgFmt(SN_EDIT_RUTINA_YA_EXISTE_FMT, [MF.Groups[3].Value, I + 1]);
              Break;
            end;
          var FotoVis: TFotoDeFicheros;
          if A.Visible then
            FotoVis.Toma([A.Path]);
          var R := DoEdit(A.Path, FrontLine,
            string.Join(#10, CodeLines) + #10#10 + FrontLine, FrontIdx + 1, False);
          if EsFallo(R) then
            Exit(R);
          var Extra := YaEsta;
          if A.Visible and EsMsg(R, SK_EDIT_ESCRITO_EN_FMT) then
          begin
            FotoVis.Anota(A.Path);
            // La segunda escritura puede LANZAR (otro proceso coge el fichero
            // tras la primera): sin este try el cuerpo quedaba escrito y la
            // declaracion no, contestando "cierralo y repite" - y repetir
            // duplicaba la rutina (quinta revision, medido 12 de 12)
            var FalloTexto := '';
            var FalloCausa := '';
            try
              FotoVis.Vigila(A.Path);
              var ImpIdx: Integer;
              if FindUniqueLine(SplitToLines(CodigoPascal(DecodeBytes(TFile.ReadAllBytes(A.Path), K))),
                function(L: string): Boolean
                begin
                  Result := L.Trim.ToLower = 'implementation';
                end, ImpIdx) then
              begin
                var Decl := string.Join(#10, FirmaLineas);
                if not Decl.EndsWith(';') then Decl := Decl + ';';
                if Directivas <> '' then
                  Decl := Decl + ' ' + Directivas;
                // la declaracion, con el juicio del form aplazado: ya lo dijo
                // el cuerpo, y una rutina en el interface no toca el enlace
                // (W7 del revisor de cierre: DSGN-021 dos veces)
                var R2: string;
                AplazaJuicioDeForm(True);
                try
                  R2 := DoEdit(A.Path, 'implementation', Decl + #10#10 + 'implementation', ImpIdx + 1, False);
                finally
                  AplazaJuicioDeForm(False);
                end;
                if EsMsg(R2, SK_EDIT_ESCRITO_EN_FMT) then
                  Extra := #10 + MsgFmt(SF_EDIT_VISIBLE_DECLARACION_ANADIDA_FMT, [Decl]) + #10 + R2
                else
                begin
                  FalloCausa := R2;
                  FalloTexto := MsgText(SF_EDIT_VISIBLE_NO_PUDE_ANADIR) + #10 + R2;
                end;
              end
              else
                FalloTexto := MsgText(SF_EDIT_VISIBLE_NO_ENCUENTRO_IMPLEMENTATION);
            except
              on E: Exception do
              begin
                FalloCausa := MsgExcepcion(E.ClassName, E.Message);
                FalloTexto := FalloCausa;
              end;
            end;
            if FalloTexto <> '' then
            begin
              var NoVolvio := FotoVis.Restaura;
              if NoVolvio <> '' then
                Exit(MsgFmt(SR_FOTO_NO_VOLVIO_FMT, [NoVolvio, FalloTexto]));
              Exit(MsgConCausa(SR_EDIT_VISIBLE_DESHECHO_FMT, FalloCausa, [FalloTexto]));
            end;
          end;
          Exit(MsgFmt(SK_EDIT_INSERT_RUTINA_ANTES_FMT,
            [FrontIdx + 1, FrontLine.Trim, R, Extra]));
        end;

        // insert = 'metodo'
        if A.ClassName_.Trim = '' then
          Exit(MsgText(SR_EDIT_INSERT_METODO_NECESITA_INCLASS));
        // LA clase, de EL lector de clases (Lsp.PascalDecl): la declarada,
        // con la linea de su nombre, la de su 'end', sus secciones y sus
        // rutinas - las SUYAS, no las de un tipo anidado. Leida por lineas, la
        // primera 'TFoo = class' era una declaracion adelantada, y la de una
        // sin cuerpo ('EMio = class(Exception);') o la de una linea tomaban el
        // 'end;' de la clase siguiente: la declaracion caia dentro de un
        // metodo de otra (E2070); el 'public' de un tipo anidado era el de la
        // clase, y el metodo caia en el anidado (medido el 4-oct-2026)
        var IClase := -1;
        var IFin := -1;
        var SinCuerpo := False;
        var Secciones: TArray<TSeccionPas> := [];
        var RutinasClase: TArray<TMiembroPas> := [];
        // con su contenedor si va anidada y los parametros genericos de cada
        // nivel (TCaja<T>.Foo): sin ellos se escribia TCaja.Foo, que no
        // compila, y la implementacion que ya estaba no se veia (revision de
        // la 1.13.0). Un class helper tambien lleva metodos
        var ClaseCompleta := A.ClassName_;
        var PatronClase := '';
        var Unidad := LeeFuentePascal(Text);
        try
          var Clase := Unidad.Clase(A.ClassName_, [ctClase, ctAyudante]);
          if Clase <> nil then
          begin
            IClase := Clase.Linea;
            IFin := Clase.LineaFin;
            SinCuerpo := Clase.SinCuerpo;
            Secciones := Clase.Secciones;
            RutinasClase := Clase.Rutinas;
            ClaseCompleta := Unidad.NombreDeImplementacion(Clase);
            PatronClase := Unidad.PatronDeImplementacion(Clase);
          end;
        finally
          Unidad.Free;
        end;
        if IClase = -1 then
          Exit(MsgFmt(SR_EDIT_ENCUENTRO_CLASS_FMT, [A.ClassName_, TPath.GetFileName(A.Path)]));
        if SinCuerpo then
          Exit(MsgFmt(SR_EDIT_CLASE_SIN_CUERPO_FMT, [A.ClassName_, IClase + 1, Lines[IClase].Trim]));
        if IFin = -1 then
          Exit(MsgFmt(SR_EDIT_ENCUENTRO_END_CIERRE_CLASE_FMT, [A.ClassName_]));
        if IFin <= IClase then
          Exit(MsgFmt(SR_EDIT_CLASE_EN_UNA_LINEA_FMT, [A.ClassName_, IClase + 1, Lines[IClase].Trim]));

        // COLISION (campo, hermes 17-sep): la firma de un metodo vive DOS
        // veces (interface + implementation) y la tool escribia las dos a
        // ciegas - si la clase YA declaraba el metodo, la segunda declaracion
        // es E2254/E2537 seguro. Se mira cada mitad por separado y solo se
        // escribe la que falta; entero = rechazo con el camino.
        // La declaracion, entre las rutinas de LA clase (las de un tipo
        // anidado no son suyas: con una linea por rutina de su rango, un
        // metodo del mismo nombre en la anidada "ya estaba"); la
        // implementacion, cualificada con su nombre completo
        var Nombre := MF.Groups[3].Value;
        var IDeclExiste := -1;
        for var R in RutinasClase do
          if MismoIdentificador(R.Nombre, Nombre) then
          begin
            IDeclExiste := R.Linea;
            Break;
          end;
        var ImplRe := TRegEx.Create('^\s*' + PatronInicioDeRutina + '\s+' +
          PatronClase + '\.' + TRegEx.Escape(Nombre) + '\s*[(;:]', [roIgnoreCase]);
        var IImplExiste := -1;
        for I := 0 to High(Codigo) do
          if ImplRe.IsMatch(Codigo[I]) then
          begin
            IImplExiste := I;
            Break;
          end;
        if (IDeclExiste >= 0) and (IImplExiste >= 0) then
          Exit(MsgFmt(SR_EDIT_EXISTE_ENTERO_DECLARACION_LINEA_FMT,
            [A.ClassName_, Nombre, IDeclExiste + 1, IImplExiste + 1]));
        if IImplExiste >= 0 then
          Exit(MsgFmt(SR_EDIT_EXISTE_IMPLEMENTACION_LINEA_PERO_FMT,
            [A.ClassName_, Nombre, IImplExiste + 1]));

        // Dos escrituras (la declaracion y la implementacion): todo o nada.
        // Si la segunda falla o LANZA, la primera se deshace; quedaba "a
        // medias" y, por la excepcion, ni eso se decia (quinta revision)
        // lo que el bloque traia para la declaracion (atributos, directivas)
        // no se pierde en silencio cuando la declaracion ya estaba
        var NotaCabecera := '';
        if (IDeclExiste >= 0) and ((Length(AtribLineas) > 0) or (Directivas <> '')) then
          NotaCabecera := #10 + MsgFmt(SN_EDIT_CABECERA_NO_ANADIDA_FMT,
            [(string.Join(' ', AtribLineas) + ' ' + Directivas).Trim, IDeclExiste + 1]);
        var FotoMet: TFotoDeFicheros;
        FotoMet.Toma([A.Path]);
        var R1 := '';
        var DeclLinea := '';
        var DeclNota := '';
        var NotaPublished := '';
        if IDeclExiste >= 0 then
          DeclNota := MsgFmt(SF_EDIT_CLASE_YA_DECLARABA_FMT,
            [Nombre, IDeclExiste + 1])
        else
        begin
        var IDecl := IFin;
        var Vis := A.Visibility.Trim.ToLower;
        if Vis = 'default' then
          Vis := 'published';
        // Sin visibility, un metodo que el designer pareja YA cablea como
        // evento (OnClick = Nombre) va a published: es lo unico que resuelve
        // el streaming (hermes, 25-sep-2026: cayo en public, build verde,
        // "Invalid property value" al cargar el form en Zorin).
        if Vis = '' then
          for var Dsg in DesignersDeUnidad(A.Path) do
            if DesignerWiresMethodFile(Dsg, Nombre) then
            begin
              Vis := 'published';
              NotaPublished := MsgFmt(SN_PATCH_INSERT_PUBLISHED_BY_EVENT_FMT,
                [TPath.GetFileName(Dsg), Nombre]);
              Break;
            end;
        // las secciones son las de LA clase (Secciones, del lector): su
        // palabra, en orden; la pedida acaba donde empieza la siguiente
        if Vis <> '' then
        begin
          var KVis := -1;
          for var KS := 0 to High(Secciones) do
            if Secciones[KS].Palabra = Vis then
            begin
              KVis := KS;
              Break;
            end;
          if KVis = -1 then
          begin
            // A form class keeps components and event handlers in the
            // IMPLICIT published section right after the class header, with
            // no keyword line. 'published' must land there - the most common
            // VCL case (round 2, C1). But it must go AFTER the last member of
            // that section (after the component fields), never right after the
            // header: a method before a field is E2169 (round 3, C1-bis). The
            // first explicit visibility specifier ends the implicit section.
            if Vis = 'published' then
            begin
              if Length(Secciones) > 0 then
                IDecl := Secciones[0].Linea;
            end
            else
              Exit(MsgFmt(SR_EDIT_CLASE_TIENE_SECCION_OMITE_FMT,
                [A.ClassName_, Vis]));
          end
          else if KVis < High(Secciones) then
            IDecl := Secciones[KVis + 1].Linea;
        end;
        // se escribe detras de la linea IDecl - 1: nunca encima de la cabecera
        // (una palabra de visibilidad en la misma linea que el nombre)
        if IDecl <= IClase then
          IDecl := IClase + 1;
        // la sangria, la del primer miembro (ni una linea en blanco o solo
        // comentario, ni la de una palabra de visibilidad)
        var Sangria := '    ';
        for I := IClase + 1 to IFin - 1 do
        begin
          var TrimL := Codigo[I].Trim;
          var IsSec := False;
          for var S2 in Secciones do
            if S2.Linea = I then
              IsSec := True;
          if (TrimL <> '') and not IsSec then
          begin
            Sangria := LeadingWhite(Lines[I]);
            Break;
          end;
        end;
        for var LAtr in AtribLineas do
          DeclLinea := DeclLinea + Sangria + LAtr + #10;
        DeclLinea := DeclLinea + Sangria + FirmaLineas[0];
        for I := 1 to High(FirmaLineas) do
          DeclLinea := DeclLinea + #10 + Sangria + '  ' + FirmaLineas[I];
        if not DeclLinea.EndsWith(';') then DeclLinea := DeclLinea + ';';
        if Directivas <> '' then
          DeclLinea := DeclLinea + ' ' + Directivas;
        var AnclaDecl := Lines[IDecl - 1];
        // la declaracion se escribe con el juicio del form APLAZADO: lo dice
        // la implementacion, que viene siempre detras (y si falla, esta mitad
        // se deshace); con un form ya roto salia DSGN-021 dos veces (W7 del
        // revisor de cierre)
        AplazaJuicioDeForm(True);
        try
          R1 := DoEdit(A.Path, AnclaDecl, AnclaDecl + #10 + DeclLinea, IDecl, False);
        finally
          AplazaJuicioDeForm(False);
        end;
        if not EsMsg(R1, SK_EDIT_ESCRITO_EN_FMT) then
          Exit(MsgConCausa(SR_EDIT_INSERT_FALLO_MITAD1_FMT, R1, [A.ClassName_, R1]));
        end;
        // la implementacion, sin los atributos ni las directivas: van en la
        // declaracion (medido: alli la RTTI ve el atributo, y una directiva de
        // metodo en la implementacion es E2070)
        var ImplLineas := TArray<string>.Create();
        var IFirmaImpl := 0;
        for I := 0 to High(CodeLines) do
        begin
          if (I >= IAtrIni) and (I < IFirmaIni) and (CodeVista[I].Trim <> '') then
            Continue; // un atributo
          var LnImpl := CodeLines[I];
          if Directivas <> '' then
          begin
            if (I > IFirmaFin) and (I < IDirFin) then
              Continue; // una linea solo de directivas
            if (I = IFirmaFin) and (I = IDirFin) then
              LnImpl := (Copy(LnImpl, 1, PosCierre) + Copy(LnImpl, PosDirFin + 1, MaxInt)).TrimRight
            else if I = IFirmaFin then
              LnImpl := Copy(LnImpl, 1, PosCierre).TrimRight
            else if I = IDirFin then
            begin
              LnImpl := Copy(LnImpl, PosDirFin + 1, MaxInt);
              if LnImpl.Trim = '' then
                Continue;
            end;
          end;
          if I = IFirmaIni then
            IFirmaImpl := Length(ImplLineas);
          ImplLineas := ImplLineas + [LnImpl];
        end;
        // la clase, detras de la palabra de la rutina que da la vista: una
        // firma con su comentario delante en la misma linea se quedaba sin
        // cualificar
        var MQ := TRegEx.Match(CodeVista[IFirmaIni],
          '\b' + PatronPalabraDeRutina + '\s+', [roIgnoreCase]);
        var FirmaCual := ImplLineas[IFirmaImpl];
        if MQ.Success then
          Insert(ClaseCompleta + '.', FirmaCual, MQ.Index + MQ.Length); // TOuter.TInner si va anidada
        FirmaCual := FirmaCual.Trim;
        ImplLineas[IFirmaImpl] := FirmaCual;
        FotoMet.Anota(A.Path);
        // la frontera, en SU linea: la declaracion recien escrita la bajo
        // tantas lineas como tiene. Sin numero, un 'end.' dentro de un
        // comentario hacia el ancla doble y se deshacian las dos mitades
        // (revision de la 1.10.0, medido; la rutina-global ya lo llevaba)
        var LineaFront := FrontIdx + 1;
        if IDeclExiste < 0 then
          Inc(LineaFront, Length(DeclLinea.Split([#10])));
        var R2 := '';
        try
          FotoMet.Vigila(A.Path);
          R2 := DoEdit(A.Path, FrontLine, string.Join(#10, ImplLineas) + #10#10 + FrontLine, LineaFront, False);
        except
          on E: Exception do
            R2 := MsgExcepcion(E.ClassName, E.Message);
        end;
        if not EsMsg(R2, SK_EDIT_ESCRITO_EN_FMT) then
        begin
          if DeclNota <> '' then
            Exit(MsgConCausa(SR_EDIT_INSERT_FALLO_IMPLEMENTACION_FMT, R2, [R2]));
          var NoVolvio := FotoMet.Restaura;
          if NoVolvio <> '' then
            Exit(MsgFmt(SR_FOTO_NO_VOLVIO_FMT, [NoVolvio, R2]));
          Exit(MsgConCausa(SR_EDIT_INSERT_METODO_DESHECHO_FMT, R2, [R2]));
        end;
        if DeclNota <> '' then
          Exit(MsgFmt(SK_EDIT_INSERT_METODO_SOLO_IMPL_FMT,
            [A.ClassName_, DeclNota, Copy(FirmaCual, 1, 70), R2]) + NotaCabecera);
        Exit(MsgFmt(SK_EDIT_INSERT_METODO_DOS_MITADES_FMT,
          [A.ClassName_, IfThen(NotaPublished <> '', #10'  ' + NotaPublished, ''),
           DeclLinea.Trim, R1, Copy(FirmaCual, 1, 70), R2]));
      end;

      // ---------- DELETE LINE ----------
      if A.DeleteLine then
      begin
        Result := DeleteDeLineaDenegado(A.HasOld, A.OldLine, A.NewText, A.AtLine);
        if Result <> '' then
          Exit;
        Exit(DoEdit(A.Path, A.OldLine, '', A.AtLine, IsDesigner, True, A.ToLine));
      end;

      // new without anchor: measured pattern where generic edit tools rewrite
      // the whole file. Explicit rejection, never creative interpretation.
      if (not A.HasOld or (A.OldLine = '')) and A.HasNew then
        Exit(MsgText(SR_EDIT_NEW_SIN_ANCLA));
      if not A.HasOld then
        Exit(MsgText(SR_EDIT_FALTAN_PARAMETROS_MODOS_OLD));
      if not A.HasNew then
        Exit(MsgText(SR_EDIT_HAS_PASADO_OLD_PERO));

      Result := DoEdit(A.Path, A.OldLine, A.NewText, A.AtLine, IsDesigner,
        False, A.ToLine, A.Ensayo);
    except
      on E: Exception do
        Result := MsgExcepcion(E.ClassName, E.Message);
    end;
  finally
    GLock.Leave;
  end;
end;

{ Designer lint: every property line of the RESULTING file resolved against
  the framework tables of the active Delphi (Lsp.DesignerMeta - classes,
  published properties, enum/set members and inheritance, read from that
  Delphi's own source by Lsp.DesignerMetaGen). The framework describes
  itself; no hand-written error rules. Field origin (Fase 3): a hand-edited
  .fmx crashed at form-load on the device with no trace - the build only
  checks a form resource's text grammar. Warnings, not refusals; and an edit
  never waits for a table still being generated (it says it did not check). }
function EncDeFormNuevo(const APath, ATexto, AEnc: string; out AError: string;
  out ALinea: Integer; out ACita: string): string;
begin
  Result := AEnc;
  AError := '';
  ALinea := 0;
  ACita := '';
  if not EsRutaDeDesigner(APath) then
    Exit;
  AError := ParserDeForm(ATexto, AEnc, ALinea, ACita);
  if AError = '' then
    Exit;
  var LineaBom: Integer;
  var CitaBom: string;
  if ParserDeForm(ATexto, 'utf8-bom', LineaBom, CitaBom) = '' then
  begin
    AError := '';
    ALinea := 0;
    ACita := '';
    Result := 'utf8-bom';
  end;
end;

function AvisosDelMotor(const ARespuesta: string): TArray<string>;
begin
  Result := [];
  var Dentro := False;
  for var L in ARespuesta.Split([#10]) do
  begin
    var T := L.Trim;
    if not Dentro and MsgCuerpo(T).StartsWith('***') then
      Dentro := True;
    if Dentro and (T <> '') then
      Result := Result + [T];
  end;
end;

function LintDeForm(const ADfm, ATexto, AEnc: string; AJuzga: Boolean;
  AEsperaMs: Cardinal; ALector: Boolean): TLintDeForm;
var
  Lineas: TArray<string>;
begin
  Result := Default(TLintDeForm);
  // las lineas como delphi_read: los avisos citan su numero (septima revision)
  Lineas := LineasDelTexto(ATexto);
  // EL parser del IDE las lee como LineasDeForm, que es como las leen los
  // jueces de abajo? Si no (DSGN-161), lo que dirian saldria de otras lineas:
  // eso solo (3b del censo de jueces, 1.20.2). Un binario ya tiene la forma
  // del IDE, la de su conversion
  if AJuzga then
  begin
    Result.Parser := AvisoDeFormaDeLineas(Lineas);
    if Result.Parser <> '' then
      Exit;
  end;
  // ...y su raiz, por la cadena de ancestros de su .pas (H8 de la 1.19.2)
  Result.Propiedades := DesignerMetaLint(EsDesignerFmx(ADfm), Lineas, Result.Notas,
    Result.Falta, Result.SinJuez, AEsperaMs, UnidadDeDesigner(ADfm));
  // El form contra su clase (Lsp.DesignerBinding): un OnClick a un metodo
  // en public compila y revienta al cargar el form. Se avisa AL ESCRIBIR.
  Result.Enlace := DesignerBindingWarnings(ADfm, Lineas);
  // ...y EL parser del IDE con los bytes del disco (8.10 de la 1.18.0): un //
  // en un .fmx daba CLEAN y solo el IDE lo rechazaba al cargarlo
  if AJuzga then
    Result.Parser := AvisoDelParserDeForm(ATexto, AEnc);
  // EL juez de verdad de lo que la tabla no juzga (DSGN-061 de la 1.20): una
  // propiedad que la clase guarda por codigo no tiene tipo en la tabla, y
  // FontColor = -65536 en un TEdit FMX pasaba delphi_edit sin aviso y el lint
  // con CLEAN de un form que no abria. Solo si la tabla no encontro nada: con
  // un aviso suyo el form ya no carga, y el lector no diria mas
  if ALector and (Result.SinJuez > 0) and (Result.Parser = '') and
     (Length(Result.Propiedades) = 0) and (Result.Falta.Razon = '') then
    Result.Lector := LoQueNoCargaElIde(ADfm, ATexto, AEnc, Result.SinLector);
end;

{ Lo que delphi_edit (y el changeset y la tanda, que escriben por el) dice del
  form que acaba de escribir: LintDeForm con el texto escrito, sin esperar a
  una tabla, presentado como avisos de una edicion. }
function AvisosDelLector(const APath: string): TArray<string>;
var
  Texto, Enc: string;
begin
  Result := [];
  try
    if not EsRutaDeDesigner(APath) or (TextoDeDesigner(APath, Texto, Enc) <> '') then
      Exit;
    // la tabla sin esperarla, como tras cada edicion; y el lector
    var L := LintDeForm(APath, Texto, Enc, True, 0, True);
    if Length(L.Lector) > 0 then
      Result := [MsgFmt(SN_EDIT_AVISO_LECTOR_FMT, [ExtractFileName(APath)])] + L.Lector;
  except
    // un juicio que no se pudo hacer no tumba una escritura ya hecha
    Result := [];
  end;
end;

function ConAvisosDelLector(const ARespuesta, APath: string): string;
begin
  Result := ARespuesta;
  if EsFallo(ARespuesta) or not EsRutaDeDesigner(APath) then
    Exit;
  var Avisos := AvisosDelLector(TPath.GetFullPath(APath));
  if Length(Avisos) > 0 then
    Result := Result + #13#10 + string.Join(#13#10, Avisos);
end;

function TandaDeUnBloque(const AOld, ANew, AFragment: string; AAtLine, AToLine: Integer;
  ADelete: Boolean; out ANegativa: string): string;
begin
  Result := '';
  ANegativa := '';
  if not TieneSalto(AOld) or (AFragment <> '') or (ADelete and (ANew <> '')) then
    Exit;
  // el bloque dice lo que se cambia, o lo dice el rango: los dos no (como en
  // una entrada de edits)
  if AToLine > 0 then
  begin
    ANegativa := MsgText(SR_RANGE_WITH_BLOCK);
    Exit;
  end;
  var Tanda := TJSONArray.Create;
  try
    var Entrada := TJSONObject.Create;
    Tanda.AddElement(Entrada);
    Entrada.AddPair('old', AOld);
    Entrada.AddPair('new', IfThen(ADelete, '', ANew));
    if AAtLine > 0 then
      Entrada.AddPair('atline', TJSONNumber.Create(AAtLine));
    Result := Tanda.ToJSON;
  finally
    Tanda.Free;
  end;
end;

function DesignerLint(const APath, ATexto, AEnc: string): TArray<string>;
var
  Raw: TArray<string>;
  Res: TStringList;
  I: Integer;
  ExtName: string;
begin
  Result := [];
  // (sin el lector: esto corre DENTRO del cerrojo; AvisosDelLector, fuera)
  var L := LintDeForm(APath, ATexto, AEnc, True, 0);
  var Falta := L.Falta;
  var Notas := L.Notas;
  Raw := L.Propiedades;
  var Bind := L.Enlace;
  // lo que el texto no dice y dcc si: un form de texto en UTF-16/32 no se
  // compila (DSGN-121), y uno sin BOM cuyos bytes son UTF-8 lo lee en ANSI
  // (READ-009). Lo decian lint y el disenador; delphi_edit, la tanda y el
  // changeset escriben el mismo form y lo callaban (B1 de la 1.18.2), y luego
  // solo lo ancho (W9 del revisor de cierre): LA nota, por su casa, del
  // fichero que acaba de escribirse
  var NotaEnc := NotaDeCodificacionDeForm(APath);
  if (L.Parser = '') and (Length(Raw) = 0) and (Length(Bind) = 0) and (Length(Notas) = 0) and
     (Falta.Razon = '') and (NotaEnc = '') then
    Exit;
  Res := TStringList.Create;
  try
    // lo primero, el parser del IDE: con el, el IDE no abre el form
    if L.Parser <> '' then
      Res.Add(L.Parser);
    // sin tabla, su nota sola: no es un aviso de propiedades (iba debajo de
    // la cabecera EDIT-076, "the app CRASHES": revision de la 1.12.0)
    if Falta.Razon <> '' then
      Res.Add(MsgFmt(SN_DESIGNER_LINT_SIN_TABLA_FMT, [Falta.Razon]));
    if Length(Raw) > 0 then
    begin
    // la cabecera, encima de SUS avisos (no encima del parser)
    var Inicio := Res.Count;
    for I := 0 to High(Raw) do
    begin
      if I >= 8 then
      begin
        Res.Add(MsgFmt(SF_EDIT_Y_MAS_FMT, [Length(Raw) - 8]));
        Break;
      end;
      Res.Add(Raw[I]);
    end;
    if EsDesignerFmx(APath) then
      ExtName := '.fmx'
    else
      ExtName := '.dfm';
    Res.Insert(Inicio, MsgFmt(SN_EDIT_AVISO_DESIGNER_PROPIEDADES_FMT, [ExtName]));
    end;
    // lo que no se pudo comprobar, con su propia linea y fuera de EDIT-076:
    // un objeto de una clase de terceros no hace que la app reviente (un
    // form con el TSslContext de ICS lo decia en cada edicion; revision)
    if Length(Notas) > 0 then
    begin
      Res.Add(MsgFmt(SN_DESIGNER_LINT_NOTAS_FMT,
        [ExtractFileName(APath), Length(Notas)]));
      for I := 0 to High(Notas) do
      begin
        if I >= 8 then
        begin
          Res.Add(MsgFmt(SF_EDIT_Y_MAS_FMT, [Length(Notas) - 8]));
          Break;
        end;
        Res.Add(Notas[I]);
      end;
    end;
    if Length(Bind) > 0 then
    begin
      Res.Add(MsgText(SN_DESIGNER_BINDING_LINT_HEADER));
      Res.AddStrings(Bind);
    end;
    if NotaEnc <> '' then
      Res.Add(NotaEnc);
    Result := Res.ToStringArray;
  finally
    Res.Free;
  end;
end;

{ Una linea que es solo estructura (end, begin, un parentesis...) se repite
  legitimamente encima o debajo de otra igual: un form y su ultimo
  componente acaban los dos en "end". El aviso de "ancla repetida" saltaba
  al insertar un objeto al final de un .dfm (revision 27-sep-2026). }
function EsSoloEstructura(const S: string): Boolean;
begin
  Result := MatchText(S.Trim, ['end', 'end;', 'end.', 'begin', 'else', 'try',
    'finally', 'except', ')', ');', 'end)', 'end);']);
end;

{ La salida sin convertir de un caracter que no cabe, en un FUENTE: su
  literal Pascal. Uno del BMP, #$XXXX o ChrW/WideChar; uno de fuera (un
  emoji), su PAR de sustitutos o Char.ConvertFromUtf32, por la RTL: ChrW no
  llega mas alla de $FFFF (r5-L1 de la 1.18.0). }
function SalidaPascalDe(ACodigo: Integer): string;
var
  Par, Alto, Bajo, Hex: string;
begin
  // un sustituto suelto no tiene literal que valga: es medio caracter
  if (ACodigo >= $D800) and (ACodigo <= $DFFF) then
    Exit('');
  Hex := IntToHex(ACodigo, 4);
  if ACodigo <= $FFFF then
    Exit(MsgFmt(SF_EDIT_LITERAL_PASCAL_FMT, [Hex, Hex, Hex, Hex]));
  Par := Char.ConvertFromUtf32(UCS4Char(ACodigo));
  Alto := IntToHex(Ord(Par[1]), 4);
  Bajo := IntToHex(Ord(Par[2]), 4);
  Result := MsgFmt(SF_EDIT_LITERAL_PASCAL_PAR_FMT, [Alto, Bajo, Alto, Bajo, Hex]);
end;

function DoEdit(const APath, AOld, ANew: string; AAtLine: Integer;
  AIsDesigner: Boolean; ADelete: Boolean = False;
  AToLine: Integer = 0; AEnsayo: Boolean = False): string;
var
  B, NewBytes, After: TBytes;
  K: TEncKind;
  Text, Eol: string;
  M, D: TMetrics;
  Lines: TArray<string>;
  Hits: TArray<Integer>;
  I, HitIdx: Integer;
  Replacement: string;
  Warnings: TStringList;

  function HighCount(const S: string): Integer;
  var
    X: Byte;
    KH: TEncKind;
  begin
    Result := 0;
    // The BOM belongs to the FILE, not to any line of text: encoding a text
    // fragment as utf8-bom would smuggle 3 phantom high bytes into the
    // accounting (measured false positive: "expected 0, got 3").
    KH := K;
    if (KH = ekUtf8Bom) or (KH in ENC_ANCHAS) then
      KH := ekUtf8; // sin BOM, y UTF-16/32 en el mismo cuerpo UTF-8 que mide Measure
    try
      for X in EncodeText(S, KH, False) do // medir, no escribir
        if X > 127 then
          Inc(Result);
    except
      Result := -1;
    end;
  end;

begin
  B := TFile.ReadAllBytes(APath);
  // la regla de ida y vuelta, en el escritor (David, 9-oct-2026): lo que no
  // vuelve igual por su codificacion no se reescribe - cambiaria bytes que
  // nadie toco (un UTF-32 mal formado, un BOM de UTF-8 con el cuerpo roto)
  var NoVuelve := ReescrituraDenegada(APath, B, K);
  if NoVuelve <> '' then
    Exit(NoVuelve);
  Text := DecodeBytes(B, K);
  M := Measure(B);
  Eol := NombreDelSalto(SaltoDominante(Text)); // la regla de todos

  if TieneSalto(AOld) then
    Exit(MsgText(SR_PATCH_ANCHOR_MULTILINE));
  // un ancla vacia solo vale para borrar una linea EN BLANCO por su numero
  // (P3-L9): no hay texto que copiar; lo comprueba LineaEnBlancoDenegada
  // ...y UNA: un rango (toline) sin un ancla de texto no (M-3 del revisor)
  if (AOld.Trim = '') and ADelete and (AToLine > 0) then
    Exit(MsgText(SR_EDIT_RANGO_SIN_OLD));
  var EnBlanco := (AOld.Trim = '') and ADelete and (AAtLine > 0);
  if (AOld.Trim = '') and not EnBlanco then
    Exit(MsgText(SR_EDIT_ANCLA_ESTA_VACIA_SOLO));
  // (un U+FFFD en el ancla no se niega aqui: es la pista de un ancla que no
  // casa, la de AnclaPerdida; negado antes de buscar, una linea que lo lleva
  // de verdad no se podia editar - E3 de A15)

  Lines := SplitToLines(Text);
  if EnBlanco then
  begin
    var NoBlanca := LineaEnBlancoDenegada(Lines, CuantasLineasReales(Lines), AAtLine,
      TPath.GetFileName(APath));
    if NoBlanca <> '' then
      Exit(NoBlanca);
  end;
  Hits := LineasDondeCasaElAncla(Lines, AOld); // la regla del motor
  Warnings := TStringList.Create;
  try
    if Length(Hits) = 0 then
      // Por que no casa: UN texto para delphi_edit, delphi_textedit y la
      // linea que falta de un bloque (AnclaPerdida).
      Exit(AnclaPerdida(Lines, AOld, TPath.GetFileName(APath)));

    // cual de ellas: LA eleccion de las dos tools (LineaElegida, A15)
    var Eleccion := LineaElegida(Hits, AAtLine, HitIdx);
    if Eleccion <> '' then
      Exit(Eleccion);

    // EL RANGO. Con AToLine el ancla deja de ser una linea y pasa a ser la
    // PRIMERA de un tramo que acaba en AToLine, incluida. Las reglas de un
    // rango no tienen nada de Pascal, asi que viven en RangoHasta y de ahi
    // tira tambien el motor de texto plano: una sola puerta.
    var Reales := CuantasLineasReales(Lines); // sin la fantasma del salto final
    var Fin: Integer;
    var MalRango := RangoHasta(APath, HitIdx, AToLine, Reales, Fin);
    if MalRango <> '' then
      Exit(MalRango);
    var Cuantas := Fin - HitIdx + 1;
    // Lo que SALE, para el recuento de bytes altos de mas abajo. Con un rango
    // no es el ancla: son TODAS las lineas que se van. Contar solo el ancla
    // dispararia el aviso de "acentos fuera de cuadro" -que manda PARAR- en
    // cualquier rango que incluyese una linea con acentos.
    var Salido := AOld;
    if Cuantas > 1 then
      Salido := string.Join(#10, Copy(Lines, HitIdx, Cuantas));

    // La sangria que el ancla dejo fuera: LA regla de las dos tools
    // (SangraComoLaLinea). Aqui iba otra: el resto de la linea delante de la
    // PRIMERA linea de new, SIEMPRE - con new ya sangrado salia doble, y las
    // demas lineas de new sin ella (medido el 6-oct-2026: 4 + 4 = 8 espacios).
    // LA regla del salto final, la misma en las dos tools y en los bloques
    // (LineasDeNew): uno es el fin de linea; cada uno de mas, una en blanco.
    Replacement := string.Join(#10, SangraComoLaLinea(Lines[HitIdx], AOld, LineasDeNew(ANew)));
    // Empty replacement (old given + new='') blanks the line - a legitimate
    // edit. Never index Split()[0] on it: '' yields an empty array (measured
    // Access Violation in the field test) - PrimerTrozo, Lsp.Args. Line
    // DELETION is delete:true.
    var NewFirst := PrimerTrozo(Replacement, [#10]);
    // las que ocupan el sitio del tramo; ninguna con delete: se va entero
    // (sin rango, Cuantas = 1)
    var Nuevas: TArray<string> := nil;
    if not ADelete then
    begin
      // An insert that repeats the line above or below is almost always the
      // anchor line sent twice by mistake: it compiles, it is invisible, and
      // it cost an agent eight calls to find and undo (field round 10).
      if not ADelete and (Replacement <> '') then
      begin
        var LastNew := Replacement;
        if Replacement.Contains(#10) then
        begin
          var Parts := Replacement.Split([#10]);
          LastNew := Parts[High(Parts)];
        end;
        if (HitIdx > 0) and (Lines[HitIdx - 1].Trim <> '') and
           not EsSoloEstructura(NewFirst) and
           (Lines[HitIdx - 1].Trim = NewFirst.Trim) then
          Warnings.Add(MsgFmt(SN_EDIT_DUP_ABOVE_FMT, [HitIdx, NewFirst.Trim]));
        // Con un rango, la linea de debajo esta DENTRO de lo que se va: no
        // es una duplicacion, es material a punto de desaparecer.
        // El numero es el de la linea en el fichero RESULTANTE (el que la
        // respuesta ensena): debajo de todo lo insertado, no del ancla
        if (Cuantas = 1) and (HitIdx < High(Lines)) and (Lines[HitIdx + 1].Trim <> '') and
           not EsSoloEstructura(LastNew) and
           (Lines[HitIdx + 1].Trim = LastNew.Trim) then
          Warnings.Add(MsgFmt(SN_EDIT_DUP_BELOW_FMT,
            [HitIdx + Length(Replacement.Split([#10])) + 1, LastNew.Trim]));
      end;
      // un Replacement vacio deja la linea EN BLANCO (borrarla es delete);
      // ''.Split da un array vacio, que el compositor tomaria por borrar
      if Replacement = '' then
        Nuevas := ['']
      else
        Nuevas := Replacement.Split([#10]);
    end;

    var Joined: string;
    var EolSep := SaltoDominante(Text); // el mismo salto que dice la cabecera
    // El compositor de todos (CambiaLineasEnSuTexto): el tramo por las
    // nuevas, con EolSep entre ellas - un new de varias lineas no deja LF en
    // un CRLF (regresion de la octava revision, cazada en la novena por
    // EDIT-082) - y cada linea de fuera con SU salto: unidas todas al
    // dominante, un fichero mixto salia entero a ese salto (1.18.2)
    Joined := CambiaLineasEnSuTexto(Text, HitIdx, Cuantas, Nuevas, EolSep);
    // Nada cambia (old == new): no se escribe ni se copia, y se dice.
    // Contestaba WRITTEN con una copia de un fichero identico (quinta
    // revision). La gemela, en Lsp.TextEdit.DoEditLine.
    if Joined = Text then
      Exit(MsgFmt(SN_EDIT_SIN_CAMBIOS_FMT, [HitIdx + 1, TPath.GetFileName(APath)]));

    // el primer caracter no ASCII de un fuente que no tenia codificacion
    // elige la que dcc lee bien (4.1 de la 1.18.0); el resto, la suya. La K
    // nueva vale tambien para el recuento de bytes altos y el eco
    // el origen, ANTES de escribir (despues, la huella ya es la nueva y el
    // fichero de antes pareceria de otro): para EDIT-080, abajo
    var Existia, TeniaCodificacion: Boolean;
    var KOrigen: TEncKind;
    OrigenDeLaLlamada(APath, B, True, Existia, TeniaCodificacion, KOrigen);
    var KLeida := K;
    K := EncAlEscribir(APath, K, B, True, Joined);
    // si esta escritura CAMBIA la codificacion (una tanda que paso de la ANSI a
    // UTF-8 con BOM: la decide lo de antes de la llamada), lo de antes se
    // cuenta en la nueva: un acento de un byte pasaba a dos y EDIT-081 pedia
    // restaurar un fichero bien escrito (medido el 9-oct-2026). Si lo de antes
    // no cabe en K (una entrada anterior puso una Omega y esta la quita), lo
    // que sale tampoco se cuenta en K (HighCount = -1) y EDIT-081 no mira
    if K <> KLeida then
      try
        M := Measure(EncodeText(Text, K));
      except
        on ECaracterNoCabe do
          ;
      end;
    try
      // lo que sustituye: un sustituto suelto que ya estaba se escribe como
      // estaba, si K lo escribe tal cual (EncodeText; revisor de la 1.18.1)
      NewBytes := EncodeText(Joined, K, True, Text);
    except
      on E: ECaracterNoCabe do
      begin
        // la negativa la compone la excepcion; la salida del literal Pascal,
        // solo en un fuente (decima revision)
        if EsRutaDeFuente(APath) then
          Exit(E.Message + SalidaPascalDe(E.Codigo));
        Exit(E.Message);
      end;
    end;

    // ...y lo que se escribe tiene que leerse igual (EDIT-122): el ensayo tambien
    var Cambia := LecturaCambiada(APath, NewBytes, K);
    if Cambia <> '' then
      Exit(Cambia);

    // ENSAYO: hasta aqui todo lo que el motor comprueba; lo que preguntaria el
    // escritor, y nada mas (el preview de un changeset; decima revision)
    if AEnsayo then
      Exit(SustitucionDenegada(APath));
    var CopyNote := BackupFile(APath);
    AtomicWrite(APath, NewBytes);

    var NotaRelectura: string;
    After := RelecturaDe(APath, NewBytes, NotaRelectura);
    D := Measure(After);
    var AfterText := DecodeBytes(After, K);
    var AfterLines := LineasDelTexto(AfterText); // el eco sin la fantasma ("6|" de 5)

    var Ctx := MsgText(SF_EDIT_NO_LOCALIZAR_LINEA_NUEVA);
    // El sitio se SABE: la sustitucion empieza justo donde estaba el ancla.
    // Buscar la primera linea del texto nuevo DESDE ARRIBA sacaba otra
    // region entera cuando esa linea es de las que se repiten - un "begin",
    // un "var", un "end;" - y entonces el agente comprobaba su edicion
    // mirando un trozo de fichero que no era el suyo (medido el 2026-09-20:
    // edicion en la linea 19, eco de la 7).
    var Idx := HitIdx;
    if Idx > High(AfterLines) then
      Idx := High(AfterLines);
    // Salvavidas por si algun dia el sitio no cuadra: se busca DESDE ahi
    // hacia abajo, nunca desde el principio.
    if (NewFirst <> '') and (Idx >= 0) and (Idx <= High(AfterLines)) and
       not AfterLines[Idx].Contains(NewFirst) then
      for I := Idx to High(AfterLines) do
        if AfterLines[I].Contains(NewFirst) then
        begin
          Idx := I;
          Break;
        end;
    if Idx >= 0 then
    begin
      var IniC := Idx - 1;
      if IniC < 0 then IniC := 0;
      // La ventana cubre TODO lo escrito, no las dos primeras lineas: una
      // insercion de diez lineas se verificaba viendo tres.
      var FinC := Idx + 2;
      if Replacement <> '' then
        FinC := Idx + Length(Replacement.Split([#10])) + 1;
      if FinC > High(AfterLines) then FinC := High(AfterLines);
      var SbC := TStringBuilder.Create;
      try
        for I := IniC to FinC do
          SbC.Append('  ').Append(CitaDeLinea(I + 1, AfterLines[I])).Append(#10);
        Ctx := SbC.ToString.TrimRight([#10]);
      finally
        SbC.Free;
      end;
    end;

    if D.Corruption > M.Corruption then
      Warnings.Add(MsgText(SN_EDIT_CARACTERES_CORRUPCION));
    // EDIT-080 cuando ESTA escritura eligio la codificacion: el fichero no
    // tenia ninguna antes de la llamada (ni BOM ni byte alto) y esta la fijo
    // o la cambio. Era M.High = 0, y Measure no cuenta el BOM: un UTF-8 con
    // BOM y solo ASCII decia "era ASCII puro" (revisor propio de la 4.1)
    if not TeniaCodificacion and (D.High > 0) and (not HayByteAlto(B) or (K <> KLeida)) then
      Warnings.Add(MsgFmt(SN_EDIT_ERA_ASCII_PURO_FMT, [EncName(K)]));
    var Salen := HighCount(Salido);
    var Entran := HighCount(Replacement);
    if (Salen >= 0) and (Entran >= 0) and (D.High <> M.High - Salen + Entran) then
      Warnings.Add(MsgFmt(SN_EDIT_ACENTOS_FUERA_CUADRO_FMT,
        [M.High - Salen + Entran, D.High]));
    var Ajenos: Boolean;
    if Eol = 'CRLF' then
      Ajenos := D.Loose > M.Loose
    else if Eol = 'CR' then
      Ajenos := D.LF > M.LF
    else
      Ajenos := D.CRLF > M.CRLF;
    if Ajenos then
      Warnings.Add(MsgFmt(SN_EDIT_FINALES_LINEA_AJENOS_FMT, [Eol]));
    var FmNew := MojibakeLines(Replacement);
    if (Length(FmNew) > 0) and (Length(MojibakeLines(AOld)) = 0) then
      Warnings.Add(MsgText(SN_EDIT_FIRMA_MOJIBAKE_NUEVO));
    // en el fichero ESCRITO (AfterText), lo que toca lo escrito: las lineas de
    // Replacement desde HitIdx, o la juntura si la edicion solo quito
    var Escritas := Length(Replacement.Split([#10]));
    if ADelete then
      Escritas := 0;
    for var Aviso in AvisosDeLlaves(APath, AfterText, HitIdx, Escritas) do
      Warnings.Add(Aviso);
    // (dentro de una tanda o un changeset lo hace quien agrupa, una vez: H6).
    // Tambien de un .pas: los forms de su unidad, por su enlace (punto 7)
    if GJuicioDeFormAplazado = 0 then
      for var LintW in JuicioDeLoEscrito(APath, AfterText, EncName(K)) do
        Warnings.Add(LintW);

    if not AIsDesigner then
    begin
      var Estructura := AvisoDeEstructura(Text, AfterText);
      if Estructura <> '' then
        Warnings.Add(Estructura);
      // lo que mira, en el CODIGO del fichero escrito: una firma dentro de un
      // comentario, o un comentario con ':=' encima de una de verdad,
      // avisaban de una insercion en un metodo que no habia (revision de la
      // 1.10.0). Y DONDE cayo, por EL lector de rutinas (TUnidadPas): dentro
      // del cuerpo de otra (entre su begin y su end) o detras de las
      // declaraciones (el bloque principal, initialization, tras el end
      // final). Lo decia la linea de ENCIMA, con una lista de sentencias: dos
      // declaraciones seguidas en un interface (la de arriba acaba en ');')
      // avisaban (medido el 18-oct-2026)
      var AfterVista := LineasDelTexto(CodigoPascal(AfterText));
      var NewLines := Replacement.Split([#10]);
      var Lector: TUnidadPas := nil;
      try
        for var J := 0 to High(NewLines) do
        begin
          if (Idx < 0) or (Idx + J > High(AfterVista)) then
            Break;
          if not TRegEx.IsMatch(AfterVista[Idx + J], '^' + PatronInicioDeRutina + '\b', [roIgnoreCase]) then
            Continue;
          if Lector = nil then
            Lector := LeeFuentePascal(AfterText);
          var L := Idx + J; // 0-based, como Linea de un cuerpo
          var Donde := '';
          for var C in Lector.Cuerpos do
          begin
            if (C.CuerpoFin < C.CuerpoIni) or (C.Linea = L) then
              Continue;
            var LIni := LineaDePosicion(AfterText, C.CuerpoIni) - 1;
            var LFin := LineaDePosicion(AfterText, C.CuerpoFin) - 1;
            if (L >= LIni) and (L <= LFin) then
            begin
              Donde := MsgFmt(SF_EDIT_EN_EL_CUERPO_DE_FMT, [C.Nombre, C.Linea + 1, C.LineaFin + 1]);
              Break;
            end;
          end;
          if (Donde = '') and (Lector.FinDeclaraciones > 0) and
             (L > LineaDePosicion(AfterText, Lector.FinDeclaraciones) - 1) then
            Donde := MsgText(SF_EDIT_TRAS_LAS_DECLARACIONES);
          if Donde <> '' then
          begin
            Warnings.Add(MsgFmt(SN_EDIT_POSIBLE_INSERCION_METODO_FMT, [Copy(NewLines[J], 1, 60), Donde]));
            Break;
          end;
        end;
      finally
        Lector.Free;
      end;
    end;

    var Accion := MsgFmt(SK_EDIT_ESCRITO_EN_FMT, [TPath.GetFileName(APath)]);
    if Cuantas > 1 then
    begin
      if ADelete then
        Accion := MsgFmt(SN_RANGE_DELETED_FMT,
          [Cuantas, HitIdx + 1, HitIdx + Cuantas, TPath.GetFileName(APath)])
      else
        Accion := MsgFmt(SN_RANGE_REPLACED_FMT,
          [Cuantas, HitIdx + 1, HitIdx + Cuantas, TPath.GetFileName(APath)]);
    end
    else if ADelete then
      Accion := MsgFmt(SK_EDIT_BORRADA_LINEA_FMT,
        [HitIdx + 1, TPath.GetFileName(APath)])
    else if Replacement = '' then
      Accion := MsgFmt(SK_EDIT_BLANQUEADA_LINEA_FMT,
        [HitIdx + 1, TPath.GetFileName(APath)]);
    // la etiqueta, la de lo que quedo en el disco (After, lo releido)
    Result := MsgFmt(SF_EDIT_ECO_ESCRITURA_FMT,
      [Accion, EtiquetaDeCodificacion(K, not HayByteAlto(After)), Eol, CopyNote, AuditoriaAntesYDespues(M, D), Ctx]);
    if Warnings.Count > 0 then
      Result := Result + #10 + Warnings.Text.TrimRight;
    if NotaRelectura <> '' then
      Result := Result + #10 + NotaRelectura;
  finally
    Warnings.Free;
  end;
end;

{ La unidad de un designer para EsDesignerFmx (Lsp.DesignerForma: el marco de
  un .dfm de un modulo de datos lo dice su grupo de clases), por LA puerta de
  leer y con los lugares del propio designer (TextoDeDesigner). '' si no se
  puede: entonces, la extension. }
function TextoDeUnidadDeDesigner(const APas: string): string;
begin
  Result := '';
  try
    if TFile.Exists(APas) then
      Result := LeeTexto(APas, [ltJaula]);
  except
    // negada o ilegible: el marco, por la extension
  end;
end;

initialization
  GLock := TCriticalSection.Create;
  GTextoDeUnidad := TextoDeUnidadDeDesigner;

finalization
  GLock.Free;

end.
