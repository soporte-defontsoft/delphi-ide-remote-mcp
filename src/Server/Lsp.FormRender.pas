unit Lsp.FormRender;

{ delphi_designer command=preview, la mitad del SERVIDOR: lanza los
  renderizadores de forms (src\Render: DelphiFormRenderVcl y
  DelphiFormRenderFmx, junto al exe del servidor como DelphiStyleConvert) y
  lee lo que contestan. Cada pieza, una vez:

    FormRenderExe          donde esta el renderizador de un framework: el
                           nombre del exe solo se compone aqui
    ComponeOrdenDeRender   LA orden, un interruptor por parametro de preview
                           (test_paisaje vigila que nadie mas la componga);
                           su inversa es ParseaArgumentos del ayudante
    LeeRespuestaDeRender   la inversa de FormRenderProtocolo.inc, que incluyen
                           el ayudante (el escritor, FormRender.Comun.Responde)
                           y este lector
    CorreRender            lo lanza con RunCapturedIn y su tiempo limite,
                           FUERA del AppContainer de delphi_test: el contenedor
                           no deja crear ventanas, y el VCL y el FMX mueren al
                           crear la form (medido 6 y 7-oct-2026, vault
                           renderform-ayudantes-2026-10-07). El ayudante lleva
                           ademas su propio vigia, un poco antes, para contestar
                           el por que.

  Por que procesos aparte y no una unidad del servidor: los paquetes de
  diseno del IDE se cargan EN el renderizador; si uno revienta muere el
  renderizador y el servidor contesta el error (src\Render\README.md). }

interface

uses
  Lsp.Styles,       // TStyleDoc: la linea de lo que dijo el lector (LineaDeLoLeido)
  Lsp.DesignerMeta; // TPropiedadDelUsuario: lo que publica una clase del usuario

type
  TPeticionRender = record
    Framework: string;         // vcl | fmx
    Path: string;              // el .dfm/.fmx, ya pasado por la puerta de lectura
    Salida: string;            // el .png que escribe el renderizador
    Estados: TArray<string>;   // Componente.Propiedad=Valor, uno por entrada
    Componente: string;        // '' = la form entera
    Estilo: string;            // fichero (ya por la puerta), plataforma, none o ''
    NoVisuales: Boolean;       // dibujar los no visuales
    Bds: string;               // la version del Delphi del servidor (37.0)
    Raiz: string;              // form | frame, por el lector de clases del servidor; '' = que mire el ayudante
    // el JUEZ de lo que guarda el IDE (3.11 de la 1.18.0): sin png, el form
    // cargado y escrito por TWriter (WRITTEN=); Carpeta, la del form de verdad
    // cuando Path es una propuesta escrita en otra (sus hermanos y su .pas)
    Escribe: Boolean;
    Carpeta: string;
  end;

  { Una propiedad que el lector se salto (IGNORED=, el OnError de TReader que
    el ayudante contesta Ignore), o el error que lo paro (NOTLOADED=): lo que
    dijo tal cual y sus partes, que da el ayudante con el formato que lo
    compuso (SPropertyException, en SU idioma: PartesDeLectura). Uno de otra
    forma queda solo en Texto (David, 7-oct-2026: que guien al modelo). }
  TIgnorada = record
    Texto: string;
    Componente, Propiedad, Motivo: string; // '' si no casa
    // la clase de la excepcion si NO era del lector (el codigo de un
    // componente: IBX sin gds32.dll, un AV de un bpl); '' si era del lector
    // (EFilerError, EParserError: el fichero). Lo dice el ayudante (IGNORED=)
    Origen: string;
  end;

  { Un no visual de la raiz (NONVISUALS=<Nombre:Clase,...>): el ayudante lo
    escribe 'Nombre:Clase' y aqui se lee en sus partes - lo troceaba la tool
    (segunda revision de la 1.17.0, 2.3 de la 1.18.0). }
  TNoVisual = record
    Nombre, Clase: string;
  end;

  { Un fichero que el ayudante leyo para cargar el form (READ=<sha256>|<ruta>):
    un ancestro, un frame, el .pas de la cadena, con la huella de los bytes
    que uso (B5 rev6 de la 1.18.2). }
  TLeidoPorElJuez = record
    Huella, Ruta: string;
  end;

  TRespuestaRender = record
    Fallo: string;             // '' = hay imagen; si no, el mensaje para el agente
    Error: string;             // ERROR= del ayudante, tal cual
    // NOTLOADED=: lo que fallo fue el LECTOR mientras cargaba el form - el
    // fichero, no el ayudante (DSGN-061 de la 1.20)
    NoCarga: Boolean;
    Parada: TIgnorada;         // ...y el error con el que paro, en sus partes
    Codigo: Cardinal;          // su codigo de salida
    Captura: string;           // CAPTURE=
    Ancho, Alto: Integer;      // SIZE=
    Dpi, Sesion: Integer;      // DPI=, SESSION=
    RaizNombre, RaizClase, RaizTipo: string; // ROOT=<nombre>:<clase>:<form|frame>
    Fidelidad, Estilo, Paquetes: string;     // FIDELITY=, STYLE=, PACKAGES=
    Componentes: Integer;      // COMPONENTS=
    Sustituidas, Avisos: TArray<string>;
    Ignoradas: TArray<TIgnorada>;
    NoVisuales: TArray<TNoVisual>; // NONVISUALS=
    NoVisualesDibujados: Integer; // NONVISUAL=
    HayRect: Boolean;          // RECT= del componente pedido
    RectX, RectY, RectW, RectH: Integer;
    MsCarga, MsPintado: Integer; // MS=
    MsTotal: Int64;            // lo que tardo de verdad, lanzamiento incluido
    Escrito: TArray<string>;   // WRITTEN=: el form como lo guarda el IDE, con sus blancos
    SinLeer: TArray<string>;   // PARTIAL=: sin que ancestro (o fichero) se leyo el form
    Leidos: TArray<TLeidoPorElJuez>; // READ=: lo que leyo para cargarlo, con su huella
  end;

{ El renderizador de AFramework (vcl|fmx) junto al exe del servidor; '' si
  no esta. ANombre sale siempre, para decir cual falta. }
function FormRenderExe(const AFramework: string; out ANombre: string): string;

{ LA orden de un render: '' y AOrden, o el rechazo. Un valor con comillas o
  con un caracter de control se niega: el lector de argumentos de Delphi no
  tiene escape para una comilla, y lo que fuera detras seria OTRO
  interruptor (un --out fuera de la jaula). }
function ComponeOrdenDeRender(const AExe: string; const APeticion: TPeticionRender;
  out AOrden: string): string;

{ El --root de un render (form | frame): lo que es la raiz de la unidad para
  el IDE, por sus jueces (Lsp.ProjectUnits.JuzgaRaizDeDiseno: su cadena
  contra la tabla del marco, sin esperarla, y si no llega, el registro del
  IDE en un .dproj que la lista), y solo si su designer es el form pedido (un X.fmx al lado
  de un X.dfm: la unidad es del .dfm). Un modulo se lee en la form. Si no se
  sabe, '': que mire el ayudante. La unidad, ya por la puerta de lectura de
  quien llama. Nunca lanza (segunda revision de la 1.17.0: un sufijo
  adivinado viajaba como un hecho; despues, una lista de nombres). }
function RaizParaElRender(const ARuta: string): string;

{ La clase en la que el lector del IDE (el ayudante) lee la raiz, por la
  clase de raiz que dijo (RaizTipo: frame o form): su frame o su form. La
  componian igual, a mano, lo que no cargo (LoQueNoCargo) y preview. }
function ClaseDelSustituto(const ARaizTipo: string): string;

{ Un mensaje del lector EN PARTES (FR_PARTES_SEP, de IGNORED= y NOTLOADED=)
  -> TIgnorada: EL lector, inverso de FormRender.Comun.LecturaEnPartes.
  Componente es el Name del objeto (o su clase, el de un item de una
  coleccion: lo que pone TReader) y Propiedad su ruta (Font.Size). Aqui se
  partia el texto con el formato INGLES, y el RTL del ayudante habla el idioma
  de Windows (medido el 18-oct-2026: en aleman no nombraba nada). }
function PartesDeLectura(const AValor: string): TIgnorada;

{ La linea (1-based) de ADoc que nombra lo que dijo el lector en AI - su
  componente y su propiedad -, o 0 si no esta en ESTE fichero (de un
  ancestro, de un frame) o no nombra ninguna. EL localizador: lo hacia a mano
  el preview para sus ignored, y ahora lo piden tambien LoQueNoCargo. }
function LineaDeLoLeido(ADoc: TStyleDoc; const AI: TIgnorada): Integer;

{ Si lo que el lector se salto (AI) es una propiedad de la RAIZ (ARaizNombre)
  que publica una clase del USUARIO (APublicadas: PublicadasPorElUsuario): el
  renderizador no carga las clases del usuario y no la conoce, asi que no es
  un error del form (DSGN-152); ASuya, cual. EL juicio de preview, que dice
  cuales son, y de LoQueNoCargo, que no las da por lo que no carga. }
function IgnoradaDelUsuario(const ARaizNombre: string; const AI: TIgnorada;
  const APublicadas: TArray<TPropiedadDelUsuario>; out ASuya: TPropiedadDelUsuario): Boolean;

{ Lo que el LECTOR del IDE no cargo de un form (R: lo que se salto y, si fue
  suyo - NoCarga -, el error que lo paro), uno por linea, lo que dijo TAL
  CUAL con la linea de ADoc que nombra (SF_DSGN_LINEA_AVISO_FMT, la forma de
  los avisos del lint); sin linea, solo lo que dijo. Sin repetir: el error
  que lo paro suele ser el ultimo que se salto. ADoc nil: todo sin linea.
  AForm, el form de verdad (su .pas dice lo que publica el usuario).
  ANoConfirmado: el motivo de DSGN-154 por lo que NO va entre lo que no carga,
  porque no se puede afirmar del fichero: algo de la RAIZ que es de su clase y
  no de la form en la que la lee el lector (DeLaRaizQueElLectorNoVe), una
  excepcion del codigo de un componente (DelCodigoDeUnComponente) o las partes de un
  componente de una clase que no esta instalada (PartesDeClaseNoInstalada). }
function LoQueNoCargo(const R: TRespuestaRender; ADoc: TStyleDoc; const AForm: string;
  out ANoConfirmado: string): TArray<string>;

{ Lo que el lector se salto por una excepcion que NO era suya (Origen: la
  clase, que dice el ayudante por la jerarquia de la RTL): la lanzo el codigo
  de un componente - IBX sin gds32.dll, un TActionManager sin su unidad de
  estilo, un AV de un bpl -, no la lectura de una linea. No es del fichero,
  que se sepa: DSGN-154 con el motivo, no un aviso (corpus del 18-oct-2026).
  Un "Ancestor for X not found" si es del lector (EReadError) y sigue siendo
  aviso: lo mide V3 de test_lint_vistas_1202. }
function DelCodigoDeUnComponente(const AI: TIgnorada): Boolean;

{ El componente de AI elige sus PARTES por una clase que esta instalacion no
  tiene: una propiedad suya '...ClassName' con un nombre de clase que la tabla
  del marco no conoce (ItemAppearanceClassName = 'TMultiDetailItemAppearance',
  que registra una unidad del proyecto y el lector no carga): lo que el lector
  salto debajo no se puede confirmar. AProp y AClase, cuales. Sin tabla, o sin
  documento, no se sabe: False (y queda como aviso). }
function PartesDeClaseNoInstalada(ADoc: TStyleDoc; const AI: TIgnorada; AFmx: Boolean;
  out AProp, AClase: string): Boolean;

{ Lo que dijo el lector de AI, con la clase de la excepcion delante si no era
  suya ('EIBClientError: ...'): EL compositor, para el lint (LoQueNoCargo) y
  el preview (revisor de la 1.20.2: dos emisores). }
function TextoDeIgnorada(const AI: TIgnorada): string;

{ La salida del renderizador -> sus campos (las lineas '#' son traza). }
function LeeRespuestaDeRender(const ASalida: string): TRespuestaRender;

{ Lanza el renderizador y lee lo que contesta. Fallo = '' si hay imagen en
  APeticion.Salida; si no, el mensaje que toca (el ERROR= del ayudante tal
  cual si ya lleva su etiqueta). Nunca lanza. }
function CorreRender(const APeticion: TPeticionRender): TRespuestaRender;

{ EL JUEZ de lo que guarda el IDE (3.11 de la 1.18.0; norma 6: lo que dice un
  juez real se le pregunta): ATexto, un form PROPUESTO para APath (en AEnc),
  cargado por el renderizador de su framework como lo carga el designer -
  modo diseno, los paquetes del IDE, sus frames y ancestros desde la carpeta
  de APath - y escrito por TWriter, lo que hace el IDE al guardar: AEscrito.
  ASustituidas, las clases que no pudo cargar (su sustituto no sabe como las
  escribe el IDE); ASinLeer, los ancestros sin los que leyo el form (PARTIAL=:
  un juicio a medias); ALeidos, los ficheros que leyo para cargarlo (READ=:
  quien escribe lo juzgado los vuelve a mirar, CambioEnLoLeido). '' si bien;
  si no, el fallo, en AError el ERROR= del ayudante tal cual y, si lo que
  fallo fue el lector (NOTLOADED=), en AParada su error en partes. La
  propuesta se escribe en una carpeta de descarga del temporal del disenador
  y se borra siempre. }
function ComoLoEscribeElIde(const APath, ATexto, AEnc: string; out AEscrito: string;
  out ASustituidas, AAvisos, ASinLeer: TArray<string>; out ALeidos: TArray<TLeidoPorElJuez>;
  out AError: string; out AParada: TIgnorada): string;

{ CON el cerrojo, justo antes de escribir lo que juzgo el ayudante: '' si
  cada fichero que leyo para cargar el form (ALeidos) sigue con los bytes de
  su huella; si no, el nombre del primero que cambio (o que ya no se deja
  leer). La huella, por EL hash de la casa (Sha256DeBytes), el mismo con el
  que la compone el ayudante; los bytes, por la puerta de leer. }
function CambioEnLoLeido(const ALeidos: TArray<TLeidoPorElJuez>): string;

{ EL JUEZ de un form ENTERO por el lector del IDE (DSGN-061 de la 1.20):
  ATexto cargado como lo carga el designer - el mismo ayudante y la misma
  carpeta de ComoLoEscribeElIde - y lo que no cargo, con las lineas de ATexto
  (LoQueNoCargo). Lo piden el lint y el juicio de lo escrito cuando las
  tablas callan: el valor de una propiedad que la clase guarda por codigo no
  tiene tipo en la tabla, y solo lo juzga el lector (FontColor = -65536 en un
  TEdit FMX: delphi_edit lo escribia sin avisar y el lint decia CLEAN de un
  form que no abria). ANoPregunto: por que no se le pudo preguntar (sin
  renderizador, el tiempo, un paquete que revento al cargar): entonces no hay
  lineas y no se sabe. Nunca lanza. }
function LoQueNoCargaElIde(const APath, ATexto, AEnc: string; out ANoPregunto: string): TArray<string>;

{ LO COMUN de una peticion de render para el form APath (ya por la puerta de
  lectura): el framework (AFramework, o el del fichero si va vacio), la ruta,
  el Delphi del servidor y form o frame por EL lector de clases si su .pas se
  deja leer. Lo componian a mano preview y el juez (revisor 5 de la noche,
  B3); el resto (salida, estado, estilo...) lo pone cada uno. }
function PeticionDeRender(const APath, AFramework: string): TPeticionRender;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Diagnostics,
  System.RegularExpressions,
  Lsp.Guard,
  Lsp.BuildRunner,  // RunCapturedIn: el lanzador de los programas externos
  Lsp.ProjectUnits, // InspectUnit: la clase de la unidad y a que raiz llega
  Lsp.DesignerForma, // UnidadDeDesigner
  Lsp.Texts,
  Lsp.DesignerBin,
  Lsp.Casa,         // ServerDir: la carpeta del exe del servidor
  Lsp.Patch,        // EscribeTexto: la puerta de escribir, la propuesta del juez
  Lsp.Codificacion, // EncKindOf
  Lsp.Discovery,    // DiscoverRadStudio: el Delphi del servidor
  Lsp.ShaCache;     // Sha256DeBytes: la huella de READ=, la misma que compone el ayudante

const
  {$I ..\Render\FormRenderProtocolo.inc}

  // Lo que espera el servidor, y el vigia del ayudante un poco antes: asi es
  // el ayudante quien contesta por que se paro (RENDER-007). Medido el
  // 7-oct-2026: una form estandar 20 ms, FichaCliente con 112 paquetes del
  // IDE ~1,2 s (9,4 s la primera vez, con la cache de disco fria).
  RENDER_TIEMPO_MS = 75000;
  RENDER_TIEMPO_AYUDANTE_MS = 60000;

  // Windows no pudo cargar el exe o sus paquetes de ejecucion (rtl/vcl/fmx
  // del Delphi): no hay ERROR= porque no llego a correr nada suyo
  STATUS_DLL_NOT_FOUND_ = $C0000135;
  STATUS_ENTRYPOINT_NOT_FOUND_ = $C0000139;
  STATUS_INVALID_IMAGE_FORMAT_ = $C000007B;

function FormRenderExe(const AFramework: string; out ANombre: string): string;
begin
  if SameText(AFramework, 'fmx') then
    ANombre := 'DelphiFormRenderFmx.exe'
  else
    ANombre := 'DelphiFormRenderVcl.exe';
  Result := ServerDir(ANombre);
  if not TFile.Exists(Result) then
    Result := '';
end;

function RaizParaElRender(const ARuta: string): string;
var
  Unidad: TUnitInfo;
begin
  Result := '';
  try
    if (InspectUnit(UnidadDeDesigner(ARuta), Unidad) <> '') or (Unidad.ClassName = '') or
       not SameFileName(Unidad.Designer, TPath.GetFullPath(ARuta)) then
      Exit;
    // la cadena primero (el lint pregunta lo mismo para la raiz: el motor, si
    // hace falta, ya esta): aqui solo cuenta la categoria, y el registro del
    // IDE sube por las carpetas leyendo cada .dpr - en cada preview y en el
    // lint de cada edicion. Solo si la cadena no llega
    JuzgaRaizDeDiseno(Unidad, '', 0);
    if Unidad.Raiz = rdDesconocida then
    begin
      var Registro := RegistroDelIde(Unidad.PasPath, '');
      if Registro <> '' then
        JuzgaRaizDeDiseno(Unidad, Registro, 0);
    end;
    case Unidad.Raiz of
      rdFrame: Result := 'frame';
      rdForm, rdModulo: Result := 'form';
    end;
  except
    Result := ''; // una unidad que no se deja leer: que mire el ayudante
  end;
end;

function ClaseDelSustituto(const ARaizTipo: string): string;
begin
  // el frame que crea el ayudante es el del marco (Lsp.DesignerMeta), y su
  // form oculta, una TForm
  if SameText(ARaizTipo, 'frame') then
    Result := DesignClassDeFrame(False)
  else
    Result := 'TForm';
end;

{ Un valor que viaja como UN argumento entre comillas }
function ValorDeArgumento(const AValor: string): Boolean;
begin
  for var C in AValor do
    if (C = '"') or (C < ' ') then
      Exit(False);
  Result := True;
end;

function ComponeOrdenDeRender(const AExe: string; const APeticion: TPeticionRender;
  out AOrden: string): string;

  function Arg(const AInterruptor, AValor: string): string;
  begin
    Result := ' ' + AInterruptor + ' "' + AValor + '"';
  end;

begin
  Result := '';
  AOrden := '';
  // un valor vacio no se pasa nunca: el lector de Delphi se salta un "" y
  // tomaria el interruptor siguiente como valor
  for var V in TArray<string>.Create(APeticion.Path, APeticion.Salida,
    APeticion.Componente, APeticion.Estilo, APeticion.Bds, APeticion.Carpeta) + APeticion.Estados do
    if not ValorDeArgumento(V) then
      Exit(MsgFmt(SR_DESIGNER_VALOR_CON_COMILLAS_FMT, [V]));
  AOrden := '"' + AExe + '"' + Arg('--path', APeticion.Path);
  // el juez no pinta: sin --out (3.11)
  if APeticion.Escribe then
  begin
    AOrden := AOrden + ' --writeback on';
    if APeticion.Carpeta <> '' then
      AOrden := AOrden + Arg('--folder', APeticion.Carpeta);
  end
  else
    AOrden := AOrden + Arg('--out', APeticion.Salida) +
      ' --nonvisual ' + (if APeticion.NoVisuales then 'on' else 'off');
  AOrden := AOrden + ' --timeout ' + IntToStr(RENDER_TIEMPO_AYUDANTE_MS);
  if APeticion.Bds <> '' then
    AOrden := AOrden + Arg('--bds', APeticion.Bds);
  for var E in APeticion.Estados do
    if E <> '' then
      AOrden := AOrden + Arg('--state', E);
  if APeticion.Componente <> '' then
    AOrden := AOrden + Arg('--component', APeticion.Componente);
  if (APeticion.Raiz = 'form') or (APeticion.Raiz = 'frame') then
    AOrden := AOrden + ' --root ' + APeticion.Raiz;
  if APeticion.Estilo <> '' then
    AOrden := AOrden + Arg('--style', APeticion.Estilo);
end;

function PartesDeLectura(const AValor: string): TIgnorada;
var
  P1, P2, P3: Integer;
begin
  Result := Default(TIgnorada);
  Result.Texto := AValor;
  // las tres partes no llevan el separador (el ayudante no parte si lo
  // llevaran) y el texto si puede: Split con tope tira lo que sobra
  P1 := AValor.IndexOf(FR_PARTES_SEP);
  if P1 < 0 then
    Exit;
  P2 := AValor.IndexOf(FR_PARTES_SEP, P1 + 1);
  if P2 < 0 then
    Exit;
  P3 := AValor.IndexOf(FR_PARTES_SEP, P2 + 1);
  if P3 < 0 then
    Exit;
  Result.Componente := AValor.Substring(0, P1);
  Result.Propiedad := AValor.Substring(P1 + 1, P2 - P1 - 1);
  Result.Motivo := AValor.Substring(P2 + 1, P3 - P2 - 1);
  Result.Texto := AValor.Substring(P3 + 1);
end;

function LeeRespuestaDeRender(const ASalida: string): TRespuestaRender;
var
  L, V: string;
  Trozos: TArray<string>;
  P: Integer;

  function Es(const AClave: string): Boolean;
  begin
    Result := L.StartsWith(AClave);
    if Result then
      V := L.Substring(Length(AClave));
  end;

begin
  Result := Default(TRespuestaRender);
  Result.Sesion := -1;
  for var Linea in ASalida.Replace(#13, '').Split([#10]) do
  begin
    L := Linea;
    if (L = '') or L.StartsWith('#') then
      Continue;
    if Es(FR_CAPTURE) then
      Result.Captura := V
    else if Es(FR_SIZE) then
    begin
      Trozos := V.Split(['x']);
      if Length(Trozos) = 2 then
      begin
        Result.Ancho := StrToIntDef(Trozos[0], 0);
        Result.Alto := StrToIntDef(Trozos[1], 0);
      end;
    end
    else if Es(FR_DPI) then
      Result.Dpi := StrToIntDef(V, 0)
    else if Es(FR_SESSION) then
      Result.Sesion := StrToIntDef(V, -1)
    else if Es(FR_ROOT) then
    begin
      Trozos := V.Split([':']);
      if Length(Trozos) = 3 then
      begin
        Result.RaizNombre := Trozos[0];
        Result.RaizClase := Trozos[1];
        Result.RaizTipo := Trozos[2];
      end;
    end
    else if Es(FR_FIDELITY) then
      Result.Fidelidad := V
    else if Es(FR_PACKAGES) then
      Result.Paquetes := V
    else if Es(FR_COMPONENTS) then
      Result.Componentes := StrToIntDef(V, 0)
    else if Es(FR_SUBSTITUTED) then
      Result.Sustituidas := V.Split([','], TStringSplitOptions.ExcludeEmpty)
    else if Es(FR_IGNORED) then
    begin
      // <de quien>|<mensaje en partes> (FR_ORIGEN_LECTOR = del lector)
      P := V.IndexOf(FR_PARTES_SEP);
      var Ig := PartesDeLectura(V.Substring(P + 1));
      if (P > 0) and (V.Substring(0, P) <> FR_ORIGEN_LECTOR) then
        Ig.Origen := V.Substring(0, P);
      Result.Ignoradas := Result.Ignoradas + [Ig];
    end
    else if Es(FR_NONVISUALS) then
      for var Item in V.Split([','], TStringSplitOptions.ExcludeEmpty) do
      begin
        var NV: TNoVisual;
        P := Item.LastIndexOf(':');
        NV.Nombre := Item;
        NV.Clase := '';
        if P >= 0 then
        begin
          NV.Nombre := Item.Substring(0, P);
          NV.Clase := Item.Substring(P + 1);
        end;
        Result.NoVisuales := Result.NoVisuales + [NV];
      end
    else if Es(FR_NONVISUAL) then
      Result.NoVisualesDibujados := StrToIntDef(V, 0)
    else if Es(FR_RECT) then
    begin
      // <Nombre>=<izq>,<arriba>,<ancho>,<alto>: el nombre no lleva '='
      P := V.LastIndexOf('=');
      Trozos := V.Substring(P + 1).Split([',']);
      if (P > 0) and (Length(Trozos) = 4) then
      begin
        Result.HayRect := True;
        Result.RectX := StrToIntDef(Trozos[0], 0);
        Result.RectY := StrToIntDef(Trozos[1], 0);
        Result.RectW := StrToIntDef(Trozos[2], 0);
        Result.RectH := StrToIntDef(Trozos[3], 0);
      end;
    end
    else if Es(FR_STYLE) then
      Result.Estilo := V
    else if Es(FR_WARNING) then
      Result.Avisos := Result.Avisos + [V]
    else if Es(FR_MS) then
    begin
      Trozos := V.Split([',']);
      if Length(Trozos) = 2 then
      begin
        Result.MsCarga := StrToIntDef(Trozos[0], 0);
        Result.MsPintado := StrToIntDef(Trozos[1], 0);
      end;
    end
    else if Es(FR_WRITTEN) then
      Result.Escrito := Result.Escrito + [V]
    else if Es(FR_PARTIAL) then
      Result.SinLeer := Result.SinLeer + [V]
    else if Es(FR_READ) then
    begin
      // <sha256>|<ruta>: la huella es hexadecimal, y una ruta no lleva '|'
      P := V.IndexOf('|');
      if P > 0 then
      begin
        var Leido: TLeidoPorElJuez;
        Leido.Huella := V.Substring(0, P);
        Leido.Ruta := V.Substring(P + 1);
        Result.Leidos := Result.Leidos + [Leido];
      end;
    end
    else if Es(FR_ERROR) then
      Result.Error := V
    else if Es(FR_NOT_LOADED) then
    begin
      // <clase>|<su mensaje en partes>
      Result.NoCarga := True;
      P := V.IndexOf(FR_PARTES_SEP);
      if P > 0 then
        Result.Parada := PartesDeLectura(V.Substring(P + 1));
    end;
  end;
end;

function LineaDeLoLeido(ADoc: TStyleDoc; const AI: TIgnorada): Integer;
var
  Ini, Fin: Integer;
begin
  Result := 0;
  if (ADoc = nil) or (AI.Componente = '') then
    Exit;
  var Obj := ADoc.ObjetoDeNombre(AI.Componente);
  if (Obj <> nil) and ADoc.PropLines(Obj, AI.Propiedad, Ini, Fin) then
    Result := Ini + 1;
end;

function IgnoradaDelUsuario(const ARaizNombre: string; const AI: TIgnorada;
  const APublicadas: TArray<TPropiedadDelUsuario>; out ASuya: TPropiedadDelUsuario): Boolean;
begin
  ASuya := Default(TPropiedadDelUsuario);
  Result := (ARaizNombre <> '') and SameText(AI.Componente, ARaizNombre) and
    PropiedadDelUsuarioLlamada(APublicadas, AI.Propiedad, ASuya);
end;

function DelCodigoDeUnComponente(const AI: TIgnorada): Boolean;
begin
  Result := AI.Origen <> '';
end;

function TextoDeIgnorada(const AI: TIgnorada): string;
begin
  Result := AI.Texto;
  if AI.Origen <> '' then
    Result := AI.Origen + ': ' + AI.Texto;
end;

function PartesDeClaseNoInstalada(ADoc: TStyleDoc; const AI: TIgnorada; AFmx: Boolean;
  out AProp, AClase: string): Boolean;
var
  Falta: TFaltaTabla;
  Id, Nombre: string;
  Nivel: Integer;
begin
  Result := False;
  AProp := '';
  AClase := '';
  if (ADoc = nil) or (AI.Componente = '') or (AI.Propiedad = '') then
    Exit;
  var Obj := ADoc.ObjetoDeNombre(AI.Componente);
  if Obj = nil then
    Exit;
  var M := MetaTable(AFmx, Falta, 0);
  if M = nil then
    Exit;
  // las propiedades del nivel propio del objeto (ni las de sus hijos ni las
  // de un item de coleccion) que acaban en ClassName, por EL lector de lineas.
  // '...ClassName' es gramatica NUESTRA, declarada (test_paisaje) y sin juez:
  // lo decide el setter de cada clase con GetClass. Y solo cuenta lo saltado
  // que cuelga de esas partes (ItemAppearance -> ItemAppearanceObjects...):
  // una errata en otra propiedad del mismo componente sigue siendo aviso
  // (revisor de la 1.20.2)
  var Lineas := LineasDeForm(ADoc.Lines);
  Nivel := 0;
  for var I := Obj.StartLine to Obj.EndLine - 2 do // 0-based: de debajo del object a encima del end
  begin
    if I > High(Lineas) then
      Break;
    case Lineas[I].Clase of
      clfObjeto: Inc(Nivel);
      clfFin: Dec(Nivel);
      clfPropiedad:
        if (Nivel = 0) and (Lineas[I].Coleccion = 0) and Lineas[I].Prop.EndsWith('ClassName', True) and
           AI.Propiedad.StartsWith(Lineas[I].Prop.Substring(0, Lineas[I].Prop.Length - Length('ClassName')), True) and
           LeeLiteralDeForm(Lineas[I].Valor, Nombre) and (Nombre <> '') and not M.ClaseDeNombre(Nombre, Id) then
        begin
          AProp := Lineas[I].Prop;
          AClase := Nombre;
          Exit(True);
        end;
    end;
  end;
end;

type
  // las partes de un componente de una clase que no esta instalada: que
  // propiedad las elige, con que clase, y lo que el lector salto debajo
  TPartesDelProyecto = record
    Componente, Prop, Clase, Saltado: string;
  end;

function LoQueNoCargo(const R: TRespuestaRender; ADoc: TStyleDoc; const AForm: string;
  out ANoConfirmado: string): TArray<string>;
var
  Vistos: TArray<string>;
  Lineas, SinProp: TArray<string>;
  RaizNombre, RaizClase, Sustituto, NoVistas, PropCn, ClaseCn: string;
  Raiz: TRaizParaElLector;
  Proyecto: TArray<TPartesDelProyecto>;

  procedure Pon(const AI: TIgnorada);
  begin
    for var V in Vistos do
      if V = AI.Texto then
        Exit;
    Vistos := Vistos + [AI.Texto];
    var N := LineaDeLoLeido(ADoc, AI);
    if N > 0 then
      Lineas := Lineas + [MsgFmt(SF_DSGN_LINEA_AVISO_FMT, [N, ADoc.Lines[N - 1].Trim, AI.Texto])]
    else
      Lineas := Lineas + [MsgFmt(SF_DSGN_LECTOR_SIN_LINEA_FMT, [AI.Texto])];
  end;

  // lo que se salto de un objeto cuya clase el ayudante SUSTITUYO (no esta
  // instalada: el sustituto no publica sus propiedades) no es un valor malo:
  // es la nota de una clase de terceros (DSGN-039), no un aviso por edicion
  function DeSustituida(const AI: TIgnorada): Boolean;
  begin
    Result := False;
    if (ADoc = nil) or (AI.Componente = '') then
      Exit;
    var Obj := ADoc.ObjetoDeNombre(AI.Componente);
    if Obj <> nil then
      for var S in R.Sustituidas do
        if SameText(S, Obj.ClassName_) then
          Exit(True);
  end;

begin
  Vistos := [];
  Lineas := [];
  SinProp := [];
  Proyecto := [];
  // la raiz: la que dijo el ayudante, o (si fallo antes de decirla) la del
  // fichero; lo que publica su cadena del usuario no lo conoce el lector
  RaizNombre := R.RaizNombre;
  RaizClase := R.RaizClase;
  if (RaizNombre = '') and (ADoc <> nil) and (ADoc.Root <> nil) then
  begin
    RaizNombre := ADoc.Root.ObjName;
    RaizClase := ADoc.Root.ClassName_;
  end;
  Raiz := Default(TRaizParaElLector);
  if (AForm <> '') and (RaizClase <> '') then
    Raiz := RaizParaElLector(AForm, RaizClase, EsDesignerFmx(AForm));
  // la clase en la que el lector lee la raiz
  Sustituto := ClaseDelSustituto(R.RaizTipo);
  NoVistas := '';
  for var I in R.Ignoradas do
  begin
    var Suya: TPropiedadDelUsuario;
    if DeSustituida(I) or IgnoradaDelUsuario(RaizNombre, I, Raiz.Propias, Suya) then
      Continue;
    // de la raiz, y de su clase y no de la form en la que la lee el lector: un
    // TQuickRep, un TForm3D, un modulo de datos FMX - no se sabe (DSGN-154)
    if (RaizNombre <> '') and SameText(I.Componente, RaizNombre) and
       DeLaRaizQueElLectorNoVe(Raiz, Sustituto, I.Propiedad) then
    begin
      NoVistas := NoVistas + (if NoVistas <> '' then ', ' else '') + I.Propiedad;
      Continue;
    end;
    // una excepcion del codigo de un componente (no del lector) y lo saltado
    // bajo las partes de una clase del proyecto: no se sabe (DSGN-154)
    if DelCodigoDeUnComponente(I) then
    begin
      SinProp := SinProp + [TextoDeIgnorada(I)];
      Continue;
    end;
    if PartesDeClaseNoInstalada(ADoc, I, EsDesignerFmx(AForm), PropCn, ClaseCn) then
    begin
      var K := -1;
      for var J := 0 to High(Proyecto) do
        if SameText(Proyecto[J].Componente, I.Componente) then
          K := J;
      if K < 0 then
      begin
        var Nueva: TPartesDelProyecto;
        Nueva.Componente := I.Componente;
        Nueva.Prop := PropCn;
        Nueva.Clase := ClaseCn;
        Nueva.Saltado := I.Propiedad;
        Proyecto := Proyecto + [Nueva];
      end
      else
        Proyecto[K].Saltado := Proyecto[K].Saltado + ', ' + I.Propiedad;
      Continue;
    end;
    Pon(I);
  end;
  ANoConfirmado := '';
  if NoVistas <> '' then
    ANoConfirmado := MsgFmt(SF_DSGN_LECTOR_RAIZ_NO_VISTA_FMT, [Sustituto, Raiz.Clase, NoVistas]);
  if Length(SinProp) > 0 then
    ANoConfirmado := ANoConfirmado + (if ANoConfirmado <> '' then '; ' else '') +
      MsgFmt(SF_DSGN_LECTOR_DEL_CODIGO_FMT, [string.Join(' | ', SinProp)]);
  for var Pr in Proyecto do
    ANoConfirmado := ANoConfirmado + (if ANoConfirmado <> '' then '; ' else '') +
      MsgFmt(SF_DSGN_LECTOR_CLASE_DEL_PROYECTO_FMT, [Pr.Componente, Pr.Prop, Pr.Clase, Pr.Saltado]);
  if R.NoCarga then
  begin
    // el error que lo paro, sin la clase delante: como lo dice el lector, y
    // como lo dicen las que se salto
    var E := R.Parada;
    if E.Texto = '' then
      E.Texto := R.Error;
    Pon(E);
  end;
  Result := Lineas;
end;

{ La forma del VALOR decide, nunca una lista de propiedades.
  Se pregunta al unico juez de lectura por cada fichero existente.
  El ayudante interpreta relativos desde la form o desde su cwd (la carpeta
  del form desde la 1.18.2; antes, la del PNG). }
function LiteralesDeRenderDenegados(const APeticion: TPeticionRender): string;
var
  Bases: TArray<string>;
  BytesLeidos: Int64;
  Doc: TStyleDoc;
  Form: TArray<TLineaForm>;
  Texto, Valor, Prop: string;

  function Comprueba(const AProp, AValor: string): string;
  var
    Ruta: string;
  begin
    Result := '';
    // El valor se juzga por su texto ANTES de alargarlo o preguntar si existe.
    if RutaSinTocarElDisco(AValor) then
      Exit(MsgFmt(SR_DESIGNER_LITERAL_FUERA_FMT, [AProp]));
    if AValor = '' then
      Exit;
    for var Base in Bases do
    begin
      try
        Ruta := TPath.GetFullPath(TPath.Combine(Base, AValor));
      except
        Continue; // una cadena que no es ruta no nombra un fichero
      end;
      // la propuesta del juez (Carpeta: la del form de verdad) es el texto del
      // agente, que el servidor escribio para ESTA llamada en una carpeta suya:
      // un relativo que la nombra ('UNom.dfm', el nombre del form) no sale de
      // ningun sitio, y daba DSGN-115 falso (revisor de version de la 1.18.0,
      // B2). Lo demas de esa base sigue juzgado: un '..\x' saldria del temporal
      if (APeticion.Carpeta <> '') and SameFileName(Ruta, TPath.GetFullPath(APeticion.Path)) then
        Continue;
      if TFile.Exists(Ruta) and (ReadPathDenied(Ruta) <> '') then
        Exit(MsgFmt(SR_DESIGNER_LITERAL_FUERA_FMT, [AProp]));
    end;
  end;

  function CompruebaForm(const ARuta: string; AEnTemporal: Boolean = False): string;
  begin
    Result := '';
    // 65 MiB de texto costaron 416 MiB en el servidor; la pasada previa
    // sucede antes del job. El presupuesto total se mira ANTES de cargar.
    const TOPE_LITERAL_BYTES = 16 * 1024 * 1024;
    Inc(BytesLeidos, TFile.GetSize(ARuta));
    if BytesLeidos > TOPE_LITERAL_BYTES then
      Exit(MsgFmt(SR_DESIGNER_LITERAL_TOPE_FMT, [TOPE_LITERAL_BYTES div (1024 * 1024)]));
    // la propuesta del juez vive en el temporal del servidor, que la puerta
    // de la jaula no lee: por su lugar, y es texto (la escribio el servidor)
    if AEnTemporal then
      Doc := TStyleDoc.DeTexto(LeeTexto(ARuta, [ltTemporal]))
    else
      Doc := TStyleDoc.Create(ARuta); // tambien el binario, por el lector existente
    try
      // los literales se juzgan por las lineas de LineasDeForm, y el ayudante
      // carga el form con el lector del IDE: uno que el parser no lee por
      // lineas como LineasDeForm no se juzga, y no se dibuja (DSGN-160, 3b
      // del censo de jueces)
      Result := FormaDistintaDeLineas(Doc.Lines, TPath.GetFileName(ARuta));
      if Result <> '' then
        Exit;
      Form := LineasDeForm(Doc.Lines);
      for var I := 0 to High(Doc.Lines) do
        if Form[I].Clase = clfPropiedad then
        begin
          Prop := Form[I].Prop;
          Valor := ValorEnteroDe(Doc.Lines, Form, I);
          if LeeLiteralDeForm(Valor, Texto) then
          begin
            Result := Comprueba(Prop, Texto);
            if Result <> '' then
              Exit;
          end
          else if Valor = '(' then
          begin
            // Strings de una lista: el mismo lector, no otra gramatica.
            Valor := '';
            for var K := I + 1 to Form[I].Fin - 1 do
            begin
              Valor := Valor + Doc.Lines[K].Trim;
              if Valor.EndsWith('+') then
                Continue;
              if LeeLiteralDeForm(Valor, Texto) then
              begin
                Result := Comprueba(Prop, Texto);
                if Result <> '' then
                  Exit;
              end;
              Valor := '';
            end;
          end;
        end;
    finally
      Doc.Free;
    end;
  end;

begin
  Result := '';
  BytesLeidos := 0;
  // las carpetas desde las que el ayudante resuelve un relativo y en las que
  // busca hermanos: la del fichero que lee y, cuando el fichero es una
  // propuesta escrita en otra, la del form de verdad (--folder: de ahi lee
  // frames y ancestros, y es su cwd). La del png fue su cwd hasta la 1.18.2 y
  // se sigue mirando: una base de mas no abre nada. Una base que no mira es
  // un relativo que pasa la puerta (revisor 3 de la noche, A-1)
  var Hermanos := TPath.GetDirectoryName(APeticion.Path);
  if APeticion.Carpeta <> '' then
    Hermanos := APeticion.Carpeta;
  Bases := [TPath.GetDirectoryName(APeticion.Path)];
  if APeticion.Salida <> '' then
    Bases := Bases + [TPath.GetDirectoryName(APeticion.Salida)];
  if APeticion.Carpeta <> '' then
    Bases := Bases + [APeticion.Carpeta];
  try
    // lo que se le da a leer al ayudante, TAMBIEN la propuesta del juez
    // (Carpeta): el form de verdad se leyo en otro momento y un escritor que
    // esperaba el cerrojo pudo cambiarlo (revisor 6 del 3.11, M1)
    Result := CompruebaForm(APeticion.Path, APeticion.Carpeta <> '');
    if Result <> '' then
      Exit;
    // Los frames y ancestros que el ayudante puede resolver son hermanos.
    // (con Carpeta, el form de verdad no es un hermano: el ayudante lee su
    // propuesta, que ya se miro arriba; mirarlo otra vez dependia de que no
    // lo borrasen mientras - medido con O20)
    var ElDeVerdad := '';
    if APeticion.Carpeta <> '' then
      ElDeVerdad := TPath.Combine(APeticion.Carpeta, TPath.GetFileName(APeticion.Path));
    for var Hermano in WalkFiles(Hermanos, ['*' + ExtractFileExt(APeticion.Path)], False, False) do
      if not EsEnlace(Hermano) and not SameFileName(Hermano, APeticion.Path) and
         not SameFileName(Hermano, ElDeVerdad) then
      begin
        Result := CompruebaForm(Hermano);
        if Result <> '' then
          Exit;
      end;
    for var Estado in APeticion.Estados do
    begin
      var P := Pos('=', Estado);
      if P = 0 then
        Continue; // el lector de state dara su diagnostico de forma
      Prop := Copy(Estado, 1, P - 1).Trim;
      Valor := Copy(Estado, P + 1, MaxInt).Trim;
      Result := Comprueba(Prop, Valor); // state se entrega crudo a SetPropValue
      if Result = '' then
        if LeeLiteralDeForm(Valor, Texto) then
          Result := Comprueba(Prop, Texto);
      if Result <> '' then
        Exit;
    end;
  except
    Result := MsgText(SR_DESIGNER_LITERAL_NO_VERIFICABLE);
  end;
end;

function CorreRender(const APeticion: TPeticionRender): TRespuestaRender;
var
  Exe, Nombre, Orden, Salida, Fallo, CwdPropio: string;
  Codigo: Cardinal;
  Reloj: TStopwatch;
begin
  Result := Default(TRespuestaRender);
  CwdPropio := '';
  Result.Fallo := LiteralesDeRenderDenegados(APeticion);
  if Result.Fallo <> '' then
    Exit;
  Exe := FormRenderExe(APeticion.Framework, Nombre);
  if Exe = '' then
  begin
    Result.Fallo := MsgFmt(SR_DESIGNER_SIN_RENDER_FMT, [Nombre, ServerDir('')]);
    Exit;
  end;
  Fallo := ComponeOrdenDeRender(Exe, APeticion, Orden);
  if Fallo <> '' then
  begin
    Result.Fallo := Fallo;
    Exit;
  end;
  Reloj := TStopwatch.StartNew;
  try
    // en la carpeta del form de verdad (la del juez que no pinta es Carpeta:
    // su propuesta esta en el temporal del servidor): el ayudante carga el
    // form DEL AGENTE y nada relativo suyo cae en la casa del servidor
    // (revisor 6 del 3.11, B6). Era la carpeta del png, que desde la 1.18.2
    // esta en nuestra casa de capturas (revisor del 2af)
    var Cwd := TPath.GetDirectoryName(APeticion.Path);
    if APeticion.Carpeta <> '' then
      Cwd := APeticion.Carpeta;
    // ...si la sesion puede ESCRIBIR alli: el codigo de diseno de los paquetes
    // escribe RELATIVO al cwd (lo miden URenderReachDummy y su gemelo FMX), y
    // un form de una referencia o de un ReadOnlyPaths lo llevaria a escribir
    // donde nadie puede (revisor de la 2a mitad del 2af, M3). Ahi, una carpeta
    // nuestra nueva y vacia, que se va al acabar
    if EscrituraDenegada(Cwd) <> '' then
    begin
      CwdPropio := NuevaCarpetaDescarga(ServerTempDir(CAPTURE_SUB_DESIGNER));
      CrearCarpeta(CwdPropio);
      Cwd := CwdPropio;
    end;
    Salida := RunCapturedIn(Orden, Cwd, RENDER_TIEMPO_MS, Codigo);
  except
    on E: Exception do
    begin
      Result.Fallo := MsgFmt(SR_DESIGNER_RENDER_NO_ARRANCA_FMT, [Nombre, E.Message]);
    end;
  end;
  if CwdPropio <> '' then
    try
      BorraArbol(CwdPropio); // sin cruzar enlaces: ver Lsp.Guard
    except
      // limpiar no puede tumbar la respuesta: la purga del arranque se la lleva
    end;
  if Result.Fallo <> '' then
    Exit;
  Result := LeeRespuestaDeRender(Salida);
  Result.Codigo := Codigo;
  Result.MsTotal := Reloj.ElapsedMilliseconds;
  if (Codigo = FR_RC_OK) and (Result.Error = '') and
     (if APeticion.Escribe then Length(Result.Escrito) > 0 else TFile.Exists(APeticion.Salida)) then
    Exit;
  // el LECTOR no cargo el form (NOTLOADED=): es el fichero, y se dice con lo
  // que dijo y su linea. Salia como DSGN-061 INTERNAL, y con un valor que el
  // Ignore se saltaba, solo "Stream read error" (DSGN-061 de la 1.20, Hermes)
  if Result.NoCarga then
  begin
    var Doc: TStyleDoc := nil;
    try
      try
        Doc := TStyleDoc.Create(APeticion.Path);
      except
        Doc := nil; // sin lineas: lo que dijo el lector, tal cual
      end;
      // el form de verdad: el del juez es una propuesta escrita en otra
      // carpeta, y su .pas (lo que publica el usuario) esta en Carpeta
      var Form := APeticion.Path;
      if APeticion.Carpeta <> '' then
        Form := TPath.Combine(APeticion.Carpeta, TPath.GetFileName(APeticion.Path));
      // (lo de la raiz que el lector no ve no va en la lista; el error que lo
      // paro, si)
      var NoVista: string;
      Result.Fallo := MsgFmt(SR_DESIGNER_NO_CARGA_FMT, [TPath.GetFileName(APeticion.Path),
        #10 + string.Join(#10, LoQueNoCargo(Result, Doc, Form, NoVista))]);
    finally
      Doc.Free;
    end;
  end
  else if Result.Error <> '' then
    // con etiqueta (un estado que no existe, el vigia) sale tal cual
    Result.Fallo := MsgEnvuelve(SR_DESIGNER_RENDER_FALLO_FMT, Result.Error,
      [TPath.GetFileName(APeticion.Path), Result.Error])
  else if (Codigo = STATUS_DLL_NOT_FOUND_) or (Codigo = STATUS_ENTRYPOINT_NOT_FOUND_) or
    (Codigo = STATUS_INVALID_IMAGE_FORMAT_) then
    Result.Fallo := MsgFmt(SR_DESIGNER_RENDER_SIN_BPL_FMT, [Nombre, APeticion.Bds, Codigo])
  else if Result.MsTotal >= RENDER_TIEMPO_MS then
    Result.Fallo := MsgFmt(SR_DESIGNER_RENDER_TIEMPO_FMT, [Nombre, RENDER_TIEMPO_MS div 1000])
  else
    Result.Fallo := MsgFmt(SR_DESIGNER_RENDER_FALLO_FMT, [TPath.GetFileName(APeticion.Path),
      MsgFmt(SF_DESIGNER_RENDER_SIN_RESPUESTA_FMT, [Codigo, Copy(Salida.Trim, 1, 300)])]);
end;

function PeticionDeRender(const APath, AFramework: string): TPeticionRender;
begin
  Result := Default(TPeticionRender);
  Result.Framework := AFramework;
  if Result.Framework = '' then
    Result.Framework := (if EsDesignerFmx(APath) then 'fmx' else 'vcl');
  Result.Path := APath;
  Result.Bds := DiscoverRadStudio.Version;
  // form o frame lo dice EL lector de clases (RaizParaElRender): el ayudante
  // lo adivinaba con su regex. Sin .pas legible, o sin saberlo, que mire el
  var Pas := UnidadDeDesigner(APath);
  if TFile.Exists(Pas) and (ReadPathDenied(Pas) = '') then
    Result.Raiz := RaizParaElRender(APath);
end;

{ La propuesta ATexto para APath, escrita en una carpeta de descarga de ESTA
  llamada y cargada por el ayudante de su framework en modo juez (--writeback:
  el form como lo carga el designer, sin pintar): lo que contesto, con Fallo
  si ni se pudo escribir. La carpeta se borra siempre. EL juez de
  ComoLoEscribeElIde y de LoQueNoCargaElIde. }
function JuezDelIde(const APath, ATexto, AEnc: string): TRespuestaRender;
var
  Pet: TPeticionRender;
  Dir, Cand: string;
begin
  Result := Default(TRespuestaRender);
  // una carpeta de descarga de ESTA llamada en el temporal del SERVIDOR (EL
  // nombrador: el guard del borrado la reconoce), con la propuesta bajo el
  // nombre del form de verdad: su .pas y sus hermanos los lee el ayudante de
  // la carpeta de APath (--folder). Es del servidor, no un entregable del
  // agente: en el __delphi-temp de la raiz la escritura pasaba por la puerta
  // del agente y el confinamiento la negaba (revisor 5 de la noche, M1)
  Dir := NuevaCarpetaDescarga(ServerTempDir(CAPTURE_SUB_DESIGNER));
  try
    try
      CrearCarpeta(Dir);
      Cand := TPath.Combine(Dir, TPath.GetFileName(APath));
      // LAXO: es la copia que se le PREGUNTA al ayudante, no la escritura del
      // form - como ParserDeForm (Lsp.DesignerBin), "juzgar el parseo, no
      // escribir". En estricto, un sustituto suelto que ya estaba en un .dfm
      // UTF-16 tumbaba el juicio con EDIT-078 "nothing written" cuando el
      // escritor de verdad (PatchSaveText) si escribia (revisor propio de la
      // 1.18.1); lo NUEVO lo sigue negando ese escritor
      EscribeTexto(Cand, ATexto, ltTemporal, EncKindOf(AEnc), False);
    except
      on E: Exception do
      begin
        Result.Fallo := MsgExcepcion(E.ClassName, E.Message);
        Exit;
      end;
    end;
    Pet := PeticionDeRender(APath, '');
    Pet.Path := Cand;
    Pet.Carpeta := TPath.GetDirectoryName(APath);
    Pet.Escribe := True;
    Result := CorreRender(Pet);
  finally
    try
      BorraArbol(Dir); // SIEMPRE, sin cruzar enlaces: ver Lsp.Guard
    except
      // limpiar no puede tumbar la respuesta
    end;
  end;
end;

function ComoLoEscribeElIde(const APath, ATexto, AEnc: string; out AEscrito: string;
  out ASustituidas, AAvisos, ASinLeer: TArray<string>; out ALeidos: TArray<TLeidoPorElJuez>;
  out AError: string; out AParada: TIgnorada): string;
begin
  AEscrito := '';
  ASustituidas := [];
  AAvisos := [];
  ASinLeer := [];
  ALeidos := [];
  var R := JuezDelIde(APath, ATexto, AEnc);
  AError := R.Error;
  AParada := R.Parada;
  Result := R.Fallo;
  if Result <> '' then
    Exit;
  AEscrito := string.Join(#13#10, R.Escrito);
  ASustituidas := R.Sustituidas;
  AAvisos := R.Avisos;
  ASinLeer := R.SinLeer;
  ALeidos := R.Leidos;
end;

function CambioEnLoLeido(const ALeidos: TArray<TLeidoPorElJuez>): string;
begin
  Result := '';
  for var L in ALeidos do
  begin
    var Igual := False;
    try
      Igual := SameText(Sha256DeBytes(LeeBytes(L.Ruta, [ltJaula])), L.Huella);
    except
      // borrado, renombrado o negado mientras se juzgaba: cambio
    end;
    if not Igual then
      Exit(TPath.GetFileName(L.Ruta));
  end;
end;

function LoQueNoCargaElIde(const APath, ATexto, AEnc: string; out ANoPregunto: string): TArray<string>;
var
  Doc: TStyleDoc;
begin
  Result := [];
  ANoPregunto := '';
  try
    var R := JuezDelIde(APath, ATexto, AEnc);
    // leido SIN un ancestro (PARTIAL=): cada 'inherited' sin el dice "Ancestor
    // for X not found", y eso es de NUESTRA lectura, no del form - una vista
    // FMX sin el .pas de su maestro al lado, o con uno que no la declara, "no
    // cargaba" (medido el 18-oct-2026). No se sabe, y se dice por que
    if Length(R.SinLeer) > 0 then
    begin
      ANoPregunto := MsgFmt(SF_DSGN_LECTOR_SIN_ANCESTRO_FMT, [string.Join(', ', R.SinLeer)]);
      Exit;
    end;
    // lo cargo, o fallo por otra cosa (sin renderizador, el tiempo, un
    // paquete): de lo suyo el lector no dijo nada
    if not R.NoCarga and (Length(R.Ignoradas) = 0) then
    begin
      ANoPregunto := R.Fallo;
      Exit;
    end;
    Doc := nil;
    try
      try
        Doc := TStyleDoc.DeTexto(ATexto);
      except
        Doc := nil; // sin lineas: lo que dijo el lector, tal cual
      end;
      var NoVista: string;
      Result := LoQueNoCargo(R, Doc, APath, NoVista);
      // lo no confirmado (la raiz que el lector no ve, una excepcion del codigo
      // de un componente, las partes de una clase del proyecto) se dice
      // TAMBIEN cuando hay avisos de verdad: el lint imprime las dos partes
      // (se tiraba si habia aviso; revisor de la 1.20.2)
      if NoVista <> '' then
        ANoPregunto := NoVista;
    finally
      Doc.Free;
    end;
  except
    on E: Exception do
    begin
      Result := [];
      ANoPregunto := MsgExcepcion(E.ClassName, E.Message);
    end;
  end;
end;

end.
