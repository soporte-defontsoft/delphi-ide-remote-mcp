unit Lsp.DesignerBin;

{ Un .dfm BINARIO, y el camino de ida y vuelta a texto que usa el propio IDE
  ("Ver como texto" y guardar): las funciones de System.Classes que Delphi
  trae de serie, corridas en el ayudante de 32 bits como en el IDE - en este
  servidor, Win64, un flotante perdia sus ultimas cifras (V71 de la 1.23.1;
  Lsp.FormRender.ConversionDelIde) -. Los .fmx son siempre texto: esto es
  solo VCL.

  Dos formas binarias, medidas con convert.exe (2026-09-24):
    - el fichero REAL en disco envuelve el flujo en una cabecera de recurso de
      16 bits: FF 0A 00 (tipo RT_RCDATA) + NOMBRE EN MAYUSCULAS + 00 +
      flags/tamano + TPF0... Un texto guardado en UTF-16 empieza por FF FE:
      por eso se miran tres bytes, no uno.
    - un flujo a pelo empieza por TPF0 (lo que escribe un WriteComponent).
  Un designer de texto empieza siempre por object/inherited/inline: nunca por
  $FF ni por TPF0.

  UN NOMBRADOR para la forma del fichero: hasta hoy cuatro sitios (Lsp.Patch,
  Lsp.ProjectUnits, Mcp.Tools.Designer, delphi_upload) comparaban los bytes a
  mano, cada uno con su copia de la regla. Y un solo conversor, el de la RTL:
  lo que escribe to-binary es byte a byte lo que escribe el IDE, y lo que lee
  to-text es lo que ensena "Ver como texto". Decision de David (24-sep-2026)
  tras el reporte de Hermes: un form legacy binario dejaba ciego al agente. }

interface

uses
  System.SysUtils,
  Lsp.Codificacion;

// La forma de un designer (TDesignerShape, DesignerShapeOf) vive en
// Lsp.DesignerForma: los renderizadores de src\Render la leen igual.
function IsBinaryDesignerBytes(const ABytes: TBytes): Boolean;
{ Lo mismo leyendo del disco: False si no existe o no llega a 4 bytes. }
function IsBinaryDesignerFile(const APath: string): Boolean;
{ Binario (cualquiera de las dos formas) -> texto, como "Ver como texto" del
  IDE. Devuelve '' si bien; si no, el motivo (fichero danado, no es un
  designer, o no se le pudo preguntar al conversor). El texto sale ASCII con
  CRLF, byte a byte lo que escribe convert.exe: lo convierte el ayudante de
  32 bits (V71), y cada texto se guarda por la huella de sus bytes. }
function DesignerBinaryToText(const ABytes: TBytes; out AText: string): string;
function DesignerFileToText(const APath: string; out AText: string): string;
{ Texto -> binario CON envoltorio de recurso (la forma en disco del IDE).
  ATexto son los BYTES del form de texto tal como estan en disco, y el parser
  los lee TAL CUAL, como el IDE, en el ayudante de 32 bits (V71: el valor de
  un flotante redondeado a Double eran otros bytes): el binario sale como el que
  compila dcc de ese mismo fichero (medido el 13-oct: un UTF-8 con BOM con
  caracteres fuera de la ANSI entra entero; uno SIN BOM lo lee en la ANSI de
  la maquina, tambien dcc). Un form de texto en UTF-16 o UTF-32 no lo lee, y
  el IDE tampoco (A28 de la 1.23): quien llama lo niega antes con
  FormAnchoQueNoCarga. Devuelve '' si bien; si no, el error del parser con su
  linea. }
function DesignerTextToBinary(const ATexto: TBytes; out ABytes: TBytes): string;

{ LA nota de un form de TEXTO guardado en UTF-16 o UTF-32 (AEnc, el nombre de
  su codificacion, EncName): el IDE no lo carga y dcc no lo compila, y la
  salida es command=to-text - DSGN-121, medido con el IDE el 24-oct-2026 (A28
  de la 1.23) -; '' en otra codificacion. La dicen quienes escriben el TEXTO
  del form - delphi_edit, la tanda y el changeset (B1, punto 4 de la 1.18.2)
  -, que es como se arregla a mano. }
function NotaDeFormAncho(const ANombre, AEnc: string): string;

{ Si un form de TEXTO en disco esta en UTF-16 o UTF-32 (AK), por EL lector
  del BOM (Lsp.Codificacion.KindDeBom), leyendo solo sus cuatro primeros
  bytes. False tambien si no se puede leer: es una nota, no una puerta.
  Vivia en Mcp.Tools.Designer; la necesitan tambien la tanda y el changeset
  (B1, punto 4 de la 1.18.2). }
function FormAncho(const APath: string; out AK: TEncKind): Boolean;
{ to-text de un form de TEXTO ancho (ABytes, sus bytes de disco): su texto
  por EL decodificador de la casa, leido por EL parser en UTF-8 con BOM y
  escrito por EL conversor del IDE (DesignerBinarioATexto), como lo deja el
  IDE al guardarlo. La unica conversion de codificacion de un form, y solo en
  esta operacion pedida. '' si bien, con AText; si no, el motivo (un medio
  caracter, DSGN-147; lo que el parser no lee). }
function TextoDeFormAncho(const ABytes: TBytes; out AText: string): string;

// La linea de objeto (LineaDeObjeto y su inversa ComponeLineaDeObjeto) vive
// en Lsp.DesignerForma, con la forma del fichero: la leen tambien los
// renderizadores.

{ Un texto como VALOR de cadena de un designer de texto, como lo escribe el
  IDE (ObjectBinaryToText de System.Classes; medido en su fuente de 13.1 y en
  los .dfm de ejemplo): los tramos ASCII imprimibles entre comillas y cada
  caracter de los demas - la comilla tambien - como #N: 'Conway'#39's Life',
  'Acci'#243'n'; el vacio, ''. En TROZOS: uno si el texto cabe en 64
  caracteres; si no, uno por cada 64 caracteres del texto, todos menos el
  ultimo acabados en ' +', que van en las lineas de debajo (LineasDePropiedad).
  En una sola linea no: una de 4.095 caracteres o mas no la lee el IDE
  (TParser, "Line too long"; revision de la 1.17.0). }
function TrozosDeLiteral(const S: string): TArray<string>;
{ Si el TEXTO de un valor que va a ser literal de un form (TrozosDeLiteral)
  lleva medio caracter - un sustituto suelto, por EL lector de la casa
  (Lsp.Codificacion.SiguienteSuelto) -, su negativa (DSGN-146); '' si no. El
  literal es ASCII (#55296) y el codificador, que niega el suelto en un texto
  (EDIT-078), ya no lo ve: designer set y styles set lo escribian (medido en
  produccion el 13-oct, punto 4 de la 1.18.2). La preguntan las puertas que
  reciben el valor del agente, antes de componer. AAntes, el texto que la
  propiedad ya tenia: un suelto que YA estaba se escribe como estaba, contados
  por valor como en los escritores (SustitutoNuevo; R8 del revisor del punto
  4: se negaba igual que uno nuevo). }
function SueltoEnLiteral(const ATexto: string; const AAntes: string = ''): string;
{ Las lineas de una propiedad como las escribe el IDE: 'Prop = valor' con un
  trozo; con varios, 'Prop = ' y cada trozo una sangria (dos espacios) mas
  adentro. ASangria, la de la linea de la propiedad. }
function LineasDePropiedad(const ASangria, AProp: string; const ATrozos: TArray<string>): TArray<string>;
{ La sangria de un nivel de un designer de texto, como la escribe el IDE: dos
  espacios por nivel (las propiedades del objeto raiz van en el 1). La
  calculaban a mano cuatro sitios de Lsp.Styles y Lsp.DesignerEdit (2.3 de la
  1.18.0). }
function SangriaDeNivel(ANivel: Integer): string;
{ Su lector, el inverso: el texto de un valor de cadena de un form - tramos
  entre comillas (la comilla doblada dentro), #N y #$N pegados, y trozos
  unidos con '+', que el TParser une: lo que ReadString acepta. False si no
  lo es. }
function LeeLiteralDeForm(const AValor: string; out ATexto: string): Boolean;
function EsLiteralDeForm(const AValor: string): Boolean;
{ Un NOMBRE dado como valor (el Name de un componente, el StyleName de un
  estilo): si es un literal de form ('BtnOk', 'Bot'#243'n', 'a' + 'b'), su
  texto; si no, el valor tal cual. Sin espacios alrededor. Lo leian de tres
  maneras el renombrado y el insert del disenador (quitaban las comillas a
  mano), styles set y styles clone (tal cual): el mismo nombre valia en uno
  y no en otro (P5 de la segunda revision de la 1.17.0). }
function NombreDeValor(const AValor: string): string;
// UN caracter, lo que ReadChar acepta: 'A', #39, #65
function EsCaracterDeForm(const AValor: string): Boolean;
{ Un numero como lo lee el cargador, PREGUNTADO a su parser (ObjectTextToBinary):
  entero, $hex, con decimales y exponente (1.5, -2E3, 1.5e-5), con su signo y
  con el sufijo del tipo con que lo escribe el IDE (34700d un TDate, 1.5s un
  Single, 12.5c un Currency). }
function EsNumeroDeForm(const AValor: string): Boolean;
// y uno ENTERO (lo que el parser deja como vaInt8..vaInt64)
function EsEnteroDeForm(const AValor: string): Boolean;
{ Y uno que lee una propiedad de coma flotante (TReader.ReadFloat): entero o
  con decimales, SIN el sufijo s/c/d - ReadFloat no los lee y el form no
  carga; asi guardan un TDate un Variant o una propiedad que se escribe por
  codigo (AccessTokenExpiryDate = 41488.4481893519d, WriteDate; medido en el
  RTL el 18-oct-2026). }
function EsNumeroDeFloat(const AValor: string): Boolean;

(* LA gramatica de las lineas de un designer de texto, la que escribe
  ObjectBinaryToText: cada linea, que es. Un objeto (LineaDeObjeto) y su end;
  una propiedad 'Prop = valor' con la ultima linea de su valor - una cadena
  partida con ' +' (o la que el IDE empieza en la linea de debajo: 'Caption = '
  y los trozos), una lista ( ... ), un bloque binario { ... } o una coleccion
  < item ... end ... end> -; y dentro de una coleccion sus items, que llevan
  propiedades (un OnClick, un Action = Action1) y otras colecciones. La leian
  cuatro lectores a mano, cada uno con su parte: el arbol de tree y de las
  ediciones cerraba una coleccion con cualquier linea acabada en '>' (un
  'Items = <>' de un item) y tomaba por binario un 'Caption = 'Total = {0}''
  hasta el final del fichero; check-binding contaba como objetos los end de
  los items; set cortaba la cadena larga del IDE por su primera linea
  (revision de la 1.17.0, medido en vivo). *)
type
  TClaseLineaForm = (clfOtra, clfObjeto, clfFin, clfPropiedad, clfValor, clfItem, clfFinItem);
  TLineaForm = record
    Clase: TClaseLineaForm;
    Coleccion: Integer;  // colecciones abiertas alrededor: 0 = el nivel del objeto
    Prop, Valor: string; // clfPropiedad: el nombre (con puntos) y lo de detras del '='
    Fin: Integer;        // clfPropiedad: la ultima linea (0-based) de su valor; la del '>' de una coleccion
    Clave, Nombre, ClaseObj: string; // clfObjeto: lo que da LineaDeObjeto
  end;

function LineasDeForm(const ALineas: TArray<string>): TArray<TLineaForm>;
// una linea 'Prop = valor' (Prop con puntos; AValor sin espacios alrededor)
function LineaDePropiedad(const ALinea: string; out AProp, AValor: string): Boolean;
(* El valor entero de la propiedad de la linea AIni (clfPropiedad): el de su
  linea, o si es una cadena partida, sus trozos en una ('a' + 'b': lo que lee
  LeeLiteralDeForm). De una lista, un bloque o una coleccion, su primera linea
  ('(', '{', '<'). *)
function ValorEnteroDe(const ALineas: TArray<string>; const AForm: TArray<TLineaForm>;
  AIni: Integer): string;
(* Los ELEMENTOS de la lista que abre la propiedad de la linea AIni (su valor
  es '(') y acaba en la linea AFin (su Fin, la de FinDeValor): cada uno con sus
  trozos juntos como los lee LeeLiteralDeForm ('a' + 'b'), sin el ')' que el
  IDE escribe DETRAS del ultimo; una lista dentro de la lista da los suyos en
  el mismo orden. Recorrerla a mano se saltaba el ultimo elemento - y el
  unico -, el del ')' (V109 de la 1.23.1, medido: la puerta del render no lo
  juzgaba). *)
function ElementosDeLista(const ALineas: TArray<string>; AIni, AFin: Integer): TArray<string>;
(* Si el valor de una propiedad (lo de detras del '=', o lo que da
  ValorEnteroDe) es de BLOQUE: una lista '(', un bloque binario '{' o una
  coleccion '<' - lo que no es un valor de una linea, ni se juzga ni se
  reescribe como uno. Se preguntaba a mano en tres sitios del disenador y
  del juez de los forms (2.3 de la 1.18.0). *)
function EsValorDeBloque(const AValor: string): Boolean;
{ Las propiedades de un objeto que valen un IDENTIFICADOR (PopupMenu =
  PopupMenu1), como 'Prop=Valor': las suyas, las de su bloque antes del
  primer hijo, como las escribe el IDE, y ni las de un item. Que la
  propiedad sea de clase - una referencia a otro componente - lo dice la
  tabla (Lsp.DesignerMeta.RutaPorReferencia). AObj: la linea (0-based) de
  su cabecera. Lo preguntan set y el lint (3.3 de la 1.18.0). }
function ReferenciasDeObjeto(const AForm: TArray<TLineaForm>; AObj: Integer): TArray<string>;

{ Un numero como lo escribe el IDE Win32 en una propiedad de coma flotante de
  un form, VCL o FMX: TWriter.WriteFloat y ObjectBinaryToText lo dejan con
  FloatToStrF(V, ffFixed, 16, 18), y V es lo que guarda la propiedad - en una
  Single (ASimple), redondeado a Single: 0.4 se escribe 0.400000005960464500,
  como en los .fmx de ejemplo de 13.1. 10 -> 10.000000000000000000 (un IDE
  Win64 escribe 17 decimales; medido el 4-oct-2026). }
function FlotanteDeForm(const AValor: Extended; ASimple: Boolean): string;
// el de un entero (el Position.X de un control FMX nuevo)
function FlotanteFmx(N: Integer): string;

{ Si un NOMBRE (de componente) puede entrar en un form y en su unidad con
  las codificaciones que tienen, sin cambiarlas - la codificacion de un
  fichero no se cambia de paso (contrato de edicion de la casa, puntos 7 y
  8) -. Un nombre ASCII, siempre. Uno con una letra que no lo es necesita:
  - el form en UTF-8 con BOM: sin el, TParser (el del IDE, el del build y el
    del renderizador) lee el fichero en ANSI, y en ANSI ningun byte alto es
    letra de un identificador (System.Classes, TParser.CharType). El IDE le
    pone el BOM al guardar (ObjectBinaryToText);
  - la unidad con BOM o en ANSI: dcc lee en ANSI un fuente sin BOM, y en
    UTF-8 sin BOM el campo queda con otro nombre que su componente.
  Medido el 7-oct-2026 (segunda revision de la 1.17.0): insert con un nombre
  con acento en un .dfm sin BOM dejaba el proyecto sin compilar (RLINK32), y
  con la unidad en UTF-8 sin BOM el campo salia en la RTTI del exe leido en
  ANSI (otros bytes que su componente); las dos diciendo OK. Devuelve '' o
  la negativa (DSGN-111) con el fichero que no puede. APasEnc es la
  codificacion en que se ESCRIBIRA la unidad (Lsp.Patch.EncAlEscribir: una
  unidad ASCII no tiene ninguna y la elige el nombre). Las codificaciones,
  con los nombres de EncName. }
function NombreQueElFicheroNoLee(const ANombre, ADfm, ADfmEnc, APas, APasEnc: string): string;

{ Lo que dice EL parser del IDE del TEXTO de un designer tal como quedara en
  disco - con sus saltos de linea - (Lsp.DesignerForma.ErrorDelParserDeForm),
  con los bytes que haria en la codificacion AEnc (un nombre de EncName; '' =
  UTF-8 con BOM), tal cual - un UTF-16 o un UTF-32 lo niega, como el IDE (A28
  de la 1.23) -: '' si lo lee; si no, su mensaje, ALinea con la linea que
  nombra (contadas por LF, como TParser; 0 si no nombra ninguna) y ACita con
  su texto, o el fin del fichero si de ahi en adelante no hay nada. Era una
  lista de lineas unida con CRLF: un .fmx de solo CR se juzgaba con otros
  bytes (revisor 2 de la noche, B-2/B-4). Un texto que no cabe en AEnc no se
  juzga aqui (eso lo dice su escritor). Lo preguntan el lint de un form
  (Lsp.Patch.LintDeForm: el de delphi_designer, el que sigue a delphi_edit y
  el que sigue a cada escritura del disenador) y el guardado de un form o un
  estilo (TStyleDoc.Guarda), que con un resultado que no se lee no escribe. }
function ParserDeForm(const ATexto, AEnc: string; out ALinea: Integer;
  out ACita: string): string;
{ El aviso del lint con eso (DSGN-123); '' si el parser lo lee. }
function AvisoDelParserDeForm(const ATexto, AEnc: string): string;

{ La linea (1-based) en la que EL parser del IDE lee las lineas de un
  designer de texto de otra manera que LineasDeForm, que lee la forma en que
  las escribe el IDE (ObjectBinaryToText): un objeto, una propiedad, un item
  o un end que no estan solos en su linea, un valor que acaba en otra linea
  que la que cree el lector, una coleccion que no cierra con 'end>'. Hasta
  el end de la raiz, que es donde el parser se para y donde se para el
  lector (TStyleDoc): lo de detras no lo lee ninguno - ADetras dice su
  primera linea con algo, 0 si no hay, y lo avisa el lint: el IDE lo quita
  al guardar -. 0 si las lee igual, o si el parser no las lee (eso lo dice
  ParserDeForm, con los bytes del fichero). El juez es el recorrido de
  ObjectTextToBinary
  (System.Classes: ConvertObject, ConvertProperty, ConvertValue) con el
  TParser del IDE y su SourceLine, que dice en que linea esta cada cosa; lo
  que ve LineasDeForm tiene que ser eso, linea a linea. Sin el, set escribia
  un Left = 20 nuevo en vez de cambiar el que habia en un form con el '>' de
  una coleccion en su propia linea, que el IDE carga, y contestaba ok (3b del
  censo de jueces, medido en vivo el 18-oct-2026); la puerta del preview
  (Lsp.FormRender) juzga los literales del form por esas mismas lineas. }
function LineaQueElParserLeeDistinta(const ALineas: TArray<string>; out ADetras: Integer): Integer;
{ Con eso, lo que dice de un fichero AFichero quien lo lee o lo escribe por
  lineas: la negativa DSGN-160, o '' si el parser lo lee como LineasDeForm.
  La preguntan TStyleDoc (Lee y JuicioDelParser), el preview y
  check-binding. }
function FormaDistintaDeLineas(const ALineas: TArray<string>; const AFichero: string): string;
{ ...y el aviso del lint: DSGN-161 si no las lee igual, DSGN-162 si hay algo
  detras del end de la raiz; '' si nada. }
function AvisoDeFormaDeLineas(const ALineas: TArray<string>): string;

{ LA sintaxis de una lista de propiedades - 'Prop=valor;Prop2=valor' (props de
  insert y set) o 'Comp.Prop=valor;...' (state de preview) -: los trozos
  separados por ';' FUERA de un literal entre comillas ('a;b' es un valor, y
  '' es una comilla dentro), sin blancos alrededor y sin los vacios. Era
  Split([';']) en preview, que partia en dos un Caption = 'a;b'. Una comilla
  solo abre un literal si EMPIEZA el valor (tras el primer '=' y los
  blancos), o lo empieza un #N (#39'a;b'): en un valor sin comillas es una
  letra mas - Don't save, O'Brien
  (revisor 2 de la noche, M-A: se tragaba el resto de la lista sin decirlo).
  '' si bien; si un literal se abre y no se cierra, la negativa (DSGN-134) y
  ningun trozo. Es la sintaxis de un parametro de la casa, no la de un form:
  cada valor lo juzgan despues set y el parser del IDE (3.10 de la 1.18.0). }
function TrozosDeEstado(const AEspec: string; out ATrozos: TArray<string>): string;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.RegularExpressions,
  System.SyncObjs,
  System.Generics.Collections,
  Lsp.Pascal, // EL identificador: la linea de una propiedad
  Lsp.DesignerForma, // la forma del fichero: texto, TPF0 o recurso
  Lsp.FormRender, // ConversionDelIde: EL conversor, en el ayudante de 32 bits
  Lsp.ShaCache, // Sha256DeBytes: la huella de un binario ya convertido
  Lsp.Texts;

const
  // lo que guardan los textos de binario ya convertidos, en caracteres: al
  // pasarlo se vacia entera
  TOPE_TEXTOS_DE_BINARIO = 32 * 1024 * 1024;

var
  // EL texto de cada binario ya convertido, por la huella de sus bytes: la
  // conversion es funcion de ellos, y cada una lanza el ayudante (~0,1 s). La
  // puerta de literales del juez lee todos los hermanos de un form en cada
  // insert, set o preview: en una carpeta de forms binarios se pagaba uno por
  // hermano y llamada (V71)
  GTextosDeBinario: TDictionary<string, string>;
  GTextosTamano: Int64;
  GTextosLock: TCriticalSection;

function SangriaDeNivel(ANivel: Integer): string;
begin
  Result := StringOfChar(' ', ANivel * 2);
end;

{ El TEXTO de un designer en AK como los bytes que se le dan al parser: los
  que tendria en disco, sin escribir nada - laxo, porque se PREGUNTA al parser
  y lo que no quepa lo dice el escritor -. Lanza si no se puede codificar. LA
  casa de esa conversion: la hacian lint (ParserDeForm) y to-binary, cada uno
  con su EncodeText (test_paisaje lo cazo, run_all de la 1.18.2). Un UTF-32
  iba en UTF-16 (KindParaElParser) para que el parser lo leyera, y el IDE no
  lo lee: el parser lo dice ahora, como el IDE (A28 de la 1.23). }
function TextoParaElParser(const ATexto: string; AK: TEncKind): TArray<Byte>;
begin
  Result := EncodeText(ATexto, AK, False);
end;

// la linea ALinea (1-based) de ALineas como la nombra una respuesta: su texto,
// sin blancos alrededor y hasta 120 caracteres. La de un error del parser y
// la de una forma que no es la del IDE (la cita numerada 'N|texto' es otra
// cosa: Lsp.Mascara.CitaDeLinea)
function ExtractoDeLinea(const ALineas: TArray<string>; ALinea: Integer): string;
begin
  Result := Copy(ALineas[ALinea - 1].Trim, 1, 120);
end;

function ParserDeForm(const ATexto, AEnc: string; out ALinea: Integer;
  out ACita: string): string;
var
  Bytes: TArray<Byte>;
  Lineas: TArray<string>;
begin
  Result := '';
  ACita := '';
  ALinea := 0;
  // con los bytes de su codificacion, tambien un UTF-16 o un UTF-32: el parser
  // los niega, como el IDE (A28 de la 1.23). Un UTF-32 no se juzgaba, y los
  // escritores escribian en uno sin juez (revisor 2 de la noche, B-6)
  var K := ekUtf8Bom;
  if AEnc <> '' then
    K := EncKindOf(AEnc);
  try
    Bytes := TextoParaElParser(ATexto, K); // juzgar el parseo, no escribir
  except
    // un texto que no cabe en AEnc (lo dice su escritor), o una codificacion
    // que no es de texto: no se juzga aqui
    Exit;
  end;
  Result := ErrorDelParserDeForm(Bytes, ALinea);
  if Result = '' then
    Exit;
  if ALinea <= 0 then
  begin
    // un error que no nombra linea (TokenInt y TokenFloat lanzan EConvertError:
    // Tag = 99999999999999999999) se dice asi, no 'el fin del fichero' (B-1)
    ACita := MsgText(SF_DSGN_PARSER_SIN_LINEA);
    Exit;
  end;
  // las lineas como las cuenta TParser: por LF (un CR suelto no parte)
  Lineas := ATexto.Split([#10]);
  // la que nombra; si de ahi en adelante todo esta en blanco, el parser llego
  // al FINAL - con o sin el salto de la ultima linea, la misma cita
  ACita := MsgText(SF_DSGN_PARSER_FIN_DE_FICHERO);
  for var I := ALinea - 1 to High(Lineas) do
    if Lineas[I].Trim <> '' then
    begin
      ACita := ExtractoDeLinea(Lineas, ALinea);
      Break;
    end;
end;

function AvisoDelParserDeForm(const ATexto, AEnc: string): string;
var
  Linea: Integer;
  Cita: string;
begin
  Result := ParserDeForm(ATexto, AEnc, Linea, Cita);
  if Result <> '' then
    Result := MsgFmt(SN_DSGN_PARSER_FMT, [Result, Linea, Cita]);
end;

type
  // el juez y el lector ya no ven lo mismo: se para en la primera linea
  EFormaDistinta = class(Exception);

function LineaQueElParserLeeDistinta(const ALineas: TArray<string>; out ADetras: Integer): Integer;
var
  P: TParser;
  Flujo: TBytesStream;
  Hex: TMemoryStream;
  Juez, Lector: TArray<TLineaForm>;
  Tomada: TArray<Boolean>;
  Mala, I, FinRaiz: Integer;

  // la linea (0-based) del token de ahora
  function Aqui: Integer;
  begin
    Result := P.SourceLine - 1;
  end;

  procedure Distinta(L: Integer);
  begin
    Mala := L;
    raise EFormaDistinta.Create('');
  end;

  // la linea L es de UNA cosa, como la escribe el IDE: si ya era de otra, el
  // lector no la lee como el parser
  procedure Toma(L: Integer; AClase: TClaseLineaForm; ACol: Integer);
  begin
    if (L < 0) or (L > High(Juez)) or Tomada[L] then
      Distinta(L);
    Tomada[L] := True;
    Juez[L].Clase := AClase;
    Juez[L].Coleccion := ACol;
  end;

  // un token que va en la linea L: la cabecera de un objeto o de un item, el
  // nombre de una propiedad y su '='
  procedure EnLaLinea(L: Integer);
  begin
    if Aqui <> L then
      Distinta(Aqui);
  end;

  // el [n] detras de un objeto o de un item (ConvertOrderModifier)
  procedure Orden(L: Integer);
  begin
    if P.Token <> '[' then
      Exit;
    EnLaLinea(L);
    P.NextToken;
    P.CheckToken(toInteger);
    EnLaLinea(L);
    P.NextToken;
    P.CheckToken(']');
    EnLaLinea(L);
    P.NextToken;
  end;

  procedure Propiedad(ACol: Integer; AMarca: Boolean); forward;

  { El valor (ConvertValue) de la propiedad de la linea L, dentro de ACol
    colecciones: la linea de su ultimo token, con el parser en el siguiente.
    Con AMarca, el de una propiedad, las lineas de debajo que ocupa son
    suyas; las de un valor de dentro de una lista son de la lista }
  function Valor(L, ACol: Integer; AMarca: Boolean): Integer;
  var
    Ultimo, K: Integer;
  begin
    if CharInSet(P.Token, [System.Classes.toString, toWString]) then
    begin
      // una cadena, con sus trozos unidos por '+' (CombineString)
      Ultimo := Aqui;
      while P.NextToken = '+' do
      begin
        P.NextToken;
        if not CharInSet(P.Token, [System.Classes.toString, toWString]) then
          P.CheckToken(System.Classes.toString);
        Ultimo := Aqui;
      end;
    end
    else
    begin
      case P.Token of
        toSymbol:
          P.TokenComponentIdent; // Frame1.Edit1: los puntos son del valor
        toInteger, toFloat:
          ;
        '[':
          while P.NextToken <> ']' do
            if P.Token = toEOF then
              P.CheckToken(']');
        '(':
          begin
            P.NextToken;
            while P.Token <> ')' do
              Valor(L, ACol, False);
          end;
        '{':
          begin
            Hex.Clear;
            P.HexToBinary(Hex); // y deja el parser en su '}'
          end;
        '<':
          if not AMarca then
          begin
            // una coleccion dentro de una lista: tambien la escribe el IDE
            // (_Headers de un TTeeGrid, por su DefineProperties: un frame de
            // un proyecto real, medido el 18-oct-2026), y sus lineas son de la lista,
            // como para el lector: se recorre sin tomar ninguna
            P.NextToken;
            while P.Token <> '>' do
            begin
              P.CheckTokenSymbol('item');
              if P.NextToken = '[' then
              begin
                P.NextToken;
                P.CheckToken(toInteger);
                P.NextToken;
                P.CheckToken(']');
                P.NextToken;
              end;
              while not P.TokenSymbolIs('end') do
                Propiedad(ACol + 1, False);
              P.NextToken;
            end;
          end
          else
          begin
            // una coleccion: cada item y su end en su linea, con sus
            // propiedades
            Ultimo := L; // sin items, '<>': en la linea de su propiedad
            P.NextToken;
            while P.Token <> '>' do
            begin
              Ultimo := Aqui;
              P.CheckTokenSymbol('item');
              Toma(Ultimo, clfItem, ACol + 1);
              P.NextToken;
              Orden(Ultimo);
              while not P.TokenSymbolIs('end') do
                Propiedad(ACol + 1, True);
              Ultimo := Aqui;
              Toma(Ultimo, clfFinItem, ACol + 1);
              P.NextToken;
            end;
            // el IDE la cierra en la linea de su ultimo end: 'end>'
            EnLaLinea(Ultimo);
            P.NextToken;
            Exit(Ultimo);
          end;
      else
        P.CheckToken(toSymbol); // lo que el parser no toma por un valor
      end;
      Ultimo := Aqui;
      P.NextToken;
    end;
    if AMarca then
      for K := L + 1 to Ultimo do
        Toma(K, clfValor, ACol);
    Result := Ultimo;
  end;

  // una propiedad (ConvertProperty): su nombre, con sus puntos, y su '=' en
  // su linea. Dos veces en su objeto es la forma del IDE tambien: la escribe
  // una clase con DefineProperties del mismo nombre que una publicada
  // (ImageIndex de una accion FMX, FMX.ActnList; Left y Top de un form FMX:
  // 14 forms de los Samples, medido el 18-oct-2026). Lo que hace set con
  // ellas es de su escritor (TStyleDoc.SetPropTrozos). Sin AMarca, la de un
  // item de una coleccion de dentro de una lista: no toma lineas
  procedure Propiedad(ACol: Integer; AMarca: Boolean);
  var
    L: Integer;
    Nombre: string;
  begin
    L := Aqui;
    P.CheckToken(toSymbol);
    Nombre := P.TokenString;
    P.NextToken;
    while P.Token = '.' do
    begin
      if AMarca then
        EnLaLinea(L);
      P.NextToken;
      P.CheckToken(toSymbol);
      if AMarca then
        EnLaLinea(L);
      Nombre := Nombre + '.' + P.TokenString;
      P.NextToken;
    end;
    P.CheckToken('=');
    if AMarca then
      EnLaLinea(L);
    P.NextToken;
    if not AMarca then
    begin
      Valor(L, ACol, False);
      Exit;
    end;
    Toma(L, clfPropiedad, ACol);
    Juez[L].Prop := Nombre;
    Juez[L].Fin := Valor(L, ACol, True);
  end;

  // un objeto (ConvertObject y ConvertHeader): su cabecera en su linea, sus
  // propiedades, sus hijos y su end
  procedure Objeto;
  var
    L: Integer;
  begin
    L := Aqui;
    if not P.TokenSymbolIs('INHERITED') and not P.TokenSymbolIs('INLINE') then
      P.CheckTokenSymbol('OBJECT');
    Toma(L, clfObjeto, 0);
    P.NextToken;
    P.CheckToken(toSymbol);
    EnLaLinea(L);
    Juez[L].ClaseObj := P.TokenString;
    if P.NextToken = ':' then
    begin
      EnLaLinea(L);
      P.NextToken;
      P.CheckToken(toSymbol);
      EnLaLinea(L);
      Juez[L].Nombre := Juez[L].ClaseObj;
      Juez[L].ClaseObj := P.TokenString;
      P.NextToken;
    end;
    Orden(L);
    while not P.TokenSymbolIs('END') and not P.TokenSymbolIs('OBJECT') and
      not P.TokenSymbolIs('INHERITED') and not P.TokenSymbolIs('INLINE') do
      Propiedad(0, True);
    while not P.TokenSymbolIs('END') do
      Objeto;
    // el de la raiz, el ultimo: ahi se para el parser (ConvertObject)
    FinRaiz := Aqui;
    Toma(FinRaiz, clfFin, 0);
    P.NextToken;
  end;

begin
  Result := 0;
  ADetras := 0;
  FinRaiz := -1;
  SetLength(Juez, Length(ALineas));
  SetLength(Tomada, Length(ALineas));
  for I := 0 to High(Juez) do
  begin
    Juez[I] := Default(TLineaForm);
    Juez[I].Fin := I;
  end;
  Mala := 0;
  P := nil;
  Flujo := nil;
  Hex := TMemoryStream.Create;
  try
    try
      // las lineas como las cuenta TParser, por LF; en UTF-8 con BOM, que
      // lee tal cual
      Flujo := TBytesStream.Create(TextoParaElParser(string.Join(#10, ALineas), ekUtf8Bom));
      P := TParser.Create(Flujo, TFormatSettings.Invariant);
      Objeto;
    except
      on EFormaDistinta do
      begin
        if Mala > High(ALineas) then
          Mala := High(ALineas);
        Exit(Mala + 1);
      end;
      // lo que el parser no lee lo dice ParserDeForm, con los bytes del
      // fichero
      on Exception do
        Exit(0);
    end;
  finally
    P.Free;
    Flujo.Free;
    Hex.Free;
  end;
  // lo que vio el juez, linea a linea, contra lo que lee LineasDeForm: que es
  // cada linea (de una en blanco no cuenta en que coleccion esta), y la
  // primera que no es lo mismo es la que se nombra - un 'end >' antes que la
  // coleccion que no cierra -... hasta el end de la raiz: lo de detras no lo
  // lee el parser, y el lector tampoco (TStyleDoc.Parse)
  Lector := LineasDeForm(ALineas);
  for I := 0 to FinRaiz do
    if (Juez[I].Clase <> Lector[I].Clase) or
       ((Juez[I].Clase <> clfOtra) and (Juez[I].Coleccion <> Lector[I].Coleccion)) then
      Exit(I + 1);
  // ...y de las que si, lo que dicen: el nombre de una propiedad y hasta
  // donde llega su valor, el nombre y la clase de un objeto
  for I := 0 to FinRaiz do
    if ((Juez[I].Clase = clfPropiedad) and
        ((Juez[I].Prop <> Lector[I].Prop) or (Juez[I].Fin <> Lector[I].Fin))) or
       ((Juez[I].Clase = clfObjeto) and
        ((Juez[I].Nombre <> Lector[I].Nombre) or (Juez[I].ClaseObj <> Lector[I].ClaseObj))) then
      Exit(I + 1);
  // ...y lo de detras, que no lee nadie: un end de mas que cerro la raiz
  // antes, o algo pegado detras (en vivo, un frame de Hermes con un end de
  // mas al final; test_designer, dos raices pegadas: manda la primera)
  for I := FinRaiz + 1 to High(ALineas) do
    if ALineas[I].Trim <> '' then
    begin
      ADetras := I + 1;
      Break;
    end;
end;

function FormaDistintaDeLineas(const ALineas: TArray<string>; const AFichero: string): string;
var
  Detras: Integer;
begin
  Result := '';
  var N := LineaQueElParserLeeDistinta(ALineas, Detras);
  if N > 0 then
    Result := MsgFmt(SR_DSGN_FORMA_DISTINTA_FMT, [AFichero, N, ExtractoDeLinea(ALineas, N)]);
end;

function AvisoDeFormaDeLineas(const ALineas: TArray<string>): string;
var
  Detras: Integer;
begin
  Result := '';
  var N := LineaQueElParserLeeDistinta(ALineas, Detras);
  if N > 0 then
    Result := MsgFmt(SN_DSGN_FORMA_DISTINTA_FMT, [N, ExtractoDeLinea(ALineas, N)])
  else if Detras > 0 then
    Result := MsgFmt(SN_DSGN_DETRAS_DE_LA_RAIZ_FMT, [Detras, ExtractoDeLinea(ALineas, Detras)]);
end;

function TrozosDeEstado(const AEspec: string; out ATrozos: TArray<string>): string;
type
  // donde va la entrada: en el nombre, al principio del valor, en un valor
  // de texto suelto o en uno que empezo con comilla (un literal del form)
  TTramo = (ttNombre, ttInicio, ttTexto, ttLiteral);
var
  Tramo: TTramo;
  EnCadena: Boolean;
  Trozo: TStringBuilder;

  procedure Cierra;
  begin
    if Trozo.ToString.Trim <> '' then
      ATrozos := ATrozos + [Trozo.ToString.Trim];
    Trozo.Clear;
    Tramo := ttNombre;
    EnCadena := False;
  end;

begin
  Result := '';
  ATrozos := [];
  Tramo := ttNombre;
  EnCadena := False;
  Trozo := TStringBuilder.Create;
  try
    for var C in AEspec do
    begin
      case Tramo of
        ttNombre:
          if C = '=' then
            Tramo := ttInicio;
        ttInicio:
          if C = '''' then
          begin
            Tramo := ttLiteral;
            EnCadena := True;
          end
          // un literal del form tambien empieza por un caracter #N (#39'a;b',
          // #13#10'x'): el ';' de su cadena no parte (revisor 3, B-4)
          else if C = '#' then
            Tramo := ttLiteral
          else if C > ' ' then
            Tramo := ttTexto;
        ttLiteral:
          // '' dentro de una cadena son dos cambios: sigue dentro
          if C = '''' then
            EnCadena := not EnCadena;
      end;
      if (C = ';') and not EnCadena then
      begin
        Cierra;
        Continue;
      end;
      Trozo.Append(C);
    end;
    if EnCadena then
    begin
      Result := MsgFmt(SR_DESIGNER_COMILLA_SIN_CERRAR_FMT, [Trozo.ToString.Trim]);
      ATrozos := [];
      Exit;
    end;
    Cierra;
  finally
    Trozo.Free;
  end;
end;

function TrozosDeLiteral(const S: string): TArray<string>;
const
  LARGO_DE_LINEA = 64; // el LineLength de ObjectBinaryToText
var
  I, J, K, L: Integer;
  Trozo: string;
  Corta: Boolean;
begin
  Result := [''''''];
  L := Length(S);
  if L = 0 then
    Exit;
  Result := [];
  // el bucle de ObjectBinaryToText (vaWString): K, donde empieza la linea,
  // en caracteres del TEXTO, no de lo escrito
  Trozo := '';
  I := 1;
  K := 1;
  repeat
    Corta := False;
    if (S[I] >= ' ') and (S[I] <> '''') and (Ord(S[I]) <= 127) then
    begin
      J := I;
      repeat
        Inc(I);
      until (I > L) or (S[I] < ' ') or (S[I] = '''') or (I - K >= LARGO_DE_LINEA) or
        (Ord(S[I]) > 127);
      if I - K >= LARGO_DE_LINEA then
        Corta := True;
      Trozo := Trozo + '''' + Copy(S, J, I - J) + '''';
    end
    else
    begin
      Trozo := Trozo + '#' + IntToStr(Ord(S[I]));
      Inc(I);
      if I - K >= LARGO_DE_LINEA then
        Corta := True;
    end;
    if Corta and (I <= L) then
    begin
      Result := Result + [Trozo + ' +'];
      Trozo := '';
      K := I;
    end;
  until I > L;
  Result := Result + [Trozo];
end;

function SueltoEnLiteral(const ATexto: string; const AAntes: string): string;
var
  Nuevo: string;
begin
  Result := '';
  // el literal lo escribe #N en cualquier fichero: el suelto vuelve igual, y
  // se cuenta como en UTF-16, que lo guarda tal cual (solo cuenta por valor)
  Nuevo := SustitutoNuevo(ATexto, AAntes, ekUtf16LE);
  if Nuevo <> '' then
    Result := MsgFmt(SR_DSGN_LITERAL_SUELTO_FMT,
      [MsgFmt(SF_EDIT_SUSTITUTO_SUELTO_FMT, [IntToHex(Ord(Nuevo[1]), 4)])]);
end;

function LineasDePropiedad(const ASangria, AProp: string; const ATrozos: TArray<string>): TArray<string>;
begin
  // el IDE escribe ' = ' y, si hay varios trozos, salta de linea: la de la
  // propiedad acaba en blanco
  Result := [ASangria + AProp + ' = '];
  if Length(ATrozos) = 1 then
    Result[0] := Result[0] + ATrozos[0];
  if Length(ATrozos) <= 1 then
    Exit;
  for var T in ATrozos do
    Result := Result + [ASangria + '  ' + T];
end;

function LeeLiteralDeForm(const AValor: string; out ATexto: string): Boolean;
var
  S, Codigo: string;
  I, N, J, V: Integer;

  procedure Blancos;
  begin
    while (I <= N) and CharInSet(S[I], [' ', #9]) do
      Inc(I);
  end;

  // tramos entre comillas y #N pegados, sin nada entre ellos: UN token del
  // TParser
  function Pieza: Boolean;
  begin
    Result := False;
    while (I <= N) and CharInSet(S[I], ['''', '#']) do
    begin
      if S[I] = '''' then
      begin
        Inc(I);
        while True do
        begin
          if I > N then
            Exit(False); // sin cerrar
          if S[I] = '''' then
          begin
            if (I < N) and (S[I + 1] = '''') then
            begin
              ATexto := ATexto + '''';
              Inc(I, 2);
              Continue;
            end;
            Inc(I);
            Break;
          end;
          ATexto := ATexto + S[I];
          Inc(I);
        end;
      end
      else
      begin
        Inc(I);
        J := I;
        if (I <= N) and (S[I] = '$') then
        begin
          Inc(I);
          while (I <= N) and CharInSet(S[I], ['0'..'9', 'A'..'F', 'a'..'f']) do
            Inc(I);
        end
        else
          while (I <= N) and CharInSet(S[I], ['0'..'9']) do
            Inc(I);
        Codigo := Copy(S, J, I - J);
        if not TryStrToInt(Codigo, V) or (V < 0) or (V > $FFFF) then
          Exit(False);
        ATexto := ATexto + Char(V);
      end;
      Result := True;
    end;
  end;

begin
  ATexto := '';
  S := AValor.Trim;
  N := Length(S);
  I := 1;
  if not Pieza then
    Exit(False);
  // y trozos unidos con '+', que el TParser une (CombineString)
  while True do
  begin
    Blancos;
    if I > N then
      Exit(True);
    if S[I] <> '+' then
      Exit(False);
    Inc(I);
    Blancos;
    if not Pieza then
      Exit(False);
  end;
end;

function EsLiteralDeForm(const AValor: string): Boolean;
var
  T: string;
begin
  Result := LeeLiteralDeForm(AValor, T);
end;

function NombreDeValor(const AValor: string): string;
var
  T: string;
begin
  Result := AValor.Trim;
  if LeeLiteralDeForm(Result, T) then
    Result := T;
end;

function EsCaracterDeForm(const AValor: string): Boolean;
var
  T: string;
begin
  Result := LeeLiteralDeForm(AValor, T) and (Length(T) = 1);
end;

{ La forma de numero de un valor que el parser no CONVIERTE: el tipo con que
  lo escribiria por la forma que le ve su TOKENIZADOR (TParser) - entero, coma
  flotante, o el de su sufijo s/c/d -, si Val lo lee entero: lo que esta bien
  escrito y solo no cabe (1E400 da INF y codigo 0; 1e y 1e+ dan otro codigo,
  y TokenFloat lanza el mismo EConvertError para los tres: medido el
  18-oct-2026). False si no es un numero bien escrito. }
function FormaDeNumero(const AValor: string; out ATipo: TValueType): Boolean;
var
  Flujo: TStringStream;
  P: TParser;
  V: string;
  D: Double;
  Codigo: Integer;
begin
  Result := False;
  ATipo := vaNull;
  Val(AValor, D, Codigo);
  if Codigo <> 0 then
    Exit;
  V := AValor;
  if V.StartsWith('-') then
    V := V.Substring(1); // el signo lo lee ConvertValue, delante del numero
  Flujo := TStringStream.Create(V, TEncoding.ASCII);
  try
    try
      P := TParser.Create(Flujo);
      try
        case P.Token of
          toInteger: ATipo := vaInt64;
          toFloat:
            case UpCase(P.FloatType) of
              'S': ATipo := vaSingle;
              'C': ATipo := vaCurrency;
              'D': ATipo := vaDate;
            else
              ATipo := vaExtended;
            end;
        else
          Exit;
        end;
        Result := P.NextToken = toEOF;
      finally
        P.Free;
      end;
    except
      Result := False;
    end;
  finally
    Flujo.Free;
  end;
end;

{ Como deja EL parser del IDE (ObjectTextToBinary, por DesignerAFlujo) AValor
  puesto como valor de una propiedad: el TValueType que escribe en el binario.
  False si no lo lee, si no es de UNA linea o si se lleva algo detras (la
  propiedad que le sigue, un centinela, tiene que llegar entera). Lo que el
  IDE escribe y lee no lo dice una gramatica nuestra: un TDate como lo escribe
  el IDE, 45123.5d, era "not a one-line form value" (DSGN-092; 3 en los .dfm
  de los Samples; lote 3 del censo de jueces, 18-oct-2026). }
function TipoDeValorDeForm(const AValor: string; out ATipo: TValueType): Boolean;
const
  CENTINELA = 'Z';
var
  V: string;
  Entrada: TBytesStream;
  Binario: TMemoryStream;
  R: TReader;
  Flags: TFilerFlags;
  Pos: Integer;
begin
  Result := False;
  ATipo := vaNull;
  V := AValor.Trim;
  if (V = '') or (V.IndexOfAny([#10, #13]) >= 0) then
    Exit;
  Entrada := nil;
  Binario := TMemoryStream.Create;
  try
    try
      // las dos lineas por SU escritor (LineasDePropiedad), como el IDE
      Entrada := TBytesStream.Create(TextoParaElParser('object A: TA'#13#10 +
        LineasDePropiedad(SangriaDeNivel(1), 'P', [V])[0] + #13#10 +
        LineasDePropiedad(SangriaDeNivel(1), CENTINELA, ['0'])[0] + #13#10'end'#13#10, ekUtf8Bom));
      DesignerAFlujo(Entrada, Binario);
      Binario.Position := 0;
      R := TReader.Create(Binario, 4096);
      try
        R.ReadSignature;
        Flags := [];
        Pos := 0;
        R.ReadPrefix(Flags, Pos);
        R.ReadStr; // la clase
        R.ReadStr; // el nombre
        if R.ReadStr <> 'P' then
          Exit;
        ATipo := R.NextValue;
        R.SkipValue;
        Result := not R.EndOfList and (R.ReadStr = CENTINELA);
      finally
        R.Free;
      end;
    except
      // un numero que el parser no CONVIERTE (TokenInt y TokenFloat lanzan
      // EConvertError: 1E400, 99999999999999999999) tiene su forma, la de su
      // tokenizador; que no cabe lo dice luego quien lo convierte (set, con el
      // tope de su tipo: "a number its type holds"). Lo demas, no lo lee
      on EConvertError do
        Result := FormaDeNumero(V, ATipo);
      on Exception do
        Result := False;
    end;
  finally
    Binario.Free;
    Entrada.Free;
  end;
end;

function EsNumeroDeForm(const AValor: string): Boolean;
var
  T: TValueType;
begin
  Result := TipoDeValorDeForm(AValor, T) and
    (T in [vaInt8, vaInt16, vaInt32, vaInt64, vaExtended, vaDouble, vaSingle, vaCurrency, vaDate]);
end;

function EsEnteroDeForm(const AValor: string): Boolean;
var
  T: TValueType;
begin
  Result := TipoDeValorDeForm(AValor, T) and (T in [vaInt8, vaInt16, vaInt32, vaInt64]);
end;

function EsNumeroDeFloat(const AValor: string): Boolean;
var
  T: TValueType;
begin
  Result := TipoDeValorDeForm(AValor, T) and
    (T in [vaInt8, vaInt16, vaInt32, vaInt64, vaExtended, vaDouble]);
end;

// una linea que sigue una cadena: un trozo empieza por comilla o por #
function EsTrozoDeCadena(const ALinea: string): Boolean;
var
  T: string;
begin
  T := ALinea.TrimLeft;
  Result := T.StartsWith('''') or T.StartsWith('#');
end;

{ La ultima linea (0-based) del valor que empieza en la linea AIni con el
  texto AValor (lo de detras del '='): una lista entre parentesis, un bloque
  binario entre llaves, una cadena partida en trozos que acaban en '+' - o
  la larga que el IDE empieza en la linea de debajo, con la de la propiedad
  en blanco. Una coleccion la lleva LineasDeForm, que ve sus items. }
function FinDeValor(const ALineas: TArray<string>; AIni: Integer; const AValor: string): Integer;
var
  T, Cierre: string;
  Tope, Nivel, K: Integer;
begin
  Result := AIni;
  Tope := High(ALineas);
  if (AValor = '(') or ((AValor <> '') and (AValor[1] = '{') and not AValor.EndsWith('}')) then
  begin
    Cierre := IfThen(AValor = '(', ')', '}');
    Nivel := 1;
    while Result < Tope do
    begin
      // uno sin cerrar no se lleva el end de su objeto
      if SameText(ALineas[Result + 1].Trim, 'end') then
        Exit;
      Inc(Result);
      T := ALineas[Result].Trim;
      if Cierre = '}' then
      begin
        if T.EndsWith(Cierre) then
          Exit;
        Continue;
      end;
      // una lista dentro de la lista: el IDE la abre con un '(' en su propia
      // linea y cierra cada una con un ')' detras de su ultimo elemento
      // (ObjectBinaryToText, vaList); una vacia, '()', se cierra sola. Se
      // cerraba en la primera linea acabada en ')', la de la de dentro (3b
      // del censo de jueces, 1.20.2)
      if T = '(' then
        Inc(Nivel)
      else
      begin
        K := Length(T);
        while (K > 0) and (T[K] = ')') do
          Dec(K);
        Dec(Nivel, Length(T) - K);
        if T.StartsWith('(') then
          Inc(Nivel);
        if Nivel <= 0 then
          Exit;
      end;
    end;
    Exit;
  end;
  T := AValor;
  if T = '' then
  begin
    if (Result >= Tope) or not EsTrozoDeCadena(ALineas[Result + 1]) then
      Exit;
    Inc(Result);
    T := ALineas[Result].Trim;
  end;
  while T.EndsWith('+') and (Result < Tope) and EsTrozoDeCadena(ALineas[Result + 1]) do
  begin
    Inc(Result);
    T := ALineas[Result].Trim;
  end;
end;

function LineaDePropiedad(const ALinea: string; out AProp, AValor: string): Boolean;
var
  M: TMatch;
begin
  AProp := '';
  AValor := '';
  M := TRegEx.Match(ALinea.Trim, '^(' + PATRON_IDENT_PUNTOS + ')\s*=\s*(.*)$');
  Result := M.Success;
  if Result then
  begin
    AProp := M.Groups[1].Value;
    AValor := M.Groups[2].Value.Trim;
  end;
end;

function LineasDeForm(const ALineas: TArray<string>): TArray<TLineaForm>;
var
  I, K, Fin: Integer;
  T: string;
  Pila: TStack<Integer>; // la linea de la propiedad de cada coleccion abierta
  R: TLineaForm;
begin
  SetLength(Result, Length(ALineas));
  Pila := TStack<Integer>.Create;
  try
    I := 0;
    while I <= High(ALineas) do
    begin
      T := ALineas[I].Trim;
      R := Default(TLineaForm);
      R.Coleccion := Pila.Count;
      R.Fin := I;
      if T = '' then
        R.Clase := clfOtra
      else if Pila.Count > 0 then
      begin
        // dentro de una coleccion: 'item' (o 'item [2]'), sus propiedades,
        // 'end' y, el ultimo, 'end>', que la cierra
        if TRegEx.IsMatch(T, '^item(?:\s*\[[^\]]*\])?$', [roIgnoreCase]) then
          R.Clase := clfItem
        else if SameText(T, 'end') then
          R.Clase := clfFinItem
        else if SameText(T, 'end>') then
        begin
          R.Clase := clfFinItem;
          Result[Pila.Pop].Fin := I;
        end
        else if LineaDePropiedad(T, R.Prop, R.Valor) then
          R.Clase := clfPropiedad;
      end
      else if LineaDeObjeto(T, R.Clave, R.Nombre, R.ClaseObj) then
        R.Clase := clfObjeto
      else if SameText(T, 'end') then
        R.Clase := clfFin
      else if LineaDePropiedad(T, R.Prop, R.Valor) then
        R.Clase := clfPropiedad;
      Result[I] := R;
      if R.Clase = clfPropiedad then
        if R.Valor = '<' then
          Pila.Push(I) // su Fin, en su '>'
        else if R.Valor <> '<>' then
        begin
          Fin := FinDeValor(ALineas, I, R.Valor);
          Result[I].Fin := Fin;
          for K := I + 1 to Fin do
          begin
            Result[K] := Default(TLineaForm);
            Result[K].Clase := clfValor;
            Result[K].Coleccion := Pila.Count;
            Result[K].Fin := K;
          end;
          I := Fin;
        end;
      Inc(I);
    end;
  finally
    Pila.Free;
  end;
end;

function ValorEnteroDe(const ALineas: TArray<string>; const AForm: TArray<TLineaForm>;
  AIni: Integer): string;
begin
  Result := AForm[AIni].Valor;
  // solo una cadena partida: lo demas de varias lineas se queda en su marca
  if (AForm[AIni].Fin = AIni) or ((Result <> '') and not Result.EndsWith('+')) then
    Exit;
  for var K := AIni + 1 to AForm[AIni].Fin do
    Result := Trim(Result + ' ' + ALineas[K].Trim);
end;

function ElementosDeLista(const ALineas: TArray<string>; AIni, AFin: Integer): TArray<string>;
var
  Elem, T: string;
begin
  Result := [];
  Elem := '';
  for var K := AIni + 1 to AFin do
  begin
    T := ALineas[K].Trim;
    // la lista de dentro se abre con '(' (FinDeValor) y se cierra con ')'
    // detras de su ultimo elemento, como la de fuera: un literal empieza por
    // comilla, # o digito y acaba en comilla o digito, nunca en un parentesis
    while T.StartsWith('(') do
      T := T.Substring(1).TrimLeft;
    while T.EndsWith(')') do
      T := T.Substring(0, T.Length - 1).TrimRight;
    if T = '' then
      Continue;
    Elem := Trim(Elem + ' ' + T);
    // una cadena larga, en trozos que acaban en '+' (como ValorEnteroDe)
    if Elem.EndsWith('+') then
      Continue;
    Result := Result + [Elem];
    Elem := '';
  end;
  if Elem <> '' then
    Result := Result + [Elem];
end;

function EsValorDeBloque(const AValor: string): Boolean;
begin
  Result := (AValor <> '') and CharInSet(AValor[1], ['(', '<', '{']);
end;

function ReferenciasDeObjeto(const AForm: TArray<TLineaForm>; AObj: Integer): TArray<string>;
var
  I: Integer;
begin
  Result := [];
  for I := AObj + 1 to High(AForm) do
  begin
    if AForm[I].Clase in [clfObjeto, clfFin] then
      Break;
    if (AForm[I].Clase = clfPropiedad) and (AForm[I].Coleccion = 0) and
       EsIdentificador(AForm[I].Valor, True) then
      Result := Result + [AForm[I].Prop + '=' + AForm[I].Valor];
  end;
end;

{ Las cifras EXACTAS de un Double positivo, sin ceros delante ni detras, y
  AX con V = 0,ACifras x 10^AX: su mantisa por su potencia de 2, en decimal
  (por 2, o por 5 con la coma AX sitios a la izquierda). Este servidor es de
  64 bits y su FloatToStrF no sirve para esto: con 16 cifras trunca (0.4 en
  Single daba ...4644) y con 17 se equivoca (0.7 en Single, ...7105, y es
  ...710449; medido el 7-oct-2026). }
procedure CifrasExactas(const V: Double; out ACifras: string; out AX: Integer);
var
  Bits, M: UInt64;
  Exp, K, I: Integer;
  Cif: TArray<Byte>; // al reves: Cif[0] son las unidades

  procedure Multiplica(F: Integer);
  var
    J, P, Lleva: Integer;
  begin
    Lleva := 0;
    for J := 0 to High(Cif) do
    begin
      P := Cif[J] * F + Lleva;
      Cif[J] := P mod 10;
      Lleva := P div 10;
    end;
    while Lleva > 0 do
    begin
      SetLength(Cif, Length(Cif) + 1);
      Cif[High(Cif)] := Lleva mod 10;
      Lleva := Lleva div 10;
    end;
  end;

begin
  Move(V, Bits, SizeOf(Bits));
  Exp := (Bits shr 52) and $7FF;
  M := Bits and $FFFFFFFFFFFFF;
  if Exp = 0 then
    Exp := -1074
  else
  begin
    M := M or (UInt64(1) shl 52);
    Exp := Exp - 1075;
  end;
  Cif := [];
  repeat
    SetLength(Cif, Length(Cif) + 1);
    Cif[High(Cif)] := M mod 10;
    M := M div 10;
  until M = 0;
  K := 0;
  if Exp >= 0 then
    for I := 1 to Exp do
      Multiplica(2)
  else
  begin
    K := -Exp;
    for I := 1 to K do
      Multiplica(5);
  end;
  SetLength(ACifras, Length(Cif));
  for I := 0 to High(Cif) do
    ACifras[Length(Cif) - I] := Chr(Ord('0') + Cif[I]);
  AX := Length(ACifras) - K;
  while (Length(ACifras) > 1) and (ACifras[Length(ACifras)] = '0') do
    Delete(ACifras, Length(ACifras), 1);
end;

// ACifras a ANum cifras: la siguiente decide, hacia arriba desde 5
procedure RedondeaCifras(var ACifras: string; var AX: Integer; ANum: Integer);
var
  K: Integer;
  Sube: Boolean;
begin
  if Length(ACifras) <= ANum then
    Exit;
  Sube := ACifras[ANum + 1] >= '5';
  ACifras := Copy(ACifras, 1, ANum);
  if not Sube then
    Exit;
  K := ANum;
  while (K >= 1) and (ACifras[K] = '9') do
  begin
    ACifras[K] := '0';
    Dec(K);
  end;
  if K >= 1 then
    ACifras[K] := Chr(Ord(ACifras[K]) + 1)
  else
  begin
    ACifras := '1' + Copy(ACifras, 1, ANum - 1);
    Inc(AX);
  end;
end;

function FlotanteDeForm(const AValor: Extended; ASimple: Boolean): string;
var
  V: Double;
  Digitos, Ent, Frac: string;
  X, N: Integer;
begin
  V := AValor;
  if ASimple then
    V := Single(AValor);
  if V = 0 then
    Exit('0.' + StringOfChar('0', 18));
  CifrasExactas(Abs(V), Digitos, X);
  // como el IDE de 32 bits (el que manda; David, 7-oct-2026): las 18 cifras
  // que da su FPU (FBSTP) y de ahi FloatToStrF(V, ffFixed, 16, 18) - 16
  // cifras, sin pasar del decimal 18 (el 0.000001339281197943 de un .fmx de
  // ejemplo se corta en el decimal, no en la cifra). Medido contra los 80
  // valores distintos de los .fmx de ejemplo de 13.1: salen todos; el paso
  // de 18 cifras es como las saca la RTL de 32 bits, y ninguno de esos 80 lo
  // distingue (una guarda, no una medida)
  RedondeaCifras(Digitos, X, 18);
  N := 18 + X;
  if N > 16 then
    N := 16;
  // bajo el decimal 18 se redondea EN el: de 5E-19 sale el ultimo
  // (0.000000000000000001), y de menos, cero y sin signo (lo decia el
  // revisor de la 1.17.0 leyendo la RTL de 32 bits: aqui salia cero)
  if N < 0 then
    Exit('0.' + StringOfChar('0', 18));
  RedondeaCifras(Digitos, X, N);
  if Digitos = '' then
    Exit('0.' + StringOfChar('0', 18));
  // con mas de 16 cifras enteras FloatToStrF pasa a la forma general:
  // 1E20, 1.000000020040877E20
  if X > 16 then
  begin
    while (Length(Digitos) > 1) and (Digitos[Length(Digitos)] = '0') do
      Delete(Digitos, Length(Digitos), 1);
    Result := Digitos[1];
    if Length(Digitos) > 1 then
      Result := Result + '.' + Copy(Digitos, 2, MaxInt);
    Result := Result + 'E' + IntToStr(X - 1);
    if V < 0 then
      Result := '-' + Result;
    Exit;
  end;
  if X > 0 then
  begin
    while Length(Digitos) < X do
      Digitos := Digitos + '0';
    Ent := Copy(Digitos, 1, X);
    Frac := Copy(Digitos, X + 1, MaxInt);
  end
  else
  begin
    Ent := '0';
    Frac := StringOfChar('0', -X) + Digitos;
  end;
  Result := Ent + '.' + Frac + StringOfChar('0', 18 - Length(Frac));
  if V < 0 then
    Result := '-' + Result;
end;

function FlotanteFmx(N: Integer): string;
begin
  Result := FlotanteDeForm(N, True);
end;

function NombreQueElFicheroNoLee(const ANombre, ADfm, ADfmEnc, APas, APasEnc: string): string;
begin
  Result := '';
  if IsAscii(ANombre) then
    Exit;
  if EncKindOf(ADfmEnc) <> ekUtf8Bom then
    Exit(MsgFmt(SR_DESIGNER_NOMBRE_SIN_BOM_FMT, [ANombre, ExtractFileName(ADfm),
      MsgText(SF_DESIGNER_SIN_BOM_FORM)]));
  if EncKindOf(APasEnc) = ekUtf8 then
    Exit(MsgFmt(SR_DESIGNER_NOMBRE_SIN_BOM_FMT, [ANombre, ExtractFileName(APas),
      MsgText(SF_DESIGNER_SIN_BOM_UNIDAD)]));
end;

function IsBinaryDesignerBytes(const ABytes: TBytes): Boolean;
begin
  Result := DesignerShapeOf(ABytes) <> dsText;
end;

function IsBinaryDesignerFile(const APath: string): Boolean;
begin
  // su cabecera por EL lector de cabeceras (con menos de cuatro bytes, o sin
  // poder abrirlo, texto: DesignerShapeOf)
  Result := IsBinaryDesignerBytes(PrimerosBytes(APath, 4));
end;

function DesignerBinaryToText(const ABytes: TBytes; out AText: string): string;
var
  Huella, Clase, Mensaje: string;
  Salida: TBytes;
  Linea: Integer;
begin
  Result := '';
  AText := '';
  if DesignerShapeOf(ABytes) = dsText then
    Exit(MsgText(SR_DSGN_NO_ES_DESIGNER_BINARIO));
  Huella := Sha256DeBytes(ABytes);
  GTextosLock.Enter;
  try
    if GTextosDeBinario.TryGetValue(Huella, AText) then
      Exit;
  finally
    GTextosLock.Leave;
  end;
  // EL conversor de la casa (Lsp.DesignerForma) en el ayudante de 32 bits, el
  // proceso del IDE (V71); aqui, sus mensajes
  Result := ConversionDelIde(ABytes, True, Salida, Clase, Mensaje, Linea);
  if Result <> '' then
    Exit;
  if (Clase <> '') or (Mensaje <> '') then
    Exit(MsgFmt(SR_DSGN_BINARIO_DANADO_FMT, [Clase, Mensaje]));
  AText := TEncoding.UTF8.GetString(Salida);
  GTextosLock.Enter;
  try
    if GTextosTamano + Length(AText) > TOPE_TEXTOS_DE_BINARIO then
    begin
      GTextosDeBinario.Clear;
      GTextosTamano := 0;
    end;
    if not GTextosDeBinario.ContainsKey(Huella) then
    begin
      GTextosDeBinario.Add(Huella, AText);
      Inc(GTextosTamano, Length(AText));
    end;
  finally
    GTextosLock.Leave;
  end;
end;

function DesignerFileToText(const APath: string; out AText: string): string;
begin
  AText := '';
  if not TFile.Exists(APath) then
    Exit(MsgFmt(SR_NO_EXISTE_FMT, [APath]));
  Result := DesignerBinaryToText(TFile.ReadAllBytes(APath), AText);
end;

function FormAncho(const APath: string; out AK: TEncKind): Boolean;
begin
  AK := ekAnsi;
  // los cuatro primeros bytes bastan, el BOM mas largo (el de UTF-32): leer
  // el fichero entero eran dos lecturas completas en lint (revisor propio de r5)
  Result := KindDeBom(PrimerosBytes(APath, 4), AK) and (AK in ENC_ANCHAS);
end;

function NotaDeFormAncho(const ANombre, AEnc: string): string;
begin
  Result := '';
  if EncKindOf(AEnc) in ENC_ANCHAS then
    Result := MsgFmt(SN_DSGN_FORM_ANCHO_FMT, [ANombre, AEnc]);
end;

function TextoDeFormAncho(const ABytes: TBytes; out AText: string): string;
var
  K: TEncKind;
  Bin: TBytes;
  Decodificado: string;
begin
  AText := '';
  if not KindDeBom(ABytes, K) then
    K := ekAnsi;
  try
    Decodificado := DecodeBytes(ABytes, K);
  except
    on E: Exception do
      Exit(MsgFmt(SR_DSGN_NO_PUDE_CONVERTIR_BINARIO_FMT, [E.ClassName, E.Message]));
  end;
  // medio caracter: el parser lo leeria en UTF-8 como U+FFFD y el texto
  // llevaria otro caracter sin decirlo (R7 del revisor propio del punto 4 de
  // la 1.18.2, entonces en to-binary)
  var I := 1;
  var Suelto := SiguienteSuelto(Decodificado, I);
  if Suelto <> #0 then
    Exit(MsgFmt(SR_DSGN_FORM_SUELTO_BINARIO_FMT,
      [MsgFmt(SF_EDIT_SUSTITUTO_SUELTO_FMT, [IntToHex(Ord(Suelto), 4)]),
       LineaDePosicion(Decodificado, I - 1)]));
  // al parser en UTF-8 con BOM, que lee todos sus caracteres, y de ahi, por EL
  // conversor del IDE, el texto que el IDE escribe al guardar (A28 de la 1.23)
  Result := DesignerTextToBinary(TextoParaElParser(Decodificado, ekUtf8Bom), Bin);
  if Result = '' then
    Result := DesignerBinaryToText(Bin, AText);
end;

function DesignerTextToBinary(const ATexto: TBytes; out ABytes: TBytes): string;
var
  Lineas: TStringList;
  K: TEncKind;
  Clase, Mensaje: string;
  LineaDelError: Integer;
begin
  ABytes := nil;
  // Los BYTES de disco, TAL CUAL, al parser del IDE: el decide (norma 6). Aqui
  // habia un camino propio - el texto ya decodificado, recodificado a ANSI -
  // que negaba (DSGN-045) un UTF-8 con BOM que dcc compila entero, y que
  // dependia de como decodificara quien llama (M2, punto 4 de la 1.18.2,
  // medido el 13-oct contra el exe de dcc: 'ok ✔ Ж' entra entero con BOM;
  // 'Configuración' SIN BOM sale con la ó partida en dos letras -C3 B3 leidos
  // como ANSI-, como ya salia por el servidor). Un form ancho (UTF-16 /
  // UTF-32) se pasaba antes a UTF-8 o a UTF-16 y se convertia, y el IDE no lo
  // carga: lo niega quien llama (FormAnchoQueNoCarga; A28 de la 1.23). Y en
  // el ayudante de 32 bits, el proceso del IDE: aqui el valor de un flotante,
  // redondeado a Double, eran otros bytes (V71)
  Result := ConversionDelIde(ATexto, False, ABytes, Clase, Mensaje, LineaDelError);
  if (Result <> '') or ((Clase = '') and (Mensaje = '')) then
    Exit;
  // si no lo lee y es por un NOMBRE con letras fuera de ASCII (BotonÑ, de un
  // objeto, de su clase o de una propiedad) en un form que el parser lee en
  // ANSI - salia su 'Identifier expected', y dcc si lo lee guardandolo en
  // UTF-8 (medido 9-oct, 4.1 de la 1.18.0) -, se dice cual, donde y por que.
  // Solo cuando el parser ya dijo que no: antes se miraba primero y se negaba
  // lo que el parser si lee (un UTF-8 con BOM). Y solo SIN BOM y con el
  // nombre en la linea que el parser nombra (la da el ayudante, leida con el
  // formato del mensaje en SU idioma): con BOM el parser lee esos nombres
  // (TParser en UTF-8), y un error de otra linea (una cadena sin cerrar)
  // quedaba tapado por DSGN-120 (R2 del revisor propio del punto 4 de la
  // 1.18.2). Decodificado como lo lee el parser: la ANSI de la maquina
  if KindDeBom(ATexto, K) or (LineaDelError <= 0) then
    Exit(MsgFmt(SR_DSGN_NO_PUDE_CONVERTIR_BINARIO_FMT, [Clase, Mensaje]));
  Lineas := TStringList.Create;
  try
    try
      Lineas.Text := DecodeBytes(ATexto, ekAnsi);
    except
      Lineas.Clear; // lo que no se decodifica no nombra nada: el mensaje del parser
    end;
    var Fm := LineasDeForm(Lineas.ToStringArray);
    var I := LineaDelError - 1;
    if I <= High(Fm) then
    begin
      var Nombre := '';
      if (Fm[I].Clase = clfObjeto) and not IsAscii(Fm[I].Nombre) then
        Nombre := Fm[I].Nombre
      else if (Fm[I].Clase = clfObjeto) and not IsAscii(Fm[I].ClaseObj) then
        Nombre := Fm[I].ClaseObj
      else if (Fm[I].Clase = clfPropiedad) and not IsAscii(Fm[I].Prop) then
        Nombre := Fm[I].Prop;
      if Nombre <> '' then
        Exit(MsgFmt(SR_DSGN_NOMBRE_NO_ASCII_BINARIO_FMT, [Nombre, I + 1]));
    end;
  finally
    Lineas.Free;
  end;
  Result := MsgFmt(SR_DSGN_NO_PUDE_CONVERTIR_BINARIO_FMT, [Clase, Mensaje]);
end;

initialization
  GTextosDeBinario := TDictionary<string, string>.Create;
  GTextosLock := TCriticalSection.Create;

finalization
  GTextosLock.Free;
  GTextosDeBinario.Free;

end.
