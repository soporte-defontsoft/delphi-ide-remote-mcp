unit Lsp.JuicioDeForms;

{ EL JUICIO de un form de texto: su lint (la tabla del framework, el parser
  y el lector del IDE, los estilos, el binding) y lo que se dice tras escribir
  uno (JuicioDeLoEscrito, aplazable en una tanda o un changeset), la nota de
  su codificacion y la de un fuente o un form en UTF-8 sin BOM, la codificacion
  en que nace uno nuevo, y los designers de una unidad. Vivia en Lsp.Patch
  (V94 de la depuracion de la 1.23, B6 de la 1.28): se mudo sin cambiar una
  linea. }

interface

uses
  Lsp.Codificacion,
  Lsp.DesignerMeta; // TFaltaTabla y su espera: el lint de un form (LintDeForm)

{ Los designers que puede tener una unidad: uno por DESIGNER_EXTS, al lado y
  con su mismo nombre (la regla del IDE), existan o no, en el orden de la
  lista. La inversa de UnidadDeDesigner (Lsp.DesignerForma): la componian a
  mano, extension a extension, Mcp.Tools.FileOps (el borrado, el mover y su
  gemelo) y Lsp.ProjectUnits (2.2 de la 1.18.0). Y DETRAS del par (quien busca
  el primero que exista sigue dando el maestro), sus VISTAS FMX: las que declara
  su texto (VistasDeUnidad), leido de ATextoDe si se da - tras mover o borrar,
  la unidad ya no esta donde estaba - y si no, de AUnidad (V122 de la 1.23.1). }
function DesignersDeUnidad(const AUnidad: string; const ATextoDe: string = ''): TArray<string>;
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
    // ...y si lleva un frame en linea: esa carga tampoco la juzga ninguna tabla
    // y va al lector aunque no haya lineas (LlevaFrameInline; PorQueAlLector)
    FrameInline: Boolean;
    Lector: TArray<string>;
    SinLector: string;
    // los StyleLookup de un form FMX que ningun estilo que ve define: una
    // nota (DSGN-175), no un aviso (V75 de la 1.23.1)
    Lookups: TArray<string>;
    // los colores de menos de 8 cifras, por el escritor del IDE: una nota
    // (DSGN-176), solo con ALector (V154 de la 1.23.1)
    Colores: TArray<string>;
    // los literales que preview negaria: una nota (DSGN-183); el form es valido
    Literales: TArray<string>;
    // los StyleLookup que no se juzgan: toman sus estilos de un StyleBook que no
    // se lee, o son de un frame (LookupsDeDesigner). Solo con ALector (V156 de la 1.24)
    LookupsSinJuzgar: Integer;
  end;

{ El lint del form ADfm con el TEXTO ATexto (lo que dice o dira el disco, en
  AEnc): la tabla del Delphi activo (Lsp.DesignerMeta, con su espera), el
  form contra su clase y EL parser del IDE con esos bytes (AJuzga=False en un
  binario, que ya paso su conversion). Con ALector, si la tabla no encontro
  nada y dejo lineas sin juicio, el form entero al LECTOR del IDE
  (Lsp.FormRender.LoQueNoCargaElIde, el juez de set): lo piden el lint y el
  juicio de lo escrito; designer set/insert/delete tienen el suyo. AAntes:
  el texto del form ANTES de la edicion que se juzga ('' en el lint o en un
  form nuevo): la nota de los StyleLookup dice solo los que la edicion trae
  (V143 de la 1.23.1), y la de los colores sin alfa, que pregunta al
  escritor del IDE y por eso va solo con ALector, tambien (V154). ADesde: el
  instante en que empezo la llamada que espera (Lsp.FormRender.EmpiezaLaEspera),
  y los jueces del IDE tienen lo que le queda (PlazoDelCliente); 0, sin plazo de
  cliente. Nunca lanza. }
function LintDeForm(const ADfm, ATexto, AEnc: string; AJuzga: Boolean;
  AEsperaMs: Cardinal = ESPERA_TABLA_MS; ALector: Boolean = False;
  const AAntes: string = ''; ADesde: UInt64 = 0): TLintDeForm;
{ POR QUE se le pregunta al lector del IDE por el form de AL: las lineas que la
  tabla no juzga (SinJuez), el frame en linea (FrameInline) o las dos. EL que lo
  compone para DSGN-154 del lint y EDIT-127 / EDIT-131 de una escritura: con un
  frame en linea y ninguna linea, DSGN-154 decia '0 line(s) hold a property' y
  EDIT-127 que se le pregunto por una propiedad (medido el 4-nov-2026). }
function PorQueAlLector(const AL: TLintDeForm): string;

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
  tanda y el changeset UNA vez al final (AplazaJuicioDeForm). AAntes: el
  texto de antes de la edicion, como en LintDeForm ('' = todo es nuevo). }
function JuicioDeForm(const APath, ATexto, AEnc: string; const AAntes: string = ''): TArray<string>;
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
  const AOmite: TArray<string> = nil; const AAntes: string = ''): TArray<string>;
{ Lo que el LECTOR del IDE dice del form APath tal como quedo en disco,
  cuando la tabla calla (LintDeForm con ALector): la cabecera EDIT-127 y sus
  lineas, o nada. Se pide FUERA del cerrojo de escritura (EnterFileEdit): el
  lector es un proceso que tarda segundos, y dentro paraba las escrituras de
  todos - como el juez del orden del disenador (revisor 5 de la noche, A3).
  Por eso no va en JuicioDeLoEscrito, que corre dentro: lo piden las tools
  que escriben forms al acabar (delphi_edit, el changeset, upload).
  DSGN-061 de la 1.20. Y los colores sin alfa que la escritura trae (DSGN-176,
  V154 de la 1.23.1): AAntes, el texto de antes ('' = todos: un form nuevo, o
  un upload, que trae el fichero entero). ADesde: el instante en que empezo la
  llamada (Lsp.FormRender.EmpiezaLaEspera, lo toma la tool al empezar): sus
  jueces tienen lo que le queda al cliente, y sin tiempo no se lanzan. Cada uno
  tenia el plazo de un preview, con lo escrito ya en disco: un cliente que se
  rinde y repite duplicaba la edicion (A3 del revisor del paisaje de la 1.27).
  Nunca lanza. }
function AvisosDelLector(const APath, AAntes: string; ADesde: UInt64): TArray<string>;
{ ARespuesta (la de una escritura de APath) con AvisosDelLector detras, si
  APath es un form y no fue un fallo. AAntes, el de TextoAntesDeEditar;
  ADesde, el de AvisosDelLector. }
function ConAvisosDelLector(const ARespuesta, APath, AAntes: string; ADesde: UInt64): string;
{ Lo que dice el disco de APath ANTES de una edicion, si es un form (las notas
  dicen solo lo que la edicion trae); '' si no lo es o no se lee. Nunca lanza. }
function TextoAntesDeEditar(const APath: string): string;
{ La nota de un fichero EN DISCO que es UTF-8 sin BOM y que dcc lee en ANSI
  (READ-008 de un fuente, READ-009 de un form), por la puerta de leer y EL
  detector: la de delphi_read, para quien no lo lee entero (designer lint).
  '' si no es el caso o no se puede leer. }
function NotaDeUtf8SinBomDe(const APath: string): string;
{ ...y sobre unos bytes ya leidos (K: la que dijo EL detector de B): la nota
  de un fuente o de un form sin BOM, la que ensena tambien delphi_read
  (ReadNumbered, en Lsp.Patch). }
function NotaDeUtf8SinBom(const APath: string; K: TEncKind; const B: TArray<Byte>): string;
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

threadvar
  // >0 dentro de una tanda o un changeset sobre un form: ver
  // AplazaJuicioDeForm (interface). Por hilo, como GOrigenes
  GJuicioDeFormAplazado: Integer;

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

implementation

uses
  System.Math,
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.IOUtils,
  Winapi.Windows,
  Lsp.Texts,
  Lsp.DesignerBin,
  Lsp.DesignerForma, // EsDesignerFmx: de que marco es un designer
  Lsp.DesignerBinding,
  Lsp.Pascal, // VistaPascal: el lexico Pascal de la casa
  Lsp.Mascara,
  Lsp.FormRender, // LoQueNoCargaElIde: el lector del IDE juzga lo que la tabla no (LintDeForm)
  Lsp.Styles, // NotaDeLookupsSinEstilo: los StyleLookup contra los estilos que el form ve (LintDeForm)
  Lsp.Herencia, // VedaElMotor: con el cerrojo, el lint no arranca motores (LintDeForm)
  Lsp.Lineas,
  Lsp.Extensiones,
  Lsp.Deteccion, // DetectEnc: EL detector de codificacion
  Lsp.Puertas;   // LeeBytes, TextoDeDesigner, EnCerrojoDeEscritura: las puertas

function DesignersDeUnidad(const AUnidad: string; const ATextoDe: string): TArray<string>;
begin
  Result := [];
  for var E in DESIGNER_EXTS do
    Result := Result + [ChangeFileExt(AUnidad, E)];
  if Assigned(GTextoDeUnidad) then
    Result := Result + VistasDeUnidad(AUnidad, GTextoDeUnidad(IfThen(ATextoDe <> '', ATextoDe, AUnidad)));
end;

function DesignerLint(const APath, ATexto, AEnc, AAntes: string): TArray<string>; forward;

procedure AplazaJuicioDeForm(AAplaza: Boolean);
begin
  if AAplaza then
    Inc(GJuicioDeFormAplazado)
  else if GJuicioDeFormAplazado > 0 then
    Dec(GJuicioDeFormAplazado);
end;

function JuicioDeForm(const APath, ATexto, AEnc, AAntes: string): TArray<string>;
begin
  Result := [];
  if not EsRutaDeDesigner(APath) then
    Exit;
  Result := [MsgText(SN_EDIT_DESIGNER_FORMATO_TEXTO)] + DesignerLint(APath, ATexto, AEnc, AAntes);
end;

function JuicioDeLoEscrito(const APath, ATexto, AEnc: string;
  const AOmite: TArray<string>; const AAntes: string): TArray<string>;
begin
  Result := JuicioDeForm(APath, ATexto, AEnc, AAntes);
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
  for var L in LineasDelTexto(ARespuesta) do
  begin
    var T := L.Trim;
    if not Dentro and MsgCuerpo(T).StartsWith('***') then
      Dentro := True;
    if Dentro and (T <> '') then
      Result := Result + [T];
  end;
end;

{ Si el form lleva un frame inline: esa carga no la juzga ninguna tabla (un frame que
  se contiene a si mismo daba CLEAN de un form que no se carga; 1-nov-2026) }
function LlevaFrameInline(const ALineas: TArray<string>): Boolean;
var
  Clave, Nombre, Clase: string;
begin
  for var L in ALineas do
    if LineaDeObjeto(L.Trim, Clave, Nombre, Clase) and SameText(Clave, 'inline') then
      Exit(True);
  Result := False;
end;

function LosJuecesDeUnForm(const ADfm, ATexto, AEnc: string; AJuzga: Boolean;
  AEsperaMs: Cardinal; ALector: Boolean; const AAntes: string; ADesde: UInt64): TLintDeForm;
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
  // ...y los StyleLookup de un form FMX contra los estilos que ve: EL juez de
  // delphi_styles lint (V75 de la 1.23.1: set los escribia y el lint daba
  // CLEAN); tras una edicion, los que ella trae (V143)
  if EsDesignerFmx(ADfm) then
    Result.Lookups := NotaDeLookupsSinEstilo(ADfm, Lineas, LineasDelTexto(AAntes));
  // ...y lo que preview negaria luego: EL juez de preview (DSGN-115); tras una
  // edicion, lo que ella trae. Por el texto: nada que pida salir del cerrojo
  Result.Literales := NotaDeLiteralesQuePreviewNiega(ADfm, Lineas, LineasDelTexto(AAntes));
  // ...y sus colores de menos de 8 cifras: los juzga el escritor del IDE, un
  // proceso aparte, asi que solo con el lector, fuera de los cerrojos (V154)
  if ALector and EsDesignerFmx(ADfm) then
  begin
    Result.Colores := NotaDeColoresSinAlfa(ADfm, ATexto, AEnc, AAntes, ADesde);
    var ConStyleBook: Boolean;
    var Usados := LookupsDeDesigner(ADfm, Lineas, ConStyleBook);
    if ConStyleBook then
      Result.LookupsSinJuzgar := Length(Usados);
  end;
  // ...y EL parser del IDE con los bytes del disco (8.10 de la 1.18.0): un //
  // en un .fmx daba CLEAN y solo el IDE lo rechazaba al cargarlo
  if AJuzga then
    Result.Parser := AvisoDelParserDeForm(ATexto, AEnc);
  // EL juez de verdad de lo que la tabla no juzga (DSGN-061 de la 1.20): una
  // propiedad que la clase guarda por codigo no tiene tipo en la tabla, y
  // FontColor = -65536 en un TEdit FMX pasaba delphi_edit sin aviso y el lint
  // con CLEAN de un form que no abria. Solo si la tabla no encontro nada: con
  // un aviso suyo el form ya no carga, y el lector no diria mas
  Result.FrameInline := LlevaFrameInline(Lineas);
  if ALector and ((Result.SinJuez > 0) or Result.FrameInline) and (Result.Parser = '') and
     (Length(Result.Propiedades) = 0) and (Result.Falta.Razon = '') then
    Result.Lector := LoQueNoCargaElIde(ADfm, ATexto, AEnc, Result.SinLector, ADesde);
end;

function PorQueAlLector(const AL: TLintDeForm): string;
begin
  if AL.FrameInline and (AL.SinJuez > 0) then
    Result := MsgFmt(SF_DSGN_LECTOR_POR_LINEAS_Y_FRAME_FMT, [AL.SinJuez])
  else if AL.FrameInline then
    Result := MsgText(SF_DSGN_LECTOR_POR_FRAME)
  else
    Result := MsgFmt(SF_DSGN_LECTOR_POR_LINEAS_FMT, [AL.SinJuez]);
end;

function LintDeForm(const ADfm, ATexto, AEnc: string; AJuzga: Boolean;
  AEsperaMs: Cardinal; ALector: Boolean; const AAntes: string; ADesde: UInt64): TLintDeForm;
begin
  // con el cerrojo de escritura cogido (DesignerLint de delphi_edit y del
  // changeset, delete del disenador), ningun juez arranca ni pregunta al
  // motor: paraba TODAS las escrituras del servidor (V173a de la 1.23.1,
  // medido: un textedit de otro fichero espero 1,9 s de los 2,6 del edit). La
  // raiz con su base en otra unidad queda sin juzgar, como sin ajustes de
  // proyecto; el lint de fuera (delphi_designer lint) la juzga entera
  if not EnCerrojoDeEscritura then
    Exit(LosJuecesDeUnForm(ADfm, ATexto, AEnc, AJuzga, AEsperaMs, ALector, AAntes, ADesde));
  VedaElMotor;
  try
    Result := LosJuecesDeUnForm(ADfm, ATexto, AEnc, AJuzga, AEsperaMs, ALector, AAntes, ADesde);
  finally
    LevantaElMotor;
  end;
end;

{ Lo que delphi_edit (y el changeset y la tanda, que escriben por el) dice del
  form que acaba de escribir: LintDeForm con el texto escrito, sin esperar a
  una tabla, presentado como avisos de una edicion. }
function AvisosDelLector(const APath, AAntes: string; ADesde: UInt64): TArray<string>;
var
  Texto, Enc: string;
begin
  Result := [];
  try
    if not EsRutaDeDesigner(APath) or (TextoDeDesigner(APath, Texto, Enc) <> '') then
      Exit;
    // la tabla sin esperarla, como tras cada edicion; y el lector, con lo que le queda
    // al cliente de la llamada
    var L := LintDeForm(APath, Texto, Enc, True, 0, True, AAntes, ADesde);
    if Length(L.Lector) > 0 then
      Result := [MsgFmt(SN_EDIT_AVISO_LECTOR_FMT, [ExtractFileName(APath), PorQueAlLector(L)])] + L.Lector;
    // ...y si no se le pudo preguntar (el plazo, sin renderizador...) o lo que salto
    // no se situa en el form, se dice, como el lint (DSGN-154): callado, se leia como
    // que el form carga
    if L.SinLector <> '' then
      Result := Result + [MsgFmt(SN_EDIT_LECTOR_SIN_CONFIRMAR_FMT, [ExtractFileName(APath), PorQueAlLector(L),
        L.SinLector])];
    Result := Result + L.Colores;
  except
    // un juicio que no se pudo hacer no tumba una escritura ya hecha
    Result := [];
  end;
end;

function ConAvisosDelLector(const ARespuesta, APath, AAntes: string; ADesde: UInt64): string;
begin
  Result := ARespuesta;
  if EsFallo(ARespuesta) or not EsRutaDeDesigner(APath) then
    Exit;
  var Avisos := AvisosDelLector(TPath.GetFullPath(APath), AAntes, ADesde);
  if Length(Avisos) > 0 then
    Result := Result + #13#10 + string.Join(#13#10, Avisos);
end;

function TextoAntesDeEditar(const APath: string): string;
var
  Enc: string;
begin
  Result := '';
  try
    if not EsRutaDeDesigner(APath) or (TextoDeDesigner(TPath.GetFullPath(APath), Result, Enc) <> '') then
      Result := '';
  except
    Result := ''; // sin el de antes se juzgan todos
  end;
end;

function DesignerLint(const APath, ATexto, AEnc, AAntes: string): TArray<string>;
var
  Raw: TArray<string>;
  Res: TStringList;
  I: Integer;
  ExtName: string;
begin
  Result := [];
  // (sin el lector: esto corre DENTRO del cerrojo; AvisosDelLector, fuera)
  var L := LintDeForm(APath, ATexto, AEnc, True, 0, False, AAntes);
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
     (Length(L.Lookups) = 0) and (Length(L.Literales) = 0) and (Falta.Razon = '') and (NotaEnc = '') then
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
    Res.AddStrings(L.Lookups);
    Res.AddStrings(L.Literales);
    if NotaEnc <> '' then
      Res.Add(NotaEnc);
    Result := Res.ToStringArray;
  finally
    Res.Free;
  end;
end;

end.
