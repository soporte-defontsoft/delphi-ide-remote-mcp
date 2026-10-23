unit Lsp.DesignerEdit;

{ delphi_designer insert / set / delete: editar un form (.dfm/.fmx) y su
  unidad como lo haria el IDE, y solo lo BASICO (David, 4-oct-2026: "no
  queremos construir un IDE completo, solo ayudar a los agentes"). El
  criterio de lo basico: que el componente SE VEA al abrir el form en el IDE
  y al ejecutar. Y la idea de fondo, suya: una puerta nuestra donde lo que se
  pide se controla contra la realidad del proyecto y del Delphi instalado
  ANTES de escribir.

    insert  un control VISUAL nuevo, hijo de su padre donde lo deja el IDE (el form por
            defecto), en 10,10, con su texto (su Name) si la clase lo tiene,
            su TabOrder, su campo publicado en la clase del form y su unidad
            en el uses; sus propiedades, como las guarda el escritor del IDE
            (el tamano de su constructor en VCL: ConLasPropiedadesDelIde).
    set     UNA propiedad, juzgada contra las tablas (JuzgaPropiedad, el juez
            del lint) ANTES de escribir, y escrita con las del componente como
            las guarda el escritor del IDE; parent= mueve el bloque entero a
            otro contenedor; Name renombra (el form, sus referencias y el campo).
    delete  el componente con su subarbol, las referencias a el desde el
            form, su campo y sus manejadores VACIOS exclusivos. Nunca deja
            codigo huerfano como el IDE (David, 7-oct-2026): un metodo propio
            CON cuerpo lo niega, y el agente limpia primero.

  UN analizador de impacto para delete y para set de Name: renombrar es,
  para el codigo, quitar un nombre y poner otro. Lo que USA el componente
  desde otros metodos es cosa del compilador: se lista y no bloquea ("no
  somos la ninera"). El form y su unidad se escriben juntos, todo o nada
  (Lsp.TodoONada.FicherosTodoONada). }

interface

uses
  Lsp.Styles,
  Lsp.DesignerMeta;    // la tabla del framework y su juez (JuzgaPropiedad); el analizador la recibe

type
  { Un campo publicado de la clase del form que es de un componente que se
    va (o que cambia de nombre). }
  TCampoPropio = record
    Nombre: string;
    Ini, Fin: Integer;  // 0-based en la unidad: la declaracion
    Todos: Integer;     // cuantos campos declara esa declaracion ('A, B: TButton;' = 2)
    Solo: Boolean;      // en sus lineas no hay nada mas de la clase (LineasSoloSuyas)
    Limpia: Boolean;    // ni una directiva ni un comentario que siga fuera de ellas (LineasLimpias)
  end;

  { Un metodo de la clase del form que es "del componente": lo ata un evento
    de su subarbol, o lleva su nombre (Button1Click, ValidaButton1). }
  TMetodoPropio = record
    Nombre: string;
    Atado: string;       // 'Button1.OnClick' si lo ata uno del subarbol; '' si no
    PorNombre: Boolean;  // lleva el nombre del componente
    Compartido: string;  // '' = exclusivo; si no, quien mas lo usa (no se toca ni bloquea)
    ConCuerpo: Boolean;  // su implementacion hace algo: codigo, un comentario o declaraciones
    DeclIni, DeclFin: Integer;  // 0-based en la unidad: la declaracion en la clase
    ImplIni, ImplFin: Integer;  // 0-based: la implementacion entera; -1 = no tiene
    EnSusLineas: Boolean;       // la declaracion y la implementacion ocupan sus lineas solas
    Linea: Integer;      // 1-based, la que se ensena (la implementacion, o la declaracion)
    SeBorra: Boolean;    // lo quita el delete (vacio y exclusivo)
  end;

  { Si la propiedad AProp de AObj guarda un componente: lo sabe la tabla del
    framework. Sin juez (nil) o sin saberlo, si: manda el nombre. }
  TJuezDeReferencia = reference to function(AObj: TStyleObj; const AProp: string): Boolean;

  TImpacto = record
    Componente, Clase: string;
    Nombres: TArray<string>;       // el componente y los de su subarbol con nombre
    Referencias: TArray<Integer>;  // 0-based: lineas del form, fuera del subarbol, que lo nombran
    Campos: TArray<TCampoPropio>;
    Metodos: TArray<TMetodoPropio>;
    Usos: TArray<string>;          // 'Unit1.pas:42: Button1.Caption := ...'
    Nota: string;                  // por que no se miro la unidad (la clase no esta en ella)
  end;

{ EL analizador de impacto: lo que el componente AObj (con su subarbol, o
  solo el si ASoloEl) ata en el form y en su unidad. APasTexto vacio = solo
  el form. Lo usan delete y set de Name. AJuez: que lineas del form son
  referencias (Align = Client en FMX no nombra a un componente Client).
  ATabla, la del marco: que lineas son eventos (EventoDeObjeto: el AfterOpen
  de un TDataSet no empieza por On); sin ella, el nombre. }
function AnalizaImpacto(ADoc: TStyleDoc; AObj: TStyleObj; ASoloEl: Boolean;
  const APasTexto, APasNombre: string; AJuez: TJuezDeReferencia = nil; ATabla: TMetaTable = nil): TImpacto;

{ El delete sobre los TEXTOS: '' y el form y la unidad como quedan, o la
  negativa (un metodo propio con cuerpo). AImp, el impacto, con SeBorra
  puesto en los metodos que se van. }
function PlanDeBorrado(ADoc: TStyleDoc; AObj: TStyleObj;
  const APasTexto, APasNombre: string; out AImp: TImpacto;
  out ADfm, APas: string; AJuez: TJuezDeReferencia = nil; ATabla: TMetaTable = nil): string;

{ El renombrado sobre los TEXTOS (ANuevo ya validado): la cabecera del objeto,
  las lineas del form que lo nombran (AImp.Referencias) y su campo; y su
  texto si era su nombre: ATextos, las propiedades donde su clase lo pone al
  nombrarse (PropiedadesDeTexto; [] = no lo hace). }
function PlanDeRenombre(ADoc: TStyleDoc; AObj: TStyleObj;
  const ANuevo, APasTexto, APasNombre: string; const ATextos: TArray<string>;
  out AImp: TImpacto; out ADfm, APas: string; AJuez: TJuezDeReferencia = nil;
  ATabla: TMetaTable = nil): string;

{ Los comandos. Cada uno devuelve el JSON de lo hecho, o la negativa sin
  haber escrito nada. La jaula de escritura la piden ellos; el cerrojo de
  escritura (EnterFileEdit) lo coge la tool. }
// AProps (3.10 de la 1.18.0): 'Prop=valor;...' - las propiedades iniciales de
// insert, o varias de set de una vez; todo o nada, cada una juzgada como set
function InsertaComponente(const APath, AClase, AComponente, AParent: string;
  const AProps: string = ''): string;
// ABefore / AAfter / AIndex (3.11 de la 1.18.0): el orden del componente entre
// sus hermanos, si el IDE lo guarda ahi (AIndex 1 = el primero; -1 = no se pide)
function CambiaPropiedad(const APath, AComponente, AProp, AValor, AParent: string;
  const AProps: string = ''; const ABefore: string = ''; const AAfter: string = '';
  AIndex: Integer = -1): string;
function BorraComponente(const APath, AComponente: string): string;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.Math,
  System.JSON,
  System.RegularExpressions,
  System.Character,
  System.Generics.Collections,
  Lsp.Texts,
  Lsp.Guard,           // WriteTargetDenied
  Lsp.Mascara,         // CitaDeLinea
  Lsp.Patch,           // PatchLoadText/PatchSaveText y los troceadores
  Lsp.Codificacion,    // EncKindOf/EncName: la codificacion de la unidad
  Lsp.Pascal,          // EL identificador, CodigoPascal, LineaDePosicion
  Lsp.PascalDecl,      // EL lector de clases: campos, rutinas y cuerpos
  Lsp.DesignerBin,     // el literal de cadena, el flotante, las lineas del form
  Lsp.DesignerForma,   // la linea de objeto y su compositor
  Lsp.Herencia,        // LA cadena de ancestros por el motor (los componentes heredados)
  Lsp.DesignerMetaGen, // la unidad de una clase (UnidadDeIdDeTipo)
  Lsp.DesignerBinding, // EL lector de la linea de evento; los avisos del binding
  Lsp.ProjectUnits,    // UsesConUnidades: el uses de la unidad
  Lsp.TodoONada,       // FicherosTodoONada
  Lsp.FormRender,      // ComoLoEscribeElIde: el juez del orden entre hermanos (3.11)
  Lsp.Args;

const
  // (las identidades de la tabla, ID_VCL_CONTROL y las demas: Lsp.DesignerMeta)
  // donde cae un control nuevo (David, 4-oct-2026)
  INSERT_X = 10;
  INSERT_Y = 10;
  MAX_USOS = 30;
  MAX_NOMBRES = 40;
  // (que valor toma cada tipo lo dice la tabla, leido del fuente: la base
  // de un tipo 'o' y las constantes de un entero, BaseQueNoCasa; aqui habia
  // tres listas de nombres de tipos a mano, que dejaban pasar un TColor
  // 'hola' o un TCursor 3.5: medido en vivo el 7-oct-2026)

type
  TFormEnEdicion = record
    Dfm, Pas, DfmNombre, PasNombre, Marco: string;
    EsFmx, HayPas: Boolean;
    Doc: TStyleDoc;
    PasTexto, PasEnc: string;
    Tabla: TMetaTable;
    // lo que leyo el juez para cargar el form - ancestros, frames, el .pas de
    // la cadena -, con su huella (READ=): CambioDesdeQueSeJuzgo lo vuelve a
    // mirar antes de escribir (B5 rev6 de la 1.18.2)
    LeidoPorElJuez: TArray<TLeidoPorElJuez>;
  end;

  { Lo que la respuesta dice de UNA propiedad puesta (PonEnMemoria) }
  TValorPuesto = record
    Prop, Valor, Antes, Aviso: string;
    HabiaAntes, Comillas, Quitada, NadaQueQuitar: Boolean;
    // la tabla la acepto SIN hoja de tipo (la guarda la clase por codigo):
    // su valor lo juzga el cargador (CargaLoPuesto, H2 de Hermes, 1.18.2)
    SinJuez: Boolean;
    // lo que guarda el escritor del IDE (ConLasPropiedadesDelIde, 1.22.1):
    // nada, si es el valor que ya da la clase, u otro valor, si el componente
    // lo cambia al cargarse
    NoGuardada: Boolean;
    GuardadaComo: string;
    // una stored False de su clase: lo que el IDE escribe por ella (DSGN-167)
    // y la primera de esas propiedades, para su linea
    GuardadaEnOtras: Boolean;
    GuardadaEn, GuardadaEnProp: string;
  end;

  { Una propiedad compuesta aqui que el escritor del IDE guarda con otro valor:
    el suyo (ConLasPropiedadesDelIde, 1.22.1) }
  TGuardadaComo = record
    Prop, Valor: string;
    // una stored False de su clase, que el IDE no guarda por su nombre: Valor
    // son las lineas que escribe por ella y Donde la primera de sus propiedades
    EnOtras: Boolean;
    Donde: string;
  end;

{ ---- el form ---- }

procedure RecogeNombres(O: TStyleObj; L: TStringList; AConRutas: Boolean = False;
  const APrefijo: string = '');
begin
  if O.ObjName <> '' then
    L.Add(APrefijo + O.ObjName);
  // lo de dentro de un frame en linea es del frame: sus nombres no son del
  // form, que puede tener su propio Edit1 (el delete del frame se llevaba el
  // campo y las referencias del Edit1 del form: revision de la 1.17.0). Con
  // AConRutas van con su RUTA desde el form (Frame11.Edit1, la que toman set
  // y get, ObjetoDeNombre): el form los cambia en su bloque inherited
  if O.Clave = 'inline' then
  begin
    if AConRutas then
      for var K in O.Children do
        RecogeNombres(K, L, True, APrefijo + O.ObjName + '.');
    Exit;
  end;
  for var K in O.Children do
    RecogeNombres(K, L, AConRutas, APrefijo);
end;

function EstaEn(const ANombre: string; L: TStringList): Boolean;
begin
  for var S in L do
    if MismoIdentificador(S, ANombre) then
      Exit(True);
  Result := False;
end;

function NombreDe(O: TStyleObj): string;
begin
  if O = nil then
    Exit('?');
  Result := IfThen(O.ObjName <> '', O.ObjName, O.ClassName_);
end;

// el objeto mas de dentro que contiene la linea ALinea (1-based)
function ObjetoEnLinea(O: TStyleObj; ALinea: Integer): TStyleObj;
begin
  Result := nil;
  if (ALinea < O.StartLine) or (ALinea > O.EndLine) then
    Exit;
  Result := O;
  for var K in O.Children do
  begin
    var D := ObjetoEnLinea(K, ALinea);
    if D <> nil then
      Exit(D);
  end;
end;

// el frame en linea (inline) que contiene a O, el de mas fuera; nil si ninguno.
// Lo de dentro de un frame es del .dfm del frame
function InlineQueLoContiene(O: TStyleObj): TStyleObj;
begin
  Result := nil;
  var P := O.Parent;
  while P <> nil do
  begin
    if P.Clave = 'inline' then
      Result := P;
    P := P.Parent;
  end;
end;

// O es AAncestro o esta dentro de el
function EsDescendiente(O, AAncestro: TStyleObj): Boolean;
begin
  while O <> nil do
  begin
    if O = AAncestro then
      Exit(True);
    O := O.Parent;
  end;
  Result := False;
end;

{ El componente ANombre del FORM: sin bajar a lo de dentro de un frame en
  linea, que es del frame (los dos pueden tener su Edit1, y el del frame,
  delante en el fichero, se tomaba por el del form: set lo cambiaba, delete
  y el renombrado lo negaban). nil si no esta. }
function ObjetoDelForm(ADoc: TStyleDoc; const ANombre: string): TStyleObj;

  function Busca(O: TStyleObj): TStyleObj;
  begin
    if (O.ObjName <> '') and MismoIdentificador(O.ObjName, ANombre) then
      Exit(O);
    Result := nil;
    if O.Clave = 'inline' then
      Exit;
    for var K in O.Children do
    begin
      Result := Busca(K);
      if Result <> nil then
        Exit;
    end;
  end;

begin
  Result := nil;
  if (ADoc.Root <> nil) and (ANombre <> '') then
    Result := Busca(ADoc.Root);
end;

// el del form, y si no lo tiene, uno de dentro de un frame (lo que se puede
// cambiar alli, o negar con su motivo)
function ObjetoPorNombre(ADoc: TStyleDoc; const ANombre: string): TStyleObj;
begin
  Result := ObjetoDelForm(ADoc, ANombre);
  if Result = nil then
    Result := ADoc.ObjetoDeNombre(ANombre);
end;

{ La linea AI del form nombra a uno de ANombres como VALOR de una propiedad
  que guarda un componente (FocusControl = Label1, DataSource = DataSource1,
  Control = Button1 en un item de una coleccion), o a uno de dentro de el
  por su ruta (Frame11.Edit1: el cargador resuelve el nombre desde el form,
  tambien dentro del bloque de un frame en linea, FindNestedComponent).
  Una linea de evento no, ni un trozo de una cadena; ni una propiedad que la
  tabla sabe que no guarda un componente: en FMX un enumerado va sin
  prefijo, y Align = Client no nombra a un componente Client (se borraba en
  un delete y se reescribia en un renombrado: revision de la 1.17.0). De un
  item de una coleccion no se sabe la clase: manda el nombre. }
function ReferenciaDeLinea(ADoc: TStyleDoc; const AForm: TArray<TLineaForm>; AI: Integer;
  ANombres: TStringList; AJuez: TJuezDeReferencia; out ANombre: string): Boolean;
var
  Ev, Met, V, Cabeza: string;
begin
  Result := False;
  ANombre := '';
  // un evento por su nombre: lo que sabe la tabla lo dice AJuez abajo (un
  // evento no guarda un componente)
  if (AForm[AI].Clase <> clfPropiedad) or EventoDeObjeto(nil, '', ADoc.Lines[AI], Ev, Met) then
    Exit;
  V := AForm[AI].Valor;
  if not EsIdentificador(V, True) then
    Exit;
  Cabeza := V;
  if Pos('.', V) > 0 then
    Cabeza := Copy(V, 1, Pos('.', V) - 1);
  for var S in ANombres do
    if MismoIdentificador(S, Cabeza) then
    begin
      ANombre := S;
      Break;
    end;
  if ANombre = '' then
    Exit;
  if Assigned(AJuez) and (AForm[AI].Coleccion = 0) then
  begin
    var Dueno := ObjetoEnLinea(ADoc.Root, AI + 1);
    if (Dueno <> nil) and not AJuez(Dueno, AForm[AI].Prop) then
    begin
      ANombre := '';
      Exit;
    end;
  end;
  Result := True;
end;

{ AMetodo lleva en su identificador el Name de uno de ASub (Button1Click,
  ValidaButton1): entero - con un digito pegado detras no, si el nombre
  acaba en digito (Edit1 no es de Edit10Change) - y sin ser trozo de OTRO
  nombre del form que tambien esta (CreditEdit1 contiene Edit1). El nombre,
  o '' si no lleva ninguno. }
function NombreEnMetodo(const AMetodo: string; ASub, ATodos: TStringList): string;
type
  TTramo = record
    Ini, Fin: Integer;
    Nombre: string;
  end;
var
  Bajo, N: string;
  P, Detras: Integer;
  Tramos: TList<TTramo>;
  T: TTramo;
begin
  Result := '';
  Bajo := ClaveDeIdentificador(AMetodo);
  Tramos := TList<TTramo>.Create;
  try
    for var S in ATodos do
    begin
      N := ClaveDeIdentificador(S);
      if N = '' then
        Continue;
      P := Pos(N, Bajo);
      while P > 0 do
      begin
        Detras := P + Length(N);
        // por sus bordes de palabra, como escribe el IDE: delante el
        // principio, una mayuscula o un '_'; detras el final, una mayuscula o
        // un '_' (Ok no es de Lookup ni de OkayClick, que se borraban vacios
        // con el: revision de la 1.17.0; Edit1 no es de Edit10Change)
        if ((P = 1) or (AMetodo[P - 1] = '_') or AMetodo[P].IsUpper or not AMetodo[P].IsLetter) and
           ((Detras > Length(AMetodo)) or (AMetodo[Detras] = '_') or AMetodo[Detras].IsUpper) then
        begin
          T.Ini := P;
          T.Fin := Detras - 1;
          T.Nombre := S;
          Tramos.Add(T);
        end;
        P := Pos(N, Bajo, P + 1);
      end;
    end;
    for var A in Tramos do
    begin
      if not EstaEn(A.Nombre, ASub) then
        Continue;
      var Cubierto := False;
      for var B in Tramos do
        if (B.Fin - B.Ini > A.Fin - A.Ini) and (B.Ini <= A.Ini) and (B.Fin >= A.Fin) then
        begin
          Cubierto := True;
          Break;
        end;
      if not Cubierto then
        Exit(A.Nombre);
    end;
  finally
    Tramos.Free;
  end;
end;

// lo que hay entre APosIni y APosFin (una rutina) ocupa sus lineas solo: en
// la primera no hay nada delante y en la ultima nada detras
function SoloEnSusLineas(const ATexto: string; APosIni, APosFin: Integer): Boolean;
var
  K: Integer;
begin
  K := APosIni - 1;
  while (K >= 1) and not CharInSet(ATexto[K], [#10, #13]) do
  begin
    if ATexto[K] > ' ' then
      Exit(False);
    Dec(K);
  end;
  K := APosFin + 1;
  while (K <= Length(ATexto)) and not CharInSet(ATexto[K], [#10, #13]) do
  begin
    if ATexto[K] > ' ' then
      Exit(False);
    Inc(K);
  end;
  Result := True;
end;

function Cruza(AIni, AFin, BIni, BFin: Integer): Boolean;
begin
  Result := (AIni <= BFin) and (BIni <= AFin);
end;

{ En las lineas AIni..AFin de la clase no hay nada mas que la declaracion
  que se quita: ni otro miembro (salvo, si es un campo, los de su misma
  declaracion), ni una palabra de visibilidad, ni la cabecera o el end de la
  clase. Quitar lineas enteras se llevaria lo que las comparte (un
  'procedure A; procedure B;' escrito a mano). }
function LineasSoloSuyas(AClase: TTipoPas; AIni, AFin: Integer; ACampo: Boolean;
  const ANombre: string): Boolean;
begin
  Result := False;
  if Cruza(AIni, AFin, AClase.Linea, AClase.Linea) or
     Cruza(AIni, AFin, AClase.LineaFin, AClase.LineaFin) then
    Exit;
  for var S in AClase.Secciones do
    if Cruza(AIni, AFin, S.Linea, S.Linea) then
      Exit;
  for var P in AClase.Propiedades do
    if Cruza(AIni, AFin, P.Linea, P.Linea) then
      Exit;
  for var C in AClase.Campos do
    if Cruza(AIni, AFin, C.LineaIni, C.LineaFin) and not (ACampo and (C.LineaFin = AFin)) then
      Exit;
  for var R in AClase.Rutinas do
    if Cruza(AIni, AFin, R.LineaIni, R.LineaFin) and
       not (not ACampo and MismoIdentificador(R.Nombre, ANombre)) then
      Exit;
  Result := True;
end;

(* En las lineas AIni..AFin (0-based, contadas como LineaDePosicion) de ATexto
  no hay una directiva, ni un comentario de bloque que entre desde antes o
  siga despues: quitarlas enteras dejaria un {$IFDEF} sin su {$ENDIF} o un
  comentario sin cerrar (revision de la 1.17.0). AClases: ClasesPascal. *)
function LineasLimpias(const ATexto: string; const AClases: TArray<TClasePascal>;
  AIni, AFin: Integer): Boolean;
var
  K, L, P0, P1: Integer;
begin
  P0 := 0;
  if AIni = 0 then
    P0 := 1;
  P1 := Length(ATexto) + 1;
  L := 0;
  for K := 1 to Length(ATexto) do
    if (ATexto[K] = #10) or ((ATexto[K] = #13) and ((K = Length(ATexto)) or (ATexto[K + 1] <> #10))) then
    begin
      if L = AFin then
      begin
        P1 := K;
        Break;
      end;
      Inc(L);
      if L = AIni then
        P0 := K + 1;
    end;
  if P0 = 0 then
    Exit(True);
  for K := P0 to Min(P1, Length(ATexto)) do
    if AClases[K] = cpDirectiva then
      Exit(False);
  if (P0 > 1) and (AClases[P0 - 1] = cpComentario) then
    Exit(False);
  if (P1 <= Length(ATexto)) and (AClases[P1] = cpComentario) then
    Exit(False);
  Result := True;
end;

function Donde(const AFichero: string; ALinea: Integer): string;
begin
  Result := AFichero + ':' + IntToStr(ALinea);
end;

{ Donde nombra el codigo de APasTexto a alguno de ANombres - se lista, no se
  juzga (lo juzga el compilador) -, sin las lineas de AFuera (las de sus
  campos; nil = ninguna) y con el tope de MAX_USOS. Lo pide el analizador
  sobre la unidad de antes, y el borrado sobre la que QUEDA: daba las
  lineas de antes, y quitar el campo por encima las movia (3.8 de la
  1.18.0, Hermes). }
function UsosEnCodigo(const APasTexto, APasNombre: string; const ANombres: TArray<string>;
  AFuera: TDictionary<Integer, Boolean>): TArray<string>;
var
  Usos: TStringList;
  Codigo: string;
  Pas: TArray<string>;
begin
  Usos := TStringList.Create;
  try
    // las mismas posiciones y saltos que el texto, sin comentarios ni cadenas
    Codigo := CodigoPascal(APasTexto);
    Pas := SplitToLines(APasTexto);
    for var S in ANombres do
      for var Mt in TRegEx.Matches(Codigo, PatronIdentEntero(S), [roIgnoreCase]) do
      begin
        var L := LineaDePosicion(Codigo, Mt.Index) - 1;
        if ((AFuera <> nil) and AFuera.ContainsKey(L)) or (L > High(Pas)) then
          Continue;
        var Uso := Donde(APasNombre, L + 1) + ': ' + Copy(Trim(Pas[L]), 1, 120);
        if Usos.IndexOf(Uso) < 0 then
          Usos.Add(Uso);
      end;
    if Usos.Count > MAX_USOS then
    begin
      var Mas := Usos.Count - MAX_USOS;
      while Usos.Count > MAX_USOS do
        Usos.Delete(Usos.Count - 1);
      Usos.Add(MsgFmt(SF_DESIGNER_USOS_MAS_FMT, [Mas]));
    end;
    Result := Usos.ToStringArray;
  finally
    Usos.Free;
  end;
end;

{ ---- el analizador ---- }

function AnalizaImpacto(ADoc: TStyleDoc; AObj: TStyleObj; ASoloEl: Boolean;
  const APasTexto, APasNombre: string; AJuez: TJuezDeReferencia = nil; ATabla: TMetaTable = nil): TImpacto;
var
  Sub, Todos, Vistos: TStringList;
  Dentro, Fuera: TDictionary<string, string>;
  Ini, Fin, I, K: Integer;
  Ev, Met, Nom, Quien, Codigo: string;
  Unidad: TUnidadPas;
  Clase: TTipoPas;
  LineasFuera: TDictionary<Integer, Boolean>;
  Form: TArray<TLineaForm>;
  Clases: TArray<TClasePascal>;
  ClasesDelForm: TArray<string>;
begin
  Result := Default(TImpacto);
  Result.Componente := AObj.ObjName;
  Result.Clase := AObj.ClassName_;
  Sub := TStringList.Create;
  Todos := TStringList.Create;
  Vistos := TStringList.Create;
  Dentro := TDictionary<string, string>.Create;
  Fuera := TDictionary<string, string>.Create;
  LineasFuera := TDictionary<Integer, Boolean>.Create;
  try
    if ASoloEl then
      Sub.Add(AObj.ObjName)
    else
      RecogeNombres(AObj, Sub);
    RecogeNombres(ADoc.Root, Todos);
    Result.Nombres := Sub.ToStringArray;
    Ini := AObj.StartLine - 1;
    Fin := AObj.EndLine - 1;
    // el form: los eventos de dentro y de fuera del subarbol, y las lineas
    // de fuera que lo nombran - por EL lector de las lineas: un trozo de una
    // cadena no es una propiedad
    Form := LineasDeForm(ADoc.Lines);
    // que linea es un evento: la tabla, por la clase de su objeto (la raiz,
    // por la que la juzga), como check-binding
    ClasesDelForm := ClasesDeLasLineas(Form, JuezDeLaRaiz(ATabla, Form, UnidadDeDesigner(ADoc.Path), APasTexto));
    for I := 0 to High(ADoc.Lines) do
      if (Form[I].Clase = clfPropiedad) and EventoDeObjeto(ATabla, ClasesDelForm[I], ADoc.Lines[I], Ev, Met) then
      begin
        var Dueno := ObjetoEnLinea(ADoc.Root, I + 1);
        Quien := NombreDe(Dueno) + '.' + Ev;
        if (I >= Ini) and (I <= Fin) and (not ASoloEl or (Dueno = AObj)) then
          Dentro.TryAdd(ClaveDeIdentificador(Met), Quien)
        else
          Fuera.TryAdd(ClaveDeIdentificador(Met), Quien);
      end
      else if ((I < Ini) or (I > Fin)) and ReferenciaDeLinea(ADoc, Form, I, Sub, AJuez, Nom) then
        Result.Referencias := Result.Referencias + [I];
    if APasTexto = '' then
      Exit;
    Unidad := LeeFuentePascal(APasTexto);
    try
      Clase := Unidad.Clase(ADoc.Root.ClassName_);
      if Clase = nil then
      begin
        Result.Nota := MsgFmt(SN_DESIGNER_IMPACTO_SIN_CLASE_FMT, [ADoc.Root.ClassName_, APasNombre]);
        Exit;
      end;
      // las mismas posiciones y saltos que el texto, sin comentarios ni cadenas
      Codigo := CodigoPascal(APasTexto);
      // y que es cada caracter: una directiva o un comentario que sigue fuera
      // de unas lineas no se quitan con ellas (LineasLimpias)
      Clases := ClasesPascal(APasTexto);
      // los campos publicados de esos nombres
      for K := 0 to High(Clase.Campos) do
      begin
        var C := Clase.Campos[K];
        if C.DeClase or not (C.Visibilidad in [vpDefecto, vpPublicada]) or not EstaEn(C.Nombre, Sub) then
          Continue;
        var CP: TCampoPropio;
        CP.Nombre := C.Nombre;
        CP.Ini := C.LineaIni;
        CP.Fin := C.LineaFin;
        CP.Todos := 0;
        for var C2 in Clase.Campos do
          if C2.LineaFin = C.LineaFin then
            Inc(CP.Todos);
        CP.Solo := LineasSoloSuyas(Clase, CP.Ini, CP.Fin, True, C.Nombre);
        CP.Limpia := LineasLimpias(APasTexto, Clases, CP.Ini, CP.Fin);
        Result.Campos := Result.Campos + [CP];
        for var L := CP.Ini to CP.Fin do
          LineasFuera.AddOrSetValue(L, True);
      end;
      // los metodos de la clase que son suyos: los ata un evento suyo, o
      // llevan su nombre
      for K := 0 to High(Clase.Rutinas) do
      begin
        var R := Clase.Rutinas[K];
        if R.DeClase or not MatchText(R.Rutina, ['procedure', 'function']) then
          Continue;
        if Vistos.IndexOf(ClaveDeIdentificador(R.Nombre)) >= 0 then
          Continue;
        Vistos.Add(ClaveDeIdentificador(R.Nombre));
        var MP := Default(TMetodoPropio);
        MP.Nombre := R.Nombre;
        Dentro.TryGetValue(ClaveDeIdentificador(R.Nombre), MP.Atado);
        MP.PorNombre := NombreEnMetodo(R.Nombre, Sub, Todos) <> '';
        if (MP.Atado = '') and not MP.PorNombre then
          Continue;
        MP.DeclIni := R.LineaIni;
        MP.DeclFin := R.LineaFin;
        MP.ImplIni := -1;
        MP.ImplFin := -1;
        MP.Linea := R.Linea + 1;
        MP.EnSusLineas := LineasSoloSuyas(Clase, MP.DeclIni, MP.DeclFin, False, R.Nombre) and
          LineasLimpias(APasTexto, Clases, MP.DeclIni, MP.DeclFin);
        var NDecl := 0;
        for var R2 in Clase.Rutinas do
          if MismoIdentificador(R2.Nombre, R.Nombre) then
            Inc(NDecl);
        var Impls: TArray<TCuerpoPas> := [];
        for var C in Unidad.Cuerpos do
          if MismoIdentificador(C.Nombre, Clase.Nombre + '.' + R.Nombre) then
            Impls := Impls + [C];
        // uno sobrecargado ni se toca ni se juzga: no se sabe de cual se habla
        if (NDecl > 1) or (Length(Impls) > 1) then
          MP.Compartido := MsgText(SF_DESIGNER_SOBRECARGADO)
        else if Fuera.TryGetValue(ClaveDeIdentificador(R.Nombre), Quien) then
          MP.Compartido := MsgFmt(SF_DESIGNER_LO_ATA_FMT, [Quien]);
        var PosIni := 0;
        var PosFin := -1;
        if Length(Impls) = 1 then
        begin
          var C := Impls[0];
          MP.ImplIni := C.Linea;
          MP.ImplFin := C.LineaFin;
          MP.Linea := C.Linea + 1;
          PosIni := C.PosIni;
          PosFin := C.PosFin;
          // un comentario tambien es contenido: el IDE tampoco borra un
          // manejador comentado - y uno entre la cabecera y el begin tambien
          // (se borraba con el: revision de la 1.17.0)
          MP.ConCuerpo := C.ConLocales or
            (Trim(Copy(APasTexto, C.CuerpoIni, C.CuerpoFin - C.CuerpoIni + 1)) <> '');
          for var P := C.PosIni to Min(C.CuerpoIni, Length(Clases)) - 1 do
            if Clases[P] in [cpComentario, cpLinea, cpDirectiva] then
            begin
              MP.ConCuerpo := True;
              Break;
            end;
          MP.EnSusLineas := MP.EnSusLineas and SoloEnSusLineas(APasTexto, C.PosIni, C.PosFin) and
            LineasLimpias(APasTexto, Clases, C.Linea, C.LineaFin);
        end;
        // usado por otro codigo de la unidad: fuera de su declaracion y de
        // su implementacion
        if MP.Compartido = '' then
          for var Mt in TRegEx.Matches(Codigo, PatronIdentEntero(R.Nombre), [roIgnoreCase]) do
          begin
            var L := LineaDePosicion(Codigo, Mt.Index) - 1;
            if ((L >= MP.DeclIni) and (L <= MP.DeclFin)) or
               ((Mt.Index >= PosIni) and (Mt.Index <= PosFin)) then
              Continue;
            MP.Compartido := MsgFmt(SF_DESIGNER_LO_USA_FMT, [Donde(APasNombre, L + 1)]);
            Break;
          end;
        Result.Metodos := Result.Metodos + [MP];
      end;
      // donde lo usa el codigo: se lista, no se juzga (el compilador)
      Result.Usos := UsosEnCodigo(APasTexto, APasNombre, Sub.ToStringArray, LineasFuera);
    finally
      Unidad.Free;
    end;
  finally
    LineasFuera.Free;
    Fuera.Free;
    Dentro.Free;
    Vistos.Free;
    Todos.Free;
    Sub.Free;
  end;
end;

{ ---- los planes, sobre los textos ---- }

function PlanDeBorrado(ADoc: TStyleDoc; AObj: TStyleObj;
  const APasTexto, APasNombre: string; out AImp: TImpacto;
  out ADfm, APas: string; AJuez: TJuezDeReferencia = nil; ATabla: TMetaTable = nil): string;
var
  Bloquean: string;
  N, I, K: Integer;
  Fuera, Quita: TArray<Boolean>;
  Lista: TList<string>;
  PasLineas, PasSaltos, CodLineas: TArray<string>;
  NuevasL, NuevasS: TList<string>;
  M: TMatch;
begin
  Result := '';
  ADfm := '';
  APas := APasTexto;
  AImp := AnalizaImpacto(ADoc, AObj, False, APasTexto, APasNombre, AJuez, ATabla);
  if AImp.Nota <> '' then
    Exit(MsgFmt(SR_DESIGNER_EDIT_SIN_CLASE_FMT, [ADoc.Root.ClassName_, APasNombre]));
  // la puerta: un metodo propio, exclusivo y con cuerpo
  Bloquean := '';
  N := 0;
  for var Mt in AImp.Metodos do
    if (Mt.Compartido = '') and Mt.ConCuerpo then
    begin
      Inc(N);
      Bloquean := Bloquean + MsgFmt(SF_DESIGNER_METODO_LINEA_FMT, [Mt.Nombre,
        Donde(APasNombre, Mt.Linea), IfThen(Mt.Atado <> '', Mt.Atado, MsgText(SF_DESIGNER_POR_SU_NOMBRE))]);
    end;
  if N > 0 then
    Exit(MsgFmt(SR_DESIGNER_DELETE_BLOQUEADO_FMT, [NombreDe(AObj), N, APasNombre, Bloquean]));
  // el form: el bloque entero y las lineas que lo nombran
  SetLength(Fuera, Length(ADoc.Lines));
  for I := AObj.StartLine - 1 to AObj.EndLine - 1 do
    Fuera[I] := True;
  for I in AImp.Referencias do
    Fuera[I] := True;
  Lista := TList<string>.Create;
  try
    for I := 0 to High(ADoc.Lines) do
      if not Fuera[I] then
        Lista.Add(ADoc.Lines[I]);
    ADfm := ADoc.TextoDe(Lista.ToArray);
  finally
    Lista.Free;
  end;
  // la unidad: los campos y los manejadores vacios exclusivos, cada linea
  // que se queda con su salto
  PasLineas := SplitToLinesConSalto(APasTexto, PasSaltos);
  // el mismo texto sin comentarios ni cadenas, con las mismas posiciones:
  // donde se busca un nombre
  CodLineas := SplitToLines(CodigoPascal(APasTexto));
  SetLength(Quita, Length(PasLineas));
  for var C in AImp.Campos do
  begin
    // los de la misma declaracion que tambien se van
    var Iguales := 0;
    var Primera := C.Ini;
    for var C2 in AImp.Campos do
      if C2.Fin = C.Fin then
      begin
        Inc(Iguales);
        Primera := Min(Primera, C2.Ini);
      end;
    if Iguales = C.Todos then
    begin
      // lineas enteras: lo que las comparta se iria con ellas
      if not C.Solo then
        Exit(MsgFmt(SR_DESIGNER_CAMPO_COMPARTIDO_FMT, [C.Nombre, Donde(APasNombre, C.Ini + 1)]));
      if not C.Limpia then
        Exit(MsgFmt(SR_DESIGNER_CAMPO_LINEA_SUCIA_FMT, [C.Nombre, Donde(APasNombre, C.Ini + 1)]));
      for K := Primera to C.Fin do
        Quita[K] := True;
      Continue;
    end;
    // 'A, B: TButton;' y se va uno: solo su nombre, con su coma
    M := TRegEx.Match(CodLineas[C.Ini], PatronIdentEntero(C.Nombre) + '\s*,\s*', [roIgnoreCase]);
    if not M.Success then
      M := TRegEx.Match(CodLineas[C.Ini], '\s*,\s*' + PatronIdentEntero(C.Nombre), [roIgnoreCase]);
    if not M.Success then
      Exit(MsgFmt(SR_DESIGNER_CAMPO_COMPARTIDO_FMT, [C.Nombre, Donde(APasNombre, C.Ini + 1)]));
    // las dos vistas a la vez: otro campo de la misma linea se busca despues
    PasLineas[C.Ini] := Copy(PasLineas[C.Ini], 1, M.Index - 1) +
      Copy(PasLineas[C.Ini], M.Index + M.Length, MaxInt);
    CodLineas[C.Ini] := Copy(CodLineas[C.Ini], 1, M.Index - 1) +
      Copy(CodLineas[C.Ini], M.Index + M.Length, MaxInt);
  end;
  for K := 0 to High(AImp.Metodos) do
  begin
    var Mt := AImp.Metodos[K];
    if (Mt.Compartido <> '') or Mt.ConCuerpo then
      Continue;
    // uno que comparte sus lineas con otro codigo se queda (y se dice)
    if not Mt.EnSusLineas then
      Continue;
    AImp.Metodos[K].SeBorra := True;
    if Mt.DeclIni >= 0 then
      for I := Mt.DeclIni to Mt.DeclFin do
        Quita[I] := True;
    if Mt.ImplIni >= 0 then
    begin
      for I := Mt.ImplIni to Mt.ImplFin do
        Quita[I] := True;
      // y la linea en blanco que el IDE le deja delante
      if (Mt.ImplIni > 0) and (Trim(PasLineas[Mt.ImplIni - 1]) = '') then
        Quita[Mt.ImplIni - 1] := True;
    end;
  end;
  NuevasL := TList<string>.Create;
  NuevasS := TList<string>.Create;
  try
    for I := 0 to High(PasLineas) do
      if not Quita[I] then
      begin
        NuevasL.Add(PasLineas[I]);
        NuevasS.Add(PasSaltos[I]);
      end;
    APas := UneConSusSaltos(NuevasL.ToArray, NuevasS.ToArray);
  finally
    NuevasS.Free;
    NuevasL.Free;
  end;
end;

function PlanDeRenombre(ADoc: TStyleDoc; AObj: TStyleObj;
  const ANuevo, APasTexto, APasNombre: string; const ATextos: TArray<string>;
  out AImp: TImpacto; out ADfm, APas: string; AJuez: TJuezDeReferencia = nil;
  ATabla: TMetaTable = nil): string;
var
  Lineas, PasLineas, PasSaltos, Nuevas: TArray<string>;
  I, Delta: Integer;
  Nom, Clave, NomObj, ClaseObj, Resto, V, Txt: string;
  Uno: TStringList;
  M: TMatch;
  Form: TArray<TLineaForm>;
begin
  Result := '';
  AImp := AnalizaImpacto(ADoc, AObj, True, APasTexto, APasNombre, AJuez, ATabla);
  Lineas := Copy(ADoc.Lines);
  Form := LineasDeForm(ADoc.Lines);
  // la cabecera: solo el nombre, por EL lector y EL compositor de esa linea;
  // lo de detras de la clase como esta (un [2]). Aqui habia una regex propia
  I := AObj.StartLine - 1;
  if not LineaDeObjeto(Lineas[I], Clave, NomObj, ClaseObj, Resto) or
     not MismoIdentificador(NomObj, AObj.ObjName) then
    Exit(MsgFmt(SR_DESIGNER_COMPONENTE_NO_ESTA_FMT, [AObj.ObjName, '?', '']));
  Lineas[I] := LeadingWhite(Lineas[I]) + ComponeLineaDeObjeto(Clave, ANuevo, ClaseObj) + Resto;
  // las lineas del form que lo nombran, de dentro y de fuera de su bloque
  // (las que guardan un componente: AJuez), con el nombre nuevo y lo de
  // detras de su ruta (Frame11.Edit1)
  AImp.Referencias := [];
  Uno := TStringList.Create;
  try
    Uno.Add(AObj.ObjName);
    for I := 0 to High(Lineas) do
      if (I <> AObj.StartLine - 1) and ReferenciaDeLinea(ADoc, Form, I, Uno, AJuez, Nom) then
      begin
        V := ANuevo;
        if Pos('.', Form[I].Valor) > 0 then
          V := ANuevo + Copy(Form[I].Valor, Pos('.', Form[I].Valor), MaxInt);
        Lineas[I] := LineasDePropiedad(LeadingWhite(Lineas[I]), Form[I].Prop, [V])[0];
        AImp.Referencias := AImp.Referencias + [I];
      end;
  finally
    Uno.Free;
  end;
  // su texto, si era su nombre, sigue al nombre: lo que hace en el IDE el
  // SetName de las clases que lo hacen (ATextos; el Caption que dejo el
  // insert, el Text de un edit). Leido entero, el de varias lineas tambien,
  // y escrito como el IDE (TrozosDeLiteral); lo ultimo, que cambia el largo
  for var Prop in ATextos do
  begin
    var PIni, PFin: Integer;
    if ADoc.PropLines(AObj, Prop, PIni, PFin) and
       LeeLiteralDeForm(ValorEnteroDe(ADoc.Lines, Form, PIni), Txt) and (Txt = AObj.ObjName) then
    begin
      Nuevas := LineasDePropiedad(LeadingWhite(ADoc.Lines[PIni]), Prop, TrozosDeLiteral(ANuevo));
      Delete(Lineas, PIni, PFin - PIni + 1);
      Insert(Nuevas, Lineas, PIni);
      // las referencias de debajo se mueven con lo que cambio el largo
      Delta := Length(Nuevas) - (PFin - PIni + 1);
      for var R := 0 to High(AImp.Referencias) do
        if AImp.Referencias[R] > PFin then
          Inc(AImp.Referencias[R], Delta);
      Break; // una clase publica su texto como Caption o como Text
    end;
  end;
  ADfm := ADoc.TextoDe(Lineas);
  // el campo: su nombre en su declaracion, nada mas
  APas := APasTexto;
  for var C in AImp.Campos do
    if MismoIdentificador(C.Nombre, AObj.ObjName) then
    begin
      PasLineas := SplitToLinesConSalto(APasTexto, PasSaltos);
      // el nombre en el codigo de su linea, no en un comentario delante
      M := TRegEx.Match(SplitToLines(CodigoPascal(APasTexto))[C.Ini],
        PatronIdentEntero(AObj.ObjName), [roIgnoreCase]);
      if not M.Success then
        Exit(MsgFmt(SR_DESIGNER_CAMPO_COMPARTIDO_FMT, [AObj.ObjName, Donde(APasNombre, C.Ini + 1)]));
      PasLineas[C.Ini] := Copy(PasLineas[C.Ini], 1, M.Index - 1) + ANuevo +
        Copy(PasLineas[C.Ini], M.Index + M.Length, MaxInt);
      APas := UneConSusSaltos(PasLineas, PasSaltos);
      Break;
    end;
end;

{ ---- abrir, comprobar y escribir ---- }

{ La tabla de clases del marco de F (la del Delphi activo): '' y F.Tabla, o
  la negativa de por que no hay. Aparte de abrir el form: quien abre CON el
  cerrojo de escritura (AbreFormParaJuzgar) la carga despues, fuera de el -
  la primera vez se genera y tarda, y bloquearia a todos los escritores. }
function PonTabla(var F: TFormEnEdicion): string;
var
  Falta: TFaltaTabla;
begin
  Result := '';
  F.Tabla := MetaTable(F.EsFmx, Falta);
  if F.Tabla = nil then
    Result := Falta.Negativa;
end;

function AbreFormNucleo(const APath: string; ANecesitaPas, ANecesitaTabla: Boolean;
  var F: TFormEnEdicion): string;
var
  Unidad: TUnidadPas;
begin
  Result := WriteTargetDenied(APath);
  if Result <> '' then
    Exit;
  if not TFile.Exists(APath) then
    Exit(NoEsFichero(APath, MsgFmt(SR_NO_EXISTE_FMT, [APath])));
  if not EsRutaDeDesigner(APath) then
    Exit(MsgText(SR_DESIGNER_NOT_FORM));
  F.Dfm := APath;
  F.DfmNombre := TPath.GetFileName(APath);
  F.EsFmx := EsDesignerFmx(APath);
  F.Marco := IfThen(F.EsFmx, 'FMX', 'VCL');
  if IsBinaryDesignerFile(APath) then
    Exit(MsgFmt(SR_DESIGNER_EDIT_BINARIO_FMT, [F.DfmNombre]));
  // por lineas como las lee el parser del IDE, o nada: con el '>' de una
  // coleccion en su linea, set escribia un Left nuevo en vez de cambiar el
  // que habia (DSGN-160, 3b del censo de jueces)
  try
    Result := TStyleDoc.Lee(APath, F.Doc);
  except
    on E: Exception do
      Exit(MsgEnvuelve(SR_DESIGNER_ILEGIBLE_FMT, E.Message, [APath, E.Message]));
  end;
  if Result <> '' then
    Exit;
  if (F.Doc.Root = nil) or (F.Doc.Root.ClassName_ = '') then
    Exit(MsgText(SR_DESIGNER_EMPTY));
  // su unidad: la del mismo nombre, la que crea el IDE
  F.Pas := UnidadDeDesigner(APath);
  F.PasNombre := TPath.GetFileName(F.Pas);
  if ANecesitaPas then
  begin
    if not TFile.Exists(F.Pas) then
      Exit(MsgFmt(SR_DESIGNER_EDIT_SIN_UNIDAD_FMT, [F.DfmNombre, F.PasNombre]));
    Result := WriteTargetDenied(F.Pas);
    if Result <> '' then
      Exit;
    F.HayPas := True;
  end
  else
    F.HayPas := TFile.Exists(F.Pas) and (ReadPathDenied(F.Pas) = '');
  if F.HayPas then
  begin
    F.PasTexto := PatchLoadText(F.Pas, F.PasEnc);
    if ANecesitaPas then
    begin
      Unidad := LeeFuentePascal(F.PasTexto);
      try
        if Unidad.Clase(F.Doc.Root.ClassName_) = nil then
          Exit(MsgFmt(SR_DESIGNER_EDIT_SIN_CLASE_FMT, [F.Doc.Root.ClassName_, F.PasNombre]));
      finally
        Unidad.Free;
      end;
    end;
  end;
  if ANecesitaTabla then
    Result := PonTabla(F);
end;

function AbreForm(const APath: string; ANecesitaPas, ANecesitaTabla: Boolean;
  out F: TFormEnEdicion): string;
begin
  F := Default(TFormEnEdicion);
  Result := AbreFormNucleo(APath, ANecesitaPas, ANecesitaTabla, F);
  if Result <> '' then
    FreeAndNil(F.Doc);
end;

{ Los nombres de AL separados por comas, hasta MAX_NOMBRES; si hay mas, lo
  dice: cuantos faltan y donde verlos (command=tree). Sin topes callados (H4
  de Hermes, 1.18.2: en un form de 161 componentes la lista de 40 parecia la
  entera). LA forma de las dos listas de nombres del disenador (los del form,
  los que caben en una referencia). }
function NombresConTope(AL: TStringList): string;
var
  N: Integer;
begin
  N := AL.Count;
  while AL.Count > MAX_NOMBRES do
    AL.Delete(AL.Count - 1);
  Result := string.Join(', ', AL.ToStringArray);
  if N > MAX_NOMBRES then
    Result := Result + MsgFmt(SF_DESIGNER_Y_MAS_NOMBRES_FMT, [N - MAX_NOMBRES]);
end;

function NombresDelForm(ADoc: TStyleDoc): string;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    RecogeNombres(ADoc.Root, L, True);
    Result := NombresConTope(L);
  finally
    L.Free;
  end;
end;

function BuscaComponente(const F: TFormEnEdicion; const AName: string;
  out AObj: TStyleObj): string;
begin
  Result := '';
  AObj := ObjetoPorNombre(F.Doc, AName.Trim);
  if AObj = nil then
    Result := MsgFmt(SR_DESIGNER_COMPONENTE_NO_ESTA_FMT, [AName.Trim, F.DfmNombre, NombresDelForm(F.Doc)]);
end;

// lo que no se borra, ni se renombra, ni se mueve desde este form
function QueNoSeToca(const F: TFormEnEdicion; AObj: TStyleObj): string;
begin
  Result := '';
  if AObj = F.Doc.Root then
    Exit(MsgFmt(SR_DESIGNER_RAIZ_FMT, [NombreDe(AObj)]));
  // lo de un frame en linea antes que lo heredado: su bloque es un inherited
  // del frame, no del ancestro del form
  var Fr := InlineQueLoContiene(AObj);
  if Fr <> nil then
    Exit(MsgFmt(SR_DESIGNER_DENTRO_DE_INLINE_FMT, [NombreDe(AObj), NombreDe(Fr)]));
  if AObj.Clave = 'inherited' then
    Exit(MsgFmt(SR_DESIGNER_HEREDADO_FMT, [NombreDe(AObj)]));
end;

function ClaseDeJuez(const F: TFormEnEdicion; AObj: TStyleObj; out AClsId: string): string; forward;
// las piezas de set que insert con propiedades usa (3.10): viven con set
function PonEnMemoria(const F: TFormEnEdicion; const ANombre, AProp, AValor: string;
  out AInfo: TValorPuesto): string; forward;
function ParesDeProps(const AProps: string; out AProps_, AValores: TArray<string>): string; forward;
procedure PonValorPuesto(AObj: TJSONObject; const ANombre: string; const AInfo: TValorPuesto); forward;
function CargaLoPuesto(var F: TFormEnEdicion; const ANombre: string;
  const AInfos: array of TValorPuesto; out ANota: string): string; forward;
// EL movimiento de un bloque de form (set parent= y el orden, 3.11)
function ConBloqueMovido(const ALineas, ABloque: TArray<string>; AIni, ALargo: Integer;
  var ADest: Integer): TArray<string>; forward;
// el form abierto para preguntar al juez del orden y escribir despues, y donde
// deja el IDE un bloque nuevo entre sus hermanos (3.11: insert y set parent=)
function AbreFormParaJuzgar(const APath: string; ANecesitaPas, ANecesitaTabla: Boolean;
  out F: TFormEnEdicion; out AAntes, AAntesPas: TArray<Byte>): string; forward;
function CambioDesdeQueSeJuzgo(const F: TFormEnEdicion; const AAntes, AAntesPas: TArray<Byte>): string; forward;
function DondeLoDejaElIde(var F: TFormEnEdicion; const ALineas: TArray<string>;
  const ANomObj, ANomPadre: string; var AIni: Integer; ALargo: Integer; ASinTabOrder: Boolean;
  out ANota: string; out ATabOrder: Integer): TArray<string>; forward;
// la mezcla con lo que guarda el escritor del IDE (1.22.1) la usa
function Resangra(const S: string; ADelta: Integer): string; forward;

{ P puede recibir un control: el form, o en VCL un control con ventana
  (TWinControl por ascendencia: David, 4-oct-2026) y en FMX un control.
  AMueve: lo pregunta set parent= (la salida a mano es mover el bloque; el
  campo y la unidad ya estan), no insert. }
function PadreQueNoVale(const F: TFormEnEdicion; P: TStyleObj; AMueve: Boolean): string;
var
  Id: string;
begin
  Result := '';
  var Fr := InlineQueLoContiene(P);
  if (Fr = nil) and (P.Clave = 'inline') then
    Fr := P;
  if Fr <> nil then
    Exit(MsgFmt(SR_DESIGNER_DENTRO_DE_INLINE_FMT, [NombreDe(P), NombreDe(Fr)]));
  if P = F.Doc.Root then
  begin
    // la raiz los recibe si es un form o un frame; un data module no (un
    // TButton entraba en un TDataModule: revision de la 1.17.0). Lo que no
    // se sabe de ella no se niega
    if (ClaseDeJuez(F, P, Id) = '') and
       not (F.Tabla.Desciende(Id, IfThen(F.EsFmx, ID_FMX_CONTROL, ID_VCL_WINCONTROL)) or
            (F.EsFmx and F.Tabla.Desciende(Id, ID_FMX_FORMA))) then
      if F.EsFmx then
        Exit(MsgFmt(SR_DESIGNER_PADRE_FMX_FMT, [NombreDe(P), P.ClassName_]))
      else
        Exit(MsgFmt(SR_DESIGNER_PADRE_VCL_FMT, [NombreDe(P), P.ClassName_]));
    Exit;
  end;
  if not F.Tabla.ClaseDeNombre(P.ClassName_, Id) then
    Exit(MsgFmt(SR_DESIGNER_CLASE_SIN_TABLA_FMT, [NombreDe(P), P.ClassName_, F.Marco,
      MsgText(SF_DESIGNER_QUE_CONTENEDOR),
      MsgFmt(SF_DESIGNER_VIA_CONTENEDOR_FMT, [MsgText(IfThen(AMueve, SF_DESIGNER_MOVER_A_MANO,
        SF_DESIGNER_A_MANO))])]));
  if F.EsFmx then
  begin
    if not F.Tabla.Desciende(Id, ID_FMX_CONTROL) then
      Exit(MsgFmt(SR_DESIGNER_PADRE_FMX_FMT, [NombreDe(P), P.ClassName_]));
  end
  // y que su clase los reciba en el disenador: csAcceptsControls en el
  // ControlStyle de su constructor (un TPageControl no, que solo guarda sus
  // paginas: lo de dentro se perdia al guardar el form en el IDE; un
  // TButton tampoco. Revision de la 1.17.0)
  else if not F.Tabla.Desciende(Id, ID_VCL_WINCONTROL) or not F.Tabla.AceptaControles(Id) then
    Exit(MsgFmt(SR_DESIGNER_PADRE_VCL_FMT, [NombreDe(P), P.ClassName_]));
end;

{ Los componentes que el form HEREDA de ancestros del proyecto (donde esten:
  los localiza el motor, Lsp.Herencia), como pares nombre=clase ancestro:
  TWriter no escribe en el .dfm del heredado un componente sin cambios, ni la
  unidad su campo, asi que ni el form ni la clase los nombran. Definida mas
  abajo. }
function NombresHeredados(const F: TFormEnEdicion; AClase: TTipoPas): TArray<string>; forward;

// '' si ANombre esta libre en el form y en su clase; si no, quien lo tiene.
// AYo: el componente que se renombra (su propio nombre y su campo no cuentan).
// AHeredados: NombresHeredados - un nombre del ancestro tambien esta cogido
// (insert en un TForm2 heredado elegia el Button1 de TForm1, y el form
// saltaba EComponentError al crearse: 3.2 de la 1.18.0)
function NombreOcupado(ADoc: TStyleDoc; AClase: TTipoPas; const ANombre: string;
  AYo: TStyleObj; const AHeredados: TArray<string>): string;
begin
  Result := '';
  var O := ObjetoDelForm(ADoc, ANombre);
  if (O <> nil) and (O <> AYo) then
    Exit(MsgText(SF_DESIGNER_OCUPA_COMPONENTE));
  if AClase = nil then
    Exit;
  if MismoIdentificador(AClase.Nombre, ANombre) then
    Exit(MsgText(SF_DESIGNER_OCUPA_CLASE));
  for var C in AClase.Campos do
    if MismoIdentificador(C.Nombre, ANombre) and
       not ((AYo <> nil) and MismoIdentificador(C.Nombre, AYo.ObjName)) then
      Exit(MsgFmt(SF_DESIGNER_OCUPA_CAMPO_FMT, [AClase.Nombre]));
  for var R in AClase.Rutinas do
    if MismoIdentificador(R.Nombre, ANombre) then
      Exit(MsgFmt(SF_DESIGNER_OCUPA_METODO_FMT, [AClase.Nombre]));
  for var P in AClase.Propiedades do
    if MismoIdentificador(P.Nombre, ANombre) then
      Exit(MsgFmt(SF_DESIGNER_OCUPA_PROPIEDAD_FMT, [AClase.Nombre]));
  for var H in AHeredados do
    if MismoIdentificador(H.Substring(0, H.IndexOf('=')), ANombre) then
      Exit(MsgFmt(SF_DESIGNER_OCUPA_HEREDADO_FMT, [H.Substring(H.IndexOf('=') + 1)]));
end;

// el nombre que pone el IDE: la clase sin su T y el primer numero libre
function NombreLibre(ADoc: TStyleDoc; AClase: TTipoPas; const AClaseComp: string;
  const AHeredados: TArray<string>): string;
var
  Base: string;
  N: Integer;
begin
  Base := AClaseComp;
  if (Length(Base) > 1) and CharInSet(Base[1], ['T', 't']) then
    Base := Copy(Base, 2, MaxInt);
  N := 1;
  repeat
    Result := Base + IntToStr(N);
    Inc(N);
  until NombreOcupado(ADoc, AClase, Result, nil, AHeredados) = '';
end;

{ Si el form y su unidad pueden llevar el nombre de componente ANombre sin
  cambiar su codificacion (DSGN-111, NombreQueElFicheroNoLee), con la unidad
  en la codificacion en que la ESCRIBIRA su escritor (EncAlEscribir), no en
  la que se leyo: una unidad solo ASCII no tiene ninguna y el nombre la elige
  -CP1252 o UTF-8 con BOM, las dos las lee dcc-; se negaba por la preferencia
  del IDE. La preguntan el nombre que se pide (NombreQueNoVale) y el que pone
  el IDE (un insert sin nombre: una clase con una letra no ASCII da un nombre
  con ella, y no pasaba por aqui). Revisor propio de la 4.1, 9-oct-2026. }
function NombreQueLaCodificacionNoLleva(const F: TFormEnEdicion; const ANombre: string): string;
var
  PasEnc: string;
begin
  // el nombre basta como texto: en una unidad ASCII lo demas cabe en
  // cualquiera, y una con codificacion la conserva sea cual sea
  PasEnc := F.PasEnc;
  if F.HayPas then
    PasEnc := EncName(EncAlEscribir(F.Pas, EncKindOf(F.PasEnc), TFile.ReadAllBytes(F.Pas),
      True, ANombre));
  Result := NombreQueElFicheroNoLee(ANombre, F.Dfm, F.Doc.Encoding, F.Pas, PasEnc);
end;

{ Si un componente puede llamarse ANombre en este form: un identificador,
  no una palabra reservada, y libre (NombreOcupado). Lo preguntan el
  renombrado y el insert con nombre. ALimpio: el nombre sin espacios ni
  comillas (Name = 'BtnOk' es como lo diria un Caption). Y que el form y su
  unidad lo puedan llevar sin cambiar su codificacion (NombreQueElFicheroNoLee:
  un nombre con acento en un .dfm sin BOM lo rompia diciendo OK, segunda
  revision de la 1.17.0). }
function NombreQueNoVale(const F: TFormEnEdicion; AClase: TTipoPas; const ANombre: string;
  AYo: TStyleObj; out ALimpio: string): string;
var
  Motivo: string;
begin
  ALimpio := NombreDeValor(ANombre); // 'Bot'#243'n' es Boton con su acento
  if not EsIdentificador(ALimpio, False) or EsPalabraReservada(ALimpio) then
    Exit(MsgFmt(SR_DESIGNER_NOMBRE_INVALIDO_FMT, [ANombre.Trim]));
  Motivo := NombreOcupado(F.Doc, AClase, ALimpio, AYo, NombresHeredados(F, AClase));
  if Motivo <> '' then
    Exit(MsgFmt(SR_DESIGNER_NOMBRE_OCUPADO_FMT, [ALimpio, Motivo]));
  Result := NombreQueLaCodificacionNoLleva(F, ALimpio);
end;


function Publica(M: TMetaTable; const AClsId, AProp: string): Boolean;
begin
  Result := M.Props.ContainsKey(ClaveProp(AClsId, AProp));
end;

{ EL juez de donde va el texto que sigue al nombre: insert lo escribe con el
  nombre y el renombrado lo cambia si era el nombre. Su clase lo hace si su
  SetName lo hace (TextoSigueAlNombre) y lo publica: en VCL Caption o Text,
  en FMX Text. Sin la clase en la tabla (AClsId ''), como el TControl del
  IDE: cualquiera de las dos. Estaba decidido en dos sitios (revision de la
  1.17.0). }
function PropiedadesDeTexto(M: TMetaTable; AEsFmx: Boolean; const AClsId: string): TArray<string>;
begin
  Result := [];
  if (M = nil) or (AClsId = '') then
  begin
    Result := ['Caption', 'Text'];
    Exit;
  end;
  if not M.TextoSigueAlNombre(AClsId) then
    Exit;
  if not AEsFmx and Publica(M, AClsId, 'Caption') then
    Result := ['Caption']
  else if Publica(M, AClsId, 'Text') then
    Result := ['Text'];
end;

// el TabOrder que lleva AObj en ADoc; -1 si no lleva (o no es un numero)
function TabOrderDe(ADoc: TStyleDoc; AObj: TStyleObj): Integer;
var
  Ini, Fin: Integer;
  P, V: string;
begin
  if not (ADoc.PropLines(AObj, 'TabOrder', Ini, Fin) and LineaDePropiedad(ADoc.Lines[Ini], P, V) and
     TryStrToInt(V, Result)) then
    Result := -1;
end;

// el TabOrder que sigue entre los hijos de APadre QUE ESTAN EN EL TEXTO: el
// de cuando el juez no contesta (los de un ancestro no estan aqui: en un panel
// heredado salia 0; el juez, DondeLoDejaElIde, si los cuenta - punto 7)
function SiguienteTabOrder(ADoc: TStyleDoc; APadre: TStyleObj): Integer;
begin
  Result := 0;
  for var K in APadre.Children do
    Result := Max(Result, TabOrderDe(ADoc, K) + 1);
end;

{ ATexto sin la linea TabOrder PROPIA de ANombre (las de sus hijos se quedan):
  lo que se le pregunta al juez para que el IDE le de la suya - la ultima del
  tabulador de su padre, como al soltarlo en el disenador. Un valor nuestro
  "al final" (32767) lo colocaba la VCL la ultima, pero FMX lo guarda tal
  cual (su TabList rellena hasta ese indice): 32767 escrito y 32768 el
  siguiente, fuera de TTabOrder (D1 del revisor de cierre de la 1.18.2,
  medido con el escritor de los dos marcos). }
function SinSuTabOrder(const ATexto, ANombre: string): string;
var
  Doc: TStyleDoc;
  Ini, Fin: Integer;
begin
  Result := ATexto;
  Doc := TStyleDoc.DeTexto(ATexto);
  try
    var O := ObjetoPorNombre(Doc, ANombre);
    if (O = nil) or not Doc.PropLines(O, 'TabOrder', Ini, Fin) then
      Exit;
    var L := Copy(Doc.Lines);
    Delete(L, Ini, Fin - Ini + 1);
    Result := Doc.TextoDe(L);
  finally
    Doc.Free;
  end;
end;

// ALineas con el TabOrder propio de ANombre a AValor: su linea ya esta (la
// cuenta propia que lleva el bloque) y pasa a lo que dijo el juez
procedure PonSuTabOrder(const F: TFormEnEdicion; var ALineas: TArray<string>; const ANombre: string;
  AValor: Integer);
var
  Doc: TStyleDoc;
  Ini, Fin: Integer;
begin
  Doc := TStyleDoc.DeTexto(F.Doc.TextoDe(ALineas));
  try
    var O := ObjetoPorNombre(Doc, ANombre);
    if (O <> nil) and Doc.PropLines(O, 'TabOrder', Ini, Fin) and (Ini = Fin) then
      ALineas[Ini] := LineasDePropiedad(LeadingWhite(ALineas[Ini]), 'TabOrder', [IntToStr(AValor)])[0];
  finally
    Doc.Free;
  end;
end;

{ Donde va el campo de un componente nuevo: detras del ultimo campo de la
  seccion por defecto (la published de un form, donde los escribe el IDE),
  o detras de la cabecera de la clase si no hay ninguno - siempre delante de
  sus metodos (un campo detras de un metodo no compila, E2169). }
procedure SitioDelCampo(AClase: TTipoPas; const ALineas: TArray<string>;
  out ADetras: Integer; out ASangria: string);
begin
  ADetras := AClase.Linea;
  ASangria := LeadingWhite(ALineas[AClase.Linea]) + '  ';
  var Ultimo := -1;
  for var C in AClase.Campos do
    if (C.Visibilidad = vpDefecto) and not C.DeClase and (C.LineaFin > Ultimo) then
    begin
      Ultimo := C.LineaFin;
      ADetras := C.LineaFin;
      ASangria := LeadingWhite(ALineas[C.LineaIni]);
    end;
end;

// AUnidad ya esta en esa lista del uses: igual, o sin su ambito ('StdCtrls'
// de un proyecto con los nombres de ambito del IDE)
function UnidadEnUses(const AUses: TArray<string>; const AUnidad: string): Boolean;
begin
  for var E in AUses do
    if MismoIdentificador(E, AUnidad) or
       ((Pos('.', E) = 0) and MismoIdentificador(E, UltimoTrozo(AUnidad))) then
      Exit(True);
  Result := False;
end;

function BloqueNumerado(const ALineas: TArray<string>; AIni, AFin: Integer): TArray<string>;
begin
  Result := [];
  for var I := AIni to AFin do
    Result := Result + [CitaDeLinea(I + 1, ALineas[I])];
end;

procedure PonLista(AObj: TJSONObject; const AClave: string; const AValores: TArray<string>);
var
  A: TJSONArray;
begin
  if Length(AValores) = 0 then
    Exit;
  A := TJSONArray.Create;
  for var V in AValores do
    A.Add(V);
  AObj.AddPair(AClave, A);
end;

// lo que el lint y el binding dicen del form YA escrito: los avisos que da
// delphi_edit tras escribir un designer
function AvisosDespues(const F: TFormEnEdicion; const ATexto: string): TArray<string>;
begin
  // EL lint de un form (Lsp.Patch.LintDeForm), sin esperar a una tabla; el
  // parser del IDE lo primero, con o sin tabla (8.10 de la 1.18.0)
  var L := LintDeForm(F.Dfm, ATexto, F.Doc.Encoding, True, 0);
  Result := L.Propiedades + L.Enlace;
  if L.Parser <> '' then
    Result := [L.Parser] + Result;
  if L.Falta.Razon <> '' then
    Result := Result + [MsgFmt(SN_DESIGNER_LINT_SIN_TABLA_FMT, [L.Falta.Razon])];
end;

// el form y su unidad, todo o nada
function EscribeFormYUnidad(const F: TFormEnEdicion; const ADfm, APas: string;
  AConPas: Boolean): string;
var
  Dfm, DfmEnc, Pas, PasEnc, TxtDfm, TxtPas: string;
  ConPas: Boolean;
  Rutas: TArray<string>;
begin
  Dfm := F.Dfm;
  DfmEnc := F.Doc.Encoding;
  Pas := F.Pas;
  PasEnc := F.PasEnc;
  TxtDfm := ADfm;
  TxtPas := APas;
  ConPas := AConPas;
  // el form, solo si el parser del IDE lo lee: la pregunta de Guarda (9.B)
  Result := F.Doc.JuicioDelParser(ADfm);
  if Result <> '' then
    Exit;
  Rutas := [Dfm];
  if ConPas then
    Rutas := Rutas + [Pas];
  Result := FicherosTodoONada(Rutas,
    function: string
    begin
      PatchSaveText(Dfm, TxtDfm, DfmEnc);
      if ConPas then
        PatchSaveText(Pas, TxtPas, PasEnc);
      Result := '';
    end);
end;

{ ALineas -un form con el bloque de ANomObj ya compuesto- con las propiedades
  de ANomObj como las guarda el escritor del IDE (1.22.1, David: "el juez da
  tambien el orden"). Se le pregunta a el (PropiedadesComoLasEscribeElIde: lo
  que escribe TWriter y, de ANomObj, el orden de sus propiedades) y sus lineas
  sustituyen a las nuestras: el tamano que da el constructor, Size.Height y
  Size.PlatformDefault junto a un Size.Width, las Font.* y ParentFont junto a
  un Font.Style, cada una en su sitio (medido con el renderizador en
  --writeback). Lo nuestro que el no puede dar se queda, en su sitio de ese
  orden, y lo dice SU cargador: lo que leyo y no pudo aplicar (UNAPPLIED=: el
  metodo de un evento, que alli no hay codigo; una referencia que no resolvio,
  la de otro modulo) y lo que su lector se salto (IGNORED=). Ninguna regla
  propia de que es un evento o una referencia (David, 22-oct-2026: "hay que
  buscar al juez"). Lo demas nuestro que no escribe es el valor
  que ya da la clase: va en ANoGuarda (DSGN-165) y no se escribe, como no lo
  guardaria el IDE; y la que el escribe con OTRO valor (un Align que la
  coloca, un Date sin la hora, el nombre de un color), en AOtras con el suyo
  (DSGN-166). Sin juez -lo heredado o de un frame en linea (el IDE
  guarda la diferencia con su ancestro), sin respuesta, leido sin un
  ancestro, con su clase sustituida, sin el orden-, ALineas tal cual y ANota
  (DSGN-164) dice por que; la raiz, tal cual y sin nota, como antes. Lo que
  puso el agente (APuestas) es lo ULTIMO que lee el cargador, como el IDE, que
  pone el valor en el componente ya cargado; y una propiedad que su clase
  declara stored False (UNSTORED=: en FMX, Width y Height van en Size) va en
  AOtras con EnOtras y lo que el escritor escribe por ella (DSGN-167), no en
  ANoGuarda (completo de Opus de la 1.22.1). }
function ConLasPropiedadesDelIde(var F: TFormEnEdicion; const ALineas: TArray<string>;
  const ANomObj: string; const APuestas: TArray<string>; out ANota: string;
  out ANoGuarda: TArray<string>; out AOtras: TArray<TGuardadaComo>): TArray<string>;

  // el valor de AProp en el nivel propio de AObj, por EL lector de ADoc: de
  // un literal, su texto (cada escritor parte una cadena larga por su sitio)
  function ValorComparable(ADoc: TStyleDoc; AObj: TStyleObj; const AProp: string): string;
  var
    Hay: Boolean;
  begin
    Result := ADoc.LiteralDe(AObj, AProp);
    if Result = '' then
      Result := ADoc.ValorDe(AObj, AProp, Hay);
  end;

  // la propiedad de arriba de AProp (Size de Size.Width): la que esta en el orden
  function ArribaDe(const AProp: string): string;
  begin
    Result := AProp;
    if Pos('.', Result) > 0 then
      Result := Copy(Result, 1, Pos('.', Result) - 1);
  end;

  // su sitio en el orden del escritor; MaxInt si no esta (la escribe
  // DefineProperties, detras de las publicadas)
  function EnElOrden(const AOrden: TArray<string>; const AProp: string): Integer;
  begin
    for var I := 0 to High(AOrden) do
      if SameText(AOrden[I], ArribaDe(AProp)) then
        Exit(I);
    Result := MaxInt;
  end;

  // las lineas ADesde..AHasta de ADoc son las de ARangos, o en blanco (esas
  // las quita el IDE al guardar)
  function SoloPropiedades(ADoc: TStyleDoc; const ARangos: TArray<TRangoDeLineas>;
    ADesde, AHasta: Integer): Boolean;
  begin
    for var I := ADesde to AHasta do
    begin
      var Dentro := False;
      for var Rg in ARangos do
        if (I >= Rg.Ini) and (I <= Rg.Fin) then
          Dentro := True;
      if not Dentro and (ADoc.Lines[I].Trim <> '') then
        Exit(False);
    end;
    Result := True;
  end;

  // ALineas con las propiedades de APuestas al final del bloque de AObj, en su
  // orden; nil si no hay que mover nada o el bloque no es solo propiedades
  function LoPuestoAlFinal(ADoc: TStyleDoc; AObj: TStyleObj): TArray<string>;
  var
    De, A: Integer;
    Antes, Puestas: TArray<string>;
  begin
    Result := nil;
    if Length(APuestas) = 0 then
      Exit;
    var Rangos := ADoc.Propiedades(AObj, De, A);
    if not SoloPropiedades(ADoc, Rangos, De, A) then
      Exit;
    Antes := [];
    Puestas := [];
    for var Rg in Rangos do
      if MatchText(Rg.Prop, APuestas) then
        Puestas := Puestas + Copy(ALineas, Rg.Ini, Rg.Fin - Rg.Ini + 1)
      else
        Antes := Antes + Copy(ALineas, Rg.Ini, Rg.Fin - Rg.Ini + 1);
    if Length(Puestas) = 0 then
      Exit;
    Result := Copy(ALineas, 0, De) + Antes + Puestas + Copy(ALineas, A + 1, MaxInt);
  end;

var
  Doc, DocE: TStyleDoc;
  O, OE: TStyleObj;
  R: TRespuestaRender;
  Nuestras, Suyas: TArray<TRangoDeLineas>;
  Desde, Hasta, DesdeE, HastaE: Integer;
  Bloques: TList<TArray<string>>;
  Puestos: TList<Integer>;
  Motivo: string;
begin
  Result := ALineas;
  ANota := '';
  ANoGuarda := [];
  AOtras := [];
  Motivo := '';
  var Texto := F.Doc.TextoDe(ALineas);
  Doc := TStyleDoc.DeTexto(Texto);
  try
    O := ObjetoPorNombre(Doc, ANomObj);
    if (O = nil) or (O.Parent = nil) then
      Exit;
    // lo que puso el agente, lo ULTIMO que lee su cargador: el IDE pone el valor
    // en el componente ya cargado y gana a lo que el fichero decia. Leido
    // arriba, lo de detras lo pisaba: un Width en FMX (stored False, va en Size)
    // con un Size.Width ya escrito se perdia en silencio (completo de Opus de la
    // 1.22.1)
    var Lineas := LoPuestoAlFinal(Doc, O);
    if Lineas <> nil then
    begin
      Doc.Free;
      Doc := nil;
      Texto := F.Doc.TextoDe(Lineas);
      Doc := TStyleDoc.DeTexto(Texto);
      O := ObjetoPorNombre(Doc, ANomObj);
      if O = nil then
        Exit;
    end
    else
      Lineas := ALineas;
    if not SameText(O.Clave, 'object') or (InlineQueLoContiene(O) <> nil) then
      Motivo := MsgFmt(SF_DESIGNER_IDE_HEREDADO_FMT, [ANomObj])
    else
    begin
      R := PropiedadesComoLasEscribeElIde(F.Dfm, Texto, F.Doc.Encoding, ANomObj);
      // lo que leyo, para mirarlo otra vez antes de escribir (B5 rev6)
      F.LeidoPorElJuez := F.LeidoPorElJuez + R.Leidos;
      if R.Fallo <> '' then
        Motivo := MsgFmt(SF_DESIGNER_IDE_SIN_RESPUESTA_FMT, [MsgCuerpo(R.Fallo)])
      else if Length(R.SinLeer) > 0 then
        Motivo := MsgFmt(SF_DESIGNER_IDE_SIN_ANCESTRO_FMT, [string.Join(', ', R.SinLeer)])
      else if Length(R.Orden) = 0 then
        Motivo := MsgText(SF_DESIGNER_IDE_SIN_ORDEN);
      for var S in R.Sustituidas do
        if (Motivo = '') and SameText(S, O.ClassName_) then
          Motivo := MsgFmt(SF_DESIGNER_IDE_SUSTITUIDA_FMT, [O.ClassName_]);
      // un salto de su lector sin dueno (el error del codigo de un componente)
      // podria ser de ANomObj: su linea se daria por no guardada y se perderia
      for var Ig in R.Ignoradas do
        if (Motivo = '') and (Ig.Componente = '') then
          Motivo := MsgFmt(SF_DESIGNER_IDE_SALTO_SIN_DUENO_FMT, [Ig.Texto]);
    end;
    if Motivo = '' then
    begin
      DocE := TStyleDoc.DeTexto(string.Join(#13#10, R.Escrito));
      Bloques := TList<TArray<string>>.Create;
      Puestos := TList<Integer>.Create;
      try
        OE := ObjetoPorNombre(DocE, ANomObj);
        if OE = nil then
          Motivo := MsgText(SF_DESIGNER_IDE_NO_LO_ESCRIBE)
        else
        begin
          Nuestras := Doc.Propiedades(O, Desde, Hasta);
          Suyas := DocE.Propiedades(OE, DesdeE, HastaE);
          if not SoloPropiedades(Doc, Nuestras, Desde, Hasta) or
             not SoloPropiedades(DocE, Suyas, DesdeE, HastaE) then
            Motivo := MsgText(SF_DESIGNER_IDE_BLOQUE_ILEGIBLE);
        end;
        if Motivo = '' then
        begin
          // las suyas, con la sangria del fichero
          var Delta := Length(LeadingWhite(Doc.Lines[O.StartLine - 1])) -
            Length(LeadingWhite(DocE.Lines[OE.StartLine - 1]));
          // lo que el escritor guarda y no estaba tal cual en lo compuesto: lo que
          // escribe por una stored False (el Size.Width de un Width en FMX)
          var Cambiadas: TArray<string> := [];
          var PrimeraCambiada := '';
          for var S in Suyas do
            for var K := S.Ini to S.Fin do
            begin
              var Estaba := False;
              for var J := Desde to Hasta do
                if Doc.Lines[J].Trim = DocE.Lines[K].Trim then
                  Estaba := True;
              if not Estaba then
              begin
                Cambiadas := Cambiadas + [DocE.Lines[K].Trim];
                if PrimeraCambiada = '' then
                  PrimeraCambiada := S.Prop;
              end;
            end;
          for var S in Suyas do
          begin
            var B: TArray<string> := [];
            for var K := S.Ini to S.Fin do
              B := B + [Resangra(DocE.Lines[K], Delta)];
            Bloques.Add(B);
            Puestos.Add(EnElOrden(R.Orden, S.Prop));
          end;
          // ...y las nuestras que el no da, cada una en su sitio de su orden
          for var N in Nuestras do
          begin
            var Suya := False;
            for var S in Suyas do
              if SameText(S.Prop, N.Prop) then
                Suya := True;
            if Suya then
            begin
              var Suyo := ValorComparable(DocE, OE, N.Prop);
              if Suyo <> ValorComparable(Doc, O, N.Prop) then
              begin
                var Otra := Default(TGuardadaComo);
                Otra.Prop := N.Prop;
                Otra.Valor := Suyo;
                AOtras := AOtras + [Otra];
              end;
              Continue;
            end;
            var Puesto := EnElOrden(R.Orden, N.Prop);
            // lo que su cargador no pudo aplicar, por su valor (el metodo, la
            // referencia), o lo que su lector se salto de este componente
            var Hay: Boolean;
            var Valor := Doc.ValorDe(O, N.Prop, Hay);
            var Queda := False;
            for var V in R.NoAplicados do
              if SameText(V, Valor) then
                Queda := True;
            for var Ig in R.Ignoradas do
              if SameText(Ig.Componente, ANomObj) and
                 (SameText(Ig.Propiedad, N.Prop) or SameText(Ig.Propiedad, ArribaDe(N.Prop))) then
                Queda := True;
            if not Queda then
            begin
              // una que su clase no guarda nunca por su nombre (stored False: en
              // FMX, Width y Height van en Size) no es "el valor que ya da la
              // clase": lo que el form guarda de ella es lo que el escritor
              // escribe por ella (completo de Opus de la 1.22.1: DSGN-165 con el
              // Size.Width escrito)
              if MatchText(ArribaDe(N.Prop), R.NuncaGuardadas) then
              begin
                var EnOtras := Default(TGuardadaComo);
                EnOtras.Prop := N.Prop;
                EnOtras.Valor := string.Join('; ', Cambiadas);
                EnOtras.EnOtras := True;
                EnOtras.Donde := PrimeraCambiada;
                AOtras := AOtras + [EnOtras];
              end
              else
                ANoGuarda := ANoGuarda + [N.Prop];
              Continue;
            end;
            // detras de las que van antes en el orden, o a la par
            var K := 0;
            while (K < Puestos.Count) and (Puestos[K] <= Puesto) do
              Inc(K);
            Bloques.Insert(K, Copy(Doc.Lines, N.Ini, N.Fin - N.Ini + 1));
            Puestos.Insert(K, Puesto);
          end;
          var Nuevas: TArray<string> := [];
          for var B in Bloques do
            Nuevas := Nuevas + B;
          Result := Copy(Lineas, 0, Desde) + Nuevas + Copy(Lineas, Hasta + 1, MaxInt);
        end;
      finally
        Puestos.Free;
        Bloques.Free;
        DocE.Free;
      end;
    end;
    if Motivo <> '' then
      ANota := MsgFmt(SN_DESIGNER_PROPIEDADES_SIN_JUEZ_FMT, [ANomObj, Motivo]);
  finally
    Doc.Free;
  end;
end;

// lo que guarda el IDE de una propiedad que puso el agente (ANoGuarda y
// AOtras de ConLasPropiedadesDelIde): la respuesta lo dice (PonValorPuesto)
procedure MarcaLoQueGuarda(var AInfo: TValorPuesto; const ANoGuarda: TArray<string>;
  const AOtras: TArray<TGuardadaComo>);
begin
  if AInfo.Quitada or AInfo.NadaQueQuitar then
    Exit;
  for var P in ANoGuarda do
    if SameText(P, AInfo.Prop) then
      AInfo.NoGuardada := True;
  for var O in AOtras do
    if SameText(O.Prop, AInfo.Prop) then
      if O.EnOtras then
      begin
        AInfo.GuardadaEnOtras := True;
        AInfo.GuardadaEn := O.Valor;
        AInfo.GuardadaEnProp := O.Donde;
      end
      else
        AInfo.GuardadaComo := O.Valor;
end;

// las propiedades que puso el agente (las APuestas de ConLasPropiedadesDelIde)
function PropsDe(const AInfos: TArray<TValorPuesto>): TArray<string>;
begin
  Result := [];
  for var I in AInfos do
    Result := Result + [I.Prop];
end;

{ ---- insert ---- }

function InsertaComponente(const APath, AClase, AComponente, AParent: string;
  const AProps: string): string;
var
  F: TFormEnEdicion;
  Padre: TStyleObj;
  ClsId, Clase, Unidad, Nombre, Ind, Texto, PasNuevo, Sangria, UsesAnadida, UsesNota: string;
  Bloque, DfmLineas, PasLineas, Faltan, YaEstan, EnOtra: TArray<string>;
  UPas: TUnidadPas;
  Cls: TTipoPas;
  Detras, Ini, LineaCampo, FinBloque: Integer;
  Creada: Boolean;
  Ret: TJSONObject;
  Props, Valores: TArray<string>;
  Infos: TArray<TValorPuesto>;
  Antes, AntesPas: TArray<Byte>;
  NotaOrden, NotaLector: string;
begin
  if AClase.Trim = '' then
    Exit(MsgText(SR_DESIGNER_NEED_CLASS));
  // las propiedades iniciales, lo que se mira sin abrir nada (3.10)
  if AProps.Trim <> '' then
  begin
    Result := ParesDeProps(AProps, Props, Valores);
    if Result <> '' then
      Exit;
  end;
  // los bytes que se juzgan (el juez del orden, abajo), leidos con el cerrojo
  Result := AbreFormParaJuzgar(APath, True, True, F, Antes, AntesPas);
  if Result <> '' then
    Exit;
  try
    // la clase: de la tabla del Delphi activo, y un control
    if not F.Tabla.ClaseDeNombre(AClase.Trim, ClsId) then
      Exit(ClaseQueNoEsta(F.Tabla, AClase.Trim, F.Marco) +
        MsgFmt(SF_DESIGNER_INSERT_SIN_TABLA_FMT, [MsgText(SF_DESIGNER_A_MANO)]));
    Clase := F.Tabla.Classes[ClsId];
    if not F.Tabla.Desciende(ClsId, IfThen(F.EsFmx, ID_FMX_CONTROL, ID_VCL_CONTROL)) then
      Exit(MsgFmt(SR_DESIGNER_INSERT_NO_VISUAL_FMT, [Clase, IfThen(F.EsFmx, ID_FMX_CONTROL, ID_VCL_CONTROL),
        MsgText(SF_DESIGNER_A_MANO)]));
    if AParent.Trim = '' then
      Padre := F.Doc.Root
    else
    begin
      Result := BuscaComponente(F, AParent, Padre);
      if Result <> '' then
        Exit;
    end;
    Result := PadreQueNoVale(F, Padre, False);
    if Result <> '' then
      Exit;
    // la unidad: el nombre libre, el campo y el uses
    UsesAnadida := '';
    UsesNota := '';
    UPas := LeeFuentePascal(F.PasTexto);
    try
      Cls := UPas.Clase(F.Doc.Root.ClassName_);
      // el nombre que se pide, con las reglas del renombrado; si no, el del IDE
      if AComponente.Trim <> '' then
      begin
        Result := NombreQueNoVale(F, Cls, AComponente, nil, Nombre);
        if Result <> '' then
          Exit;
      end
      else
      begin
        Nombre := NombreLibre(F.Doc, Cls, Clase, NombresHeredados(F, Cls));
        Result := NombreQueLaCodificacionNoLleva(F, Nombre);
        if Result <> '' then
          Exit;
      end;
      PasLineas := SplitToLines(F.PasTexto);
      SitioDelCampo(Cls, PasLineas, Detras, Sangria);
      // la linea del campo, por el compositor de todos (era su gemelo a mano):
      // las demas con su salto, la nueva con el dominante
      PasNuevo := CambiaLineasEnSuTexto(F.PasTexto, Detras + 1, 0,
        [Sangria + Nombre + ': ' + Clase + ';'], SaltoDominante(F.PasTexto));
      Unidad := '';
      if EsIdDeTipo(ClsId) then
        Unidad := UnidadDeIdDeTipo(F.Tabla.IdEscrito[ClsId]);
      if (Unidad <> '') and not UnidadEnUses(UPas.UsesInterface, Unidad) then
      begin
        if UnidadEnUses(UPas.UsesImplementation, Unidad) then
          UsesNota := MsgFmt(SF_DESIGNER_USES_EN_IMPL_FMT, [Unidad, F.PasNombre])
        else
        begin
          Result := UsesConUnidades(PasNuevo, [Unidad], 'interface', F.PasNombre,
            Faltan, YaEstan, EnOtra, Creada);
          if Result <> '' then
            Exit(Result + MsgFmt(SF_DESIGNER_INSERT_TRAS_USES_FMT, [Unidad]));
          UsesAnadida := Unidad;
        end;
      end;
    finally
      UPas.Free;
    end;
    // el bloque, con lo minimo que escribe el IDE, ultimo hijo de su padre (su
    // sitio entre los hermanos lo dice el juez del orden, abajo)
    Ind := SangriaDeNivel(Padre.Depth + 1);
    // cada linea por sus compositores (Lsp.DesignerBin): la de objeto, la de
    // una propiedad, el literal, el flotante
    Bloque := [Ind + ComponeLineaDeObjeto('object', Nombre, Clase)];
    if F.EsFmx then
      Bloque := Bloque + LineasDePropiedad(Ind + '  ', 'Position.X', [FlotanteFmx(INSERT_X)]) +
        LineasDePropiedad(Ind + '  ', 'Position.Y', [FlotanteFmx(INSERT_Y)])
    else
      Bloque := Bloque + LineasDePropiedad(Ind + '  ', 'Left', [IntToStr(INSERT_X)]) +
        LineasDePropiedad(Ind + '  ', 'Top', [IntToStr(INSERT_Y)]);
    // su texto, con su nombre, si su SetName lo hace: EL juez
    // (PropiedadesDeTexto, el mismo del renombrado)
    Texto := '';
    var Textos := PropiedadesDeTexto(F.Tabla, F.EsFmx, ClsId);
    if Length(Textos) = 1 then
      Texto := Textos[0];
    if not F.EsFmx and (Texto <> '') then
      Bloque := Bloque + LineasDePropiedad(Ind + '  ', Texto, TrozosDeLiteral(Nombre));
    // el TabOrder: el ultimo del tabulador de su padre, el que diga el juez
    // (abajo, DondeLoDejaElIde, que le pregunta SIN esta linea); el propio,
    // el que lleva el bloque, si no contesta o si su escritor no lo escribe
    var ConTab := Publica(F.Tabla, ClsId, 'TabOrder');
    if ConTab then
      Bloque := Bloque + LineasDePropiedad(Ind + '  ', 'TabOrder', [IntToStr(SiguienteTabOrder(F.Doc, Padre))]);
    if F.EsFmx and (Texto <> '') then
      Bloque := Bloque + LineasDePropiedad(Ind + '  ', Texto, TrozosDeLiteral(Nombre));
    Bloque := Bloque + [Ind + 'end'];
    DfmLineas := Copy(F.Doc.Lines);
    Ini := Padre.EndLine - 1;
    Insert(Bloque, DfmLineas, Ini);
    FinBloque := Ini + High(Bloque);
    // el nombre del padre AHORA: Reparsea (abajo) libera los objetos leidos
    var NombrePadre := NombreDe(Padre);
    // las propiedades iniciales sobre el bloque nuevo, EN MEMORIA, cada una
    // juzgada como la juzga set (PonEnMemoria) y todo o nada con el resto
    // (3.10 de la 1.18.0: Hermes replicaba un form a golpe de insert + set)
    if Length(Props) > 0 then
    begin
      F.Doc.SetLines(DfmLineas);
      F.Doc.Reparsea;
      SetLength(Infos, Length(Props));
      for var I := 0 to High(Props) do
      begin
        Result := PonEnMemoria(F, Nombre, Props[I], Valores[I], Infos[I]);
        if Result <> '' then
          Exit(MsgFmt(SR_DESIGNER_PROPS_ENTRADA_FMT, [I + 1, Props[I], Result]));
      end;
      DfmLineas := Copy(F.Doc.Lines);
      Result := CargaLoPuesto(F, Nombre, Infos, NotaLector);
      if Result <> '' then
        Exit;
      var Nuevo := ObjetoPorNombre(F.Doc, Nombre);
      if Nuevo <> nil then
        FinBloque := Nuevo.EndLine - 1;
    end;
    // donde lo deja el IDE entre sus hermanos, no siempre el ultimo (3.11: el
    // juez del orden; la VCL escribe un TLabel delante de los TButton)
    var Largo := FinBloque - Ini + 1;
    var TabDelIde: Integer;
    // un TabOrder que puso el agente (props) es suyo: el juez lo ve y se queda
    var TabDelAgente := False;
    for var P in Props do
      if SameText(P.Trim, 'TabOrder') then
        TabDelAgente := True;
    DfmLineas := DondeLoDejaElIde(F, DfmLineas, Nombre, NombrePadre, Ini, Largo, ConTab and not TabDelAgente,
      NotaOrden, TabDelIde);
    FinBloque := Ini + Largo - 1;
    if ConTab and not TabDelAgente and (TabDelIde >= 0) then
      PonSuTabOrder(F, DfmLineas, Nombre, TabDelIde);
    // sus propiedades como las guarda el escritor del IDE (1.22.1: el tamano
    // del constructor, su orden); el bloque cambia de largo y se vuelve a medir
    var NotaIde: string;
    var NoGuarda: TArray<string>;
    var Otras: TArray<TGuardadaComo>;
    DfmLineas := ConLasPropiedadesDelIde(F, DfmLineas, Nombre, PropsDe(Infos), NotaIde, NoGuarda, Otras);
    for var I := 0 to High(Infos) do
      MarcaLoQueGuarda(Infos[I], NoGuarda, Otras);
    var DocI := TStyleDoc.DeTexto(F.Doc.TextoDe(DfmLineas));
    try
      var Puesto := ObjetoPorNombre(DocI, Nombre);
      if Puesto <> nil then
      begin
        Ini := Puesto.StartLine - 1;
        FinBloque := Puesto.EndLine - 1;
      end;
    finally
      DocI.Free;
    end;
    // con el cerrojo: el form y la unidad son los que se juzgaron
    EnterFileEdit;
    try
      Result := CambioDesdeQueSeJuzgo(F, Antes, AntesPas);
      if Result = '' then
        Result := EscribeFormYUnidad(F, F.Doc.TextoDe(DfmLineas), PasNuevo, True);
    finally
      LeaveFileEdit;
    end;
    if Result <> '' then
      Exit;
    // la linea del campo, en la unidad como ha quedado
    LineaCampo := 0;
    UPas := LeeFuentePascal(PasNuevo);
    try
      Cls := UPas.Clase(F.Doc.Root.ClassName_);
      if Cls <> nil then
        for var C in Cls.Campos do
          if MismoIdentificador(C.Nombre, Nombre) then
            LineaCampo := C.Linea + 1;
    finally
      UPas.Free;
    end;
    Ret := TJSONObject.Create;
    try
      Ret.AddPair('inserted', Nombre);
      Ret.AddPair('class', Clase);
      Ret.AddPair('parent', NombrePadre);
      Ret.AddPair('file', F.DfmNombre);
      Ret.AddPair('line', TJSONNumber.Create(Ini + 1));
      Ret.AddPair('endLine', TJSONNumber.Create(FinBloque + 1));
      PonLista(Ret, 'block', BloqueNumerado(DfmLineas, Ini, FinBloque));
      if Length(Infos) > 0 then
      begin
        var Lista := TJSONArray.Create;
        Ret.AddPair('props', Lista);
        for var I := 0 to High(Infos) do
        begin
          var Una := TJSONObject.Create;
          Lista.AddElement(Una);
          Una.AddPair('prop', Infos[I].Prop);
          PonValorPuesto(Una, Nombre, Infos[I]);
        end;
      end;
      Ret.AddPair('field', Nombre + ': ' + Clase);
      Ret.AddPair('fieldAt', Donde(F.PasNombre, LineaCampo));
      if UsesAnadida <> '' then
        Ret.AddPair('usesAdded', UsesAnadida);
      if UsesNota <> '' then
        Ret.AddPair('usesNote', UsesNota);
      PonLista(Ret, 'lint', AvisosDespues(F, F.Doc.TextoDe(DfmLineas)));
      Ret.AddPair('note', MsgText(SN_DESIGNER_INSERT_NOTE));
      if NotaOrden <> '' then
        Ret.AddPair('orderNote', NotaOrden);
      if NotaLector <> '' then
        Ret.AddPair('readerNote', NotaLector);
      if NotaIde <> '' then
        Ret.AddPair('ideNote', NotaIde);
      Result := Ret.ToJSON;
    finally
      Ret.Free;
    end;
  finally
    F.Doc.Free;
  end;
end;

{ ---- set ---- }

function NombresHeredados(const F: TFormEnEdicion; AClase: TTipoPas): TArray<string>;
var
  Cadena: TCadenaPorElMotor;
  Fichero, Id: string;
  Linea, Salto: Integer;
  T: TTipoPas;
begin
  Result := [];
  if (AClase = nil) or not F.HayPas then
    Exit;
  Cadena := nil;
  try
    T := AClase;
    Fichero := F.Pas;
    Salto := 0;
    while True do
    begin
      // una clase de la tabla (TForm, un componente instalado) acaba la
      // cadena: sus campos no son componentes del form
      if (UltimoTrozo(T.Ancestro) = '') or F.Tabla.ClaseDeNombre(UltimoTrozo(T.Ancestro), Id) then
        Break;
      // una base del USUARIO: donde esta la dice el MOTOR, no la carpeta del
      // form (dos TBaseForm en la carpeta: elegia el orden de ficheros, y
      // insert daba el Button1 de la base real a un boton nuevo; 15-oct-2026)
      if Cadena = nil then
      begin
        Cadena := CadenaPara(F.Pas);
        if Cadena = nil then
          Break; // sin ajustes de proyecto no hay motor
      end;
      // por EL recorredor (Lsp.Herencia.Siguiente): el tope de saltos es suyo
      Linea := T.Linea;
      if not Cadena.Siguiente(Fichero, Linea, Salto) then
        Break;
      T := Cadena.TipoEn(Fichero, Linea);
      if T = nil then
        Break;
      // sus campos publicados: los componentes de su form
      for var Campo in T.Campos do
        if not Campo.DeClase and (Campo.Visibilidad in [vpDefecto, vpPublicada]) then
          Result := Result + [Campo.Nombre + '=' + T.Nombre];
    end;
  finally
    Cadena.Free;
  end;
end;

{ La clase contra la que se juzga una propiedad: la del componente; la de un
  frame en linea, si no esta en la tabla (es del proyecto), TFrame - medido
  el 7-oct-2026: su tamano en el form se negaba con DSGN-082; la del form,
  por la primera de su cadena que la tabla conoce (TForm, TFrame...): la suya
  propia no, que un TForm1 de una demo se llama igual. }
function ClaseDeJuezYPropias(const F: TFormEnEdicion; AObj: TStyleObj; out AClsId: string;
  out APropias: TArray<TPropiedadDelUsuario>): string;
begin
  Result := '';
  AClsId := '';
  APropias := [];
  if AObj <> F.Doc.Root then
  begin
    if F.Tabla.ClaseDeNombre(AObj.ClassName_, AClsId) then
      Exit;
    if (AObj.Clave = 'inline') and
       F.Tabla.ClaseDeNombre(IfThen(F.EsFmx, ID_FMX_FRAME, ID_VCL_FRAME), AClsId) then
      Exit;
    Exit(MsgFmt(SR_DESIGNER_CLASE_SIN_TABLA_FMT, [NombreDe(AObj), AObj.ClassName_,
      F.Marco, MsgText(SF_DESIGNER_QUE_PROPIEDADES), MsgText(SF_DESIGNER_VIA_LINEA)]));
  end;
  // la raiz, por su cadena de ancestros: EL recorredor que juzga tambien el
  // lint (Lsp.DesignerMeta); lo que publica una clase del usuario de esa
  // cadena, APropias, lo juzga set por su tipo escrito (HojaDelUsuario)
  if F.HayPas then
  begin
    AClsId := ClaseDeJuezDeRaiz(F.Tabla, F.Pas, F.PasTexto, AObj.ClassName_, APropias);
    if AClsId <> '' then
      Exit;
  end;
  Result := MsgFmt(SR_DESIGNER_CLASE_SIN_TABLA_FMT, [NombreDe(AObj), AObj.ClassName_,
    F.Marco, MsgText(SF_DESIGNER_QUE_PROPIEDADES), MsgText(SF_DESIGNER_VIA_LINEA)]);
end;

function ClaseDeJuez(const F: TFormEnEdicion; AObj: TStyleObj; out AClsId: string): string;
var
  Propias: TArray<TPropiedadDelUsuario>;
begin
  Result := ClaseDeJuezYPropias(F, AObj, AClsId, Propias);
end;

// la propiedad casi bien escrita: la mas parecida del primer trozo, si es una
// y la ruta entera existe con ella (Hint.Color por Font.Color decia, y Hint es
// una cadena); y ninguna si es de la otra plataforma, que ya lo dice el juez
// (PistaDelOtroMarco: Action por Caption en un TButton FMX). DSGN-087 de la 1.20
function ParecidaA(M: TMetaTable; const AClsId, AProp: string): string;
var
  Segs, Nombres: TArray<string>;
  Cand: string;
begin
  Result := '';
  Segs := AProp.Split(['.']);
  if (Length(Segs) = 0) or Publica(M, AClsId, Segs[0]) or
     (PistaDelOtroMarco(M, AClsId, AProp) <> '') then
    Exit;
  Nombres := [];
  for var Par in M.Props do
    if Par.Key.StartsWith(ClaveProp(AClsId, '')) and (Par.Value.Kind <> 'm') then
      Nombres := Nombres + [Par.Value.Name];
  Cand := ElMasParecido(Segs[0], Nombres, Max(2, Length(Segs[0]) div 3));
  if Cand = '' then
    Exit;
  Segs[0] := Cand;
  if not LlegaALaHoja(M, AClsId, string.Join('.', Segs)) then
    Exit;
  Result := MsgFmt(SF_DESIGNER_QUIZAS_FMT, [string.Join('.', Segs)]);
end;

// los componentes del form que si caben en una propiedad de la clase ATipoId
function LosQueCaben(const F: TFormEnEdicion; const ATipoId: string): string;
var
  L: TStringList;

  procedure Mira(O: TStyleObj);
  var
    Id: string;
  begin
    if (O.ObjName <> '') and (ClaseDeJuez(F, O, Id) = '') and F.Tabla.Desciende(Id, ATipoId) then
      L.Add(O.ObjName);
    if O.Clave = 'inline' then
      Exit; // lo de dentro es del frame
    for var K in O.Children do
      Mira(K);
  end;

begin
  L := TStringList.Create;
  try
    Mira(F.Doc.Root);
    if L.Count = 0 then
      Exit(MsgText(SF_DESIGNER_NO_CABE_NINGUNO));
    Result := MsgFmt(SF_DESIGNER_CABEN_FMT, [NombresConTope(L)]);
  finally
    L.Free;
  end;
end;

{ El valor no es de los que el cargador acepta para la propiedad, por lo que
  sabe la tabla (nunca una lista de nombres): una referencia, un componente
  de este form de su clase o de una que desciende de ella (el DataSource de
  un TDBGrid, un TDataSource; el FocusControl de un TLabel, un TWinControl);
  lo demas, por la base de su tipo (BaseQueNoCasa: un entero o una constante
  suya, un numero, un caracter, una cadena). Los enumerados y los conjuntos
  ya los juzgo JuzgaPropiedad. }
function TipoQueNoCasa(const F: TFormEnEdicion; AObj: TStyleObj;
  const AProp, AValor: string; const AHoja: TPropRec; out AAviso: string): string;
var
  Toma, Parecida, RefId: string;
  Ref: TStyleObj;
begin
  Result := '';
  if AHoja.Kind = 'c' then
  begin
    AAviso := '';
    // un objeto suyo (Font, Lines), no un componente: no toma un valor, sino
    // sus sub-propiedades, o una lista que set no escribe (la guia era la de
    // una referencia: revision de la 1.17.0). LA regla, en la tabla (1.20)
    if F.Tabla.EsObjetoPropio(AHoja.TypeId) then
    begin
      if F.Tabla.Desciende(AHoja.TypeId, ID_CADENAS) then
        Exit(MsgFmt(SR_DESIGNER_SET_LISTA_FMT, [NombreDe(AObj), AProp, AHoja.TypeName, AProp]));
      Exit(MsgFmt(SR_DESIGNER_SET_TIPO_FMT, [NombreDe(AObj), AProp, AHoja.TypeName,
        MsgText(SF_DESIGNER_TOMA_SUBPROPIEDADES), AValor, '']));
    end;
    // nil la quita (PoneValor: el IDE no la escribe)
    if SameText(AValor, 'nil') then
      Exit;
    // un componente de este form (PopupMenu1), o de otro (Form2.ImageList1)
    if EsIdentificador(AValor, False) then
    begin
      Ref := ObjetoDelForm(F.Doc, AValor);
      if Ref = nil then
        Exit(MsgFmt(SR_DESIGNER_REFERENCIA_NO_ESTA_FMT, [AValor, F.DfmNombre, NombreDe(AObj), AProp]));
      // de su clase o de una hija; lo que la tabla no conoce no se juzga
      if F.Tabla.Classes.ContainsKey(ClaveDeIdentificador(AHoja.TypeId)) and
         (ClaseDeJuez(F, Ref, RefId) = '') and not F.Tabla.Desciende(RefId, AHoja.TypeId) then
        Exit(MsgFmt(SR_DESIGNER_REFERENCIA_TIPO_FMT, [AValor, Ref.ClassName_, NombreDe(AObj),
          AProp, AHoja.TypeName, LosQueCaben(F, AHoja.TypeId)]));
      Exit;
    end;
    if EsIdentificador(AValor, True) then
      Exit;
    Exit(MsgFmt(SR_DESIGNER_SET_TIPO_FMT, [NombreDe(AObj), AProp, AHoja.TypeName,
      MsgText(SF_DESIGNER_TOMA_COMPONENTE), AValor, '']));
  end;
  Toma := BaseQueNoCasa(F.Tabla, AHoja, AValor, AAviso, Parecida);
  if Toma <> '' then
    Result := MsgFmt(SR_DESIGNER_SET_TIPO_FMT, [NombreDe(AObj), AProp, AHoja.TypeName, Toma,
      AValor, Parecida]);
end;

{ El juez de las lineas del form que guardan un componente (AnalizaImpacto):
  la propiedad AProp de AObj por la tabla; lo que no sabe, si. delete y el
  renombrado EXIGEN la tabla al abrir el form (AbreForm), a proposito: sin
  ella, borrar un Client se llevaba el Align = Client de otro (un enumerado),
  y mientras se genera la respuesta dice que se espere (DSGN-051). Sin tabla
  - ningun llamador hoy -, todo nombre seria referencia. }
{ Si la propiedad de AHoja guarda una REFERENCIA a otro componente: un
  componente ('c'), o un tipo 'o' sin base conocida - una interfaz que guarda
  un componente (el Reader de un TFDBatchMove, el Provider de REST) se escribe
  como su nombre y TReader la resuelve igual (segunda revision de la 1.17.0:
  se quedaba al renombrar). LA regla: la usan el juez de las referencias
  (renombrar, borrar) y set, que solo deja vaciar con nil una de estas (H1 de
  Hermes, 1.18.2). }
function HojaDeReferencia(const ATabla: TMetaTable; const AHoja: TPropRec): Boolean;
begin
  Result := (AHoja.Kind = 'c') or
    ((AHoja.Kind = 'o') and not ATabla.Bases.ContainsKey(ClaveDeIdentificador(AHoja.TypeId)));
end;

function JuezDeReferencias(const F: TFormEnEdicion): TJuezDeReferencia;
var
  Fm: TFormEnEdicion;
begin
  Fm := F;
  Result :=
    function(AObj: TStyleObj; const AProp: string): Boolean
    var
      Id: string;
      Hoja: TPropRec;
      Hay: Boolean;
    begin
      Result := True;
      if (Fm.Tabla = nil) or (ClaseDeJuez(Fm, AObj, Id) <> '') then
        Exit;
      JuzgaPropiedad(Fm.Tabla, Id, AProp, '', Hoja, Hay);
      if Hay and (Hoja.Kind <> '?') then
        Result := HojaDeReferencia(Fm.Tabla, Hoja);
    end;
end;

{ Lo que set mira de una propiedad y su valor antes de abrir nada: el nombre,
  que haya valor y que sea de una linea. '' si vale. }
function PropiedadQueNoVa(const AProp, AValor: string): string;
begin
  Result := '';
  if not EsIdentificador(AProp.Trim, True) then
    Exit(MsgFmt(SR_DESIGNER_SET_PROP_FMT, [AProp]));
  if AValor.Trim = '' then
    Exit(MsgText(SR_DESIGNER_SET_SIN_VALOR));
  if AValor.Contains(#10) or AValor.Contains(#13) then
    Exit(MsgText(SR_DESIGNER_SET_VALOR_LINEA));
end;

{ UNA propiedad de ANombre sobre el form ABIERTO, sin guardar: lo que set
  juzga antes de escribir y como la escribe (el IDE). '' si se puso, con
  AInfo; si no, la negativa. Despues el arbol se relee (Reparsea): un objeto
  leido antes no vale. La usan set de una propiedad, set de varias (props) e
  insert con propiedades (3.10 de la 1.18.0); estaba dentro de PoneValor. }
function PonEnMemoria(const F: TFormEnEdicion; const ANombre, AProp, AValor: string;
  out AInfo: TValorPuesto): string;
var
  Obj: TStyleObj;
  ClsId, Prop, V, Juicio, Antes, Texto, Aviso: string;
  Trozos: TArray<string>;
  Hoja: TPropRec;
  HayHoja, Comillas, WasThere, Quita: Boolean;
  Propias: TArray<TPropiedadDelUsuario>; // las que publica el usuario en la raiz
  Propia: TPropiedadDelUsuario;
  DelUsuario, Juzgado: Boolean;
  Ini, Fin: Integer;
begin
  AInfo := Default(TValorPuesto);
  Prop := AProp.Trim;
  AInfo.Prop := Prop;
  Result := PropiedadQueNoVa(AProp, AValor);
  if Result <> '' then
    Exit;
  Result := BuscaComponente(F, ANombre, Obj);
  if Result <> '' then
    Exit;
  Result := ClaseDeJuezYPropias(F, Obj, ClsId, Propias);
  if Result <> '' then
    Exit;
  // en FMX Left/Top no colocan un control (son el sitio del icono de un no
  // visual, TComponent.DefineProperties): se escribian, se contestaba bien
  // y no se movia nada (3.7, Hermes). Su sitio es Position.X/Y.
  if F.EsFmx and MatchText(Prop, ['Left', 'Top']) and F.Tabla.Desciende(ClsId, ID_FMX_CONTROL) then
    Exit(MsgFmt(SR_DESIGNER_FMX_LEFT_TOP_FMT, [NombreDe(Obj), Prop,
      IfThen(SameText(Prop, 'Left'), 'Position.X', 'Position.Y')]));
  // una ruta por una propiedad que en su bloque guarda una referencia
  // (PopupMenu = PopupMenu1): AutoPopup es de PopupMenu1, y el cargador lee
  // la ruta antes de resolver la referencia (3.3 de la 1.18.0, medido:
  // PopupMenu.AutoPopup se escribia en el boton y el form no cargaba)
  var Pre, Ref: string;
  if Prop.Contains('.') and RutaPorReferencia(F.Tabla, ClsId, Prop,
     ReferenciasDeObjeto(LineasDeForm(F.Doc.Lines), Obj.StartLine - 1), Pre, Ref) then
    Exit(MsgFmt(SR_DESIGNER_SET_POR_REFERENCIA_FMT, [NombreDe(Obj), Pre, Ref,
      Copy(Prop, Length(Pre) + 2, MaxInt), Pre, Ref, Ref, Copy(Prop, Length(Pre) + 2, MaxInt)]));
  V := AValor.Trim;
  // una propiedad que publica una clase del USUARIO en la raiz (TBaseForm.Modo):
  // la tabla no la conoce y se negaba "no existe en TForm"; se juzga por su
  // tipo escrito (HojaDelUsuario) y el resto del juicio sigue con su hoja. Una
  // redeclarada sin tipo (property Caption;) es la del ancestro: la tabla la juzga
  DelUsuario := False;
  Juzgado := False;
  Juicio := '';
  if (Obj = F.Doc.Root) and PropiedadDelUsuarioLlamada(Propias, PrimerTrozo(Prop, ['.']), Propia) and
     (Propia.Tipo <> '') then
  begin
    if Prop.Contains('.') then
      Exit(MsgFmt(SR_DESIGNER_SET_INVALIDO_FMT, [NombreDe(Obj), Prop, V,
        MsgFmt(SF_DESIGNER_RUTA_DEL_USUARIO_FMT, [PrimerTrozo(Prop, ['.']), Propia.Clase,
        TPath.GetFileName(Propia.Fichero)]), '']));
    Juicio := HojaDelUsuario(F.Tabla, Propia, V, Hoja, Juzgado);
    if Juicio <> '' then
      Exit(MsgFmt(SR_DESIGNER_SET_INVALIDO_FMT, [NombreDe(Obj), Prop, V, Juicio, '']));
    HayHoja := True;
    DelUsuario := True;
  end
  else
    Juicio := JuzgaPropiedad(F.Tabla, ClsId, Prop, V, Hoja, HayHoja);
  if HayHoja and (Hoja.Kind = 'm') then
    Exit(MsgFmt(SR_DESIGNER_SET_EVENTO_FMT, [Prop, NombreDe(Obj), Prop]));
  // nil, sin comillas, solo vacia una REFERENCIA a otro componente (la quita:
  // el IDE no la escribe). En una propiedad que no lo es se escribia como el
  // texto 'nil' (StyleLookup = 'nil': H1 de Hermes, 1.18.2); se dice como se
  // escribe ese texto y como se quita la propiedad. Lo que la tabla no conoce
  // ('?') no se juzga
  if SameText(V, 'nil') and HayHoja and (Hoja.Kind <> '?') and not HojaDeReferencia(F.Tabla, Hoja) then
    Exit(MsgFmt(SR_DESIGNER_SET_NIL_FMT, [NombreDe(Obj), Prop]));
  // una cadena (o un caracter): un literal del form ('Acci'#243'n', 'a' +
  // 'b') se lee y se vuelve a escribir como el IDE (TrozosDeLiteral: los
  // acentos como #N, en trozos de 64 en las lineas de debajo); lo que no es
  // un literal es el texto, y se le ponen las comillas. Que es una cadena lo
  // dice la base de su tipo, leida del fuente. Un 'Accion' acentuado entre
  // comillas se escribia en crudo, un #hashtag se negaba diciendo que set
  // ponia las comillas, y una cadena de 4.095 caracteres iba en una linea
  // que el IDE no lee (revision de la 1.17.0)
  Comillas := False;
  Trozos := [];
  var Base := '';
  if HayHoja and (Hoja.Kind = 'o') then
    F.Tabla.Bases.TryGetValue(ClaveDeIdentificador(Hoja.TypeId), Base);
  // el texto que la propiedad YA tenia: un sustituto suelto que ya estaba se
  // escribe como estaba (la cuenta por valor de los escritores); se negaba
  // igual que uno nuevo (R8 del revisor del punto 4 de la 1.18.2)
  var TextoAntes := F.Doc.LiteralDe(Obj, Prop);
  if MatchText(Base, ['string', 'char']) then
  begin
    if not LeeLiteralDeForm(V, Texto) then
    begin
      Texto := AValor;
      Comillas := True;
    end;
    // LA EXCEPCION DECLARADA de [Contenido] (Lsp.Attributes): lo que se
    // escribe dentro de un fichero no se expande, salvo el TEXTO de un valor
    // de value / props, que si empieza por una unidad virtual pasa a la ruta
    // real: un literal de ruta en un form tiene que funcionar en ejecucion, y
    // el agente ve las rutas como srvd:\ (delphi_list, el eco de set). La
    // puerta solo expandia el valor ENTERO: 'srvd:\x' entre comillas o dentro
    // de props llegaba tal cual al .dfm (B-9, 10-oct-2026). El coste: un
    // Caption que empiece por srvd:\ a proposito se escribe con la letra.
    Texto := ExpandDriveValue(Texto);
    // medio caracter: el literal lo escribe #N y el codificador no lo ve
    var Suelto := SueltoEnLiteral(Texto, TextoAntes);
    if Suelto <> '' then
      Exit(Suelto);
    Trozos := TrozosDeLiteral(Texto);
    V := string.Join(' ', Trozos);
    if not DelUsuario then
      Juicio := JuzgaPropiedad(F.Tabla, ClsId, Prop, V, Hoja, HayHoja);
  end
  // un literal en una propiedad que por su tipo no es una cadena (un
  // Variant, o una que la tabla no conoce): escrito como el IDE tambien;
  // iba en crudo (P6 de la segunda revision de la 1.17.0)
  else if LeeLiteralDeForm(V, Texto) then
  begin
    Texto := ExpandDriveValue(Texto); // la misma excepcion, la de arriba
    var Suelto := SueltoEnLiteral(Texto, TextoAntes);
    if Suelto <> '' then
      Exit(Suelto);
    Trozos := TrozosDeLiteral(Texto);
    V := string.Join(' ', Trozos);
    if not DelUsuario then
      Juicio := JuzgaPropiedad(F.Tabla, ClsId, Prop, V, Hoja, HayHoja);
  end;
  // un valor de una linea: una lista, una coleccion o un bloque binario no
  if not ValidStyleValue(V) or EsValorDeBloque(V) then
    Exit(MsgFmt(SR_DESIGNER_SET_GRAMATICA_FMT, [V]));
  if Juicio <> '' then
    Exit(MsgFmt(SR_DESIGNER_SET_INVALIDO_FMT, [NombreDe(Obj), Prop, V, Juicio,
      ParecidaA(F.Tabla, ClsId, Prop)]));
  Aviso := '';
  if HayHoja then
  begin
    Result := TipoQueNoCasa(F, Obj, Prop, V, Hoja, Aviso);
    if Result <> '' then
      Exit;
  end;
  // un numero de coma flotante, escrito como el IDE (FlotanteDeForm): 130
  // en un Position.X es 130.000000000000000000 - nadie lo reescribe despues,
  // el form no pasa por el IDE (David, 7-oct-2026)
  // (y un $hex, que el cargador tambien lee; uno que su tipo no guarda -
  // una Single de 1E39 - no se escribe)
  if (Base = 'single') or (Base = 'float') then
  begin
    var Num: Extended;
    var N64: Int64;
    var EsNum := TryStrToFloat(V, Num, TFormatSettings.Invariant);
    if not EsNum and TryStrToInt64(V, N64) then
    begin
      Num := N64;
      EsNum := True;
    end;
    // la gramatica ya paso (TipoQueNoCasa): uno que no se lee es que no cabe
    // (1E400 en un Double se escribia tal cual: segunda revision de la 1.17.0)
    var Tope: Extended := MaxDouble;
    if Base = 'single' then
      Tope := MaxSingle;
    if not EsNum or IsNan(Num) or IsInfinite(Num) or (Abs(Num) > Tope) then
      Exit(MsgFmt(SR_DESIGNER_SET_TIPO_FMT, [NombreDe(Obj), Prop, Hoja.TypeName,
        MsgText(SF_DESIGNER_TOMA_NUMERO_QUE_CABE), V, '']));
    V := FlotanteDeForm(Num, Base = 'single');
  end;
  if Length(Trozos) = 0 then
    Trozos := [V];
  // nil en una referencia la quita: el IDE no la escribe
  Quita := HayHoja and (Hoja.Kind = 'c') and SameText(V, 'nil');
  // lo que habia, entero: un bloque de varias lineas no se reescribe con uno
  Antes := '';
  if F.Doc.PropLines(Obj, Prop, Ini, Fin) then
  begin
    Antes := ValorEnteroDe(F.Doc.Lines, LineasDeForm(F.Doc.Lines), Ini);
    if EsValorDeBloque(Antes) then
      Exit(MsgFmt(SR_DESIGNER_SET_BLOQUE_FMT, [NombreDe(Obj), Prop, Ini + 1, Fin + 1, F.DfmNombre]));
  end;
  if Quita then
  begin
    WasThere := F.Doc.DeleteProp(Obj, Prop);
    // no habia linea: nada que quitar ni que guardar (contestaba removed
    // sin haber quitado nada: segunda revision de la 1.17.0)
    AInfo.NadaQueQuitar := not WasThere;
  end
  else
    F.Doc.SetPropTrozos(Obj, Prop, Trozos, WasThere);
  AInfo.Valor := V;
  AInfo.SinJuez := not HayHoja;
  AInfo.Antes := Antes;
  AInfo.HabiaAntes := WasThere;
  AInfo.Comillas := Comillas;
  AInfo.Quitada := Quita and WasThere;
  AInfo.Aviso := Aviso;
  // las lineas se movieron: el arbol, otra vez (Obj ya no vale)
  F.Doc.Reparsea;
end;

{ Lo que la respuesta de set dice de una propiedad puesta, en AObj: un nil
  sobre una referencia que no estaba, la nota DSGN-112 (insert con props lo
  daba como value 'nil' sin decir nada: revisor 2 de la noche, B-3) }
procedure PonValorPuesto(AObj: TJSONObject; const ANombre: string; const AInfo: TValorPuesto);
begin
  if AInfo.NadaQueQuitar then
  begin
    AObj.AddPair('note', MsgFmt(SN_DESIGNER_NADA_QUE_QUITAR_FMT, [ANombre, AInfo.Prop]));
    Exit;
  end;
  AObj.AddPair('value', AInfo.Valor);
  if AInfo.HabiaAntes then
    AObj.AddPair('previous', AInfo.Antes);
  if AInfo.Comillas then
    AObj.AddPair('quoted', TJSONBool.Create(True));
  if AInfo.Quitada then
    AObj.AddPair('removed', TJSONBool.Create(True));
  if AInfo.Aviso <> '' then
    AObj.AddPair('warning', AInfo.Aviso);
  // lo que guarda el escritor del IDE, si no es lo que se dio (1.22.1)
  if AInfo.NoGuardada then
    AObj.AddPair('notStored', MsgFmt(SN_DESIGNER_IDE_NO_GUARDA_FMT, [AInfo.Prop, ANombre]))
  else if AInfo.GuardadaEnOtras then
  begin
    // una stored False: lo que el IDE escribe por ella (DSGN-167)
    AObj.AddPair('storedIn', AInfo.GuardadaEn);
    AObj.AddPair('storedNote', MsgFmt(SN_DESIGNER_IDE_GUARDA_EN_OTRAS_FMT, [AInfo.Prop, ANombre,
      IfThen(AInfo.GuardadaEn = '', MsgText(SF_DESIGNER_IDE_NADA_CAMBIA), AInfo.GuardadaEn)]));
  end
  else if AInfo.GuardadaComo <> '' then
  begin
    AObj.AddPair('storedAs', AInfo.GuardadaComo);
    AObj.AddPair('storedNote', MsgFmt(SN_DESIGNER_IDE_GUARDA_OTRO_FMT, [AInfo.Prop, ANombre,
      AInfo.GuardadaComo, AInfo.Valor]));
  end;
end;

function PoneValor(const APath, AComponente, AProp, AValor: string): string;
var
  F: TFormEnEdicion;
  Obj: TStyleObj;
  Info: TValorPuesto;
  Nombre, NotaLector: string;
  LineaN, Ini, Fin: Integer;
  Ret: TJSONObject;
begin
  Result := PropiedadQueNoVa(AProp, AValor);
  if Result <> '' then
    Exit;
  Result := AbreForm(APath, False, True, F);
  if Result <> '' then
    Exit;
  try
    Result := BuscaComponente(F, AComponente, Obj);
    if Result <> '' then
      Exit;
    Nombre := NombreDe(Obj);
    Result := PonEnMemoria(F, Nombre, AProp, AValor, Info);
    if Result <> '' then
      Exit;
    if Info.NadaQueQuitar then
      Exit(MsgFmt(SN_DESIGNER_NADA_QUE_QUITAR_FMT, [Nombre, Info.Prop]));
    Result := CargaLoPuesto(F, Nombre, [Info], NotaLector);
    if Result <> '' then
      Exit;
    // sus propiedades como las guarda el escritor del IDE (1.22.1)
    var NotaIde: string;
    var NoGuarda: TArray<string>;
    var Otras: TArray<TGuardadaComo>;
    F.Doc.SetLines(ConLasPropiedadesDelIde(F, F.Doc.Lines, Nombre, [Info.Prop], NotaIde, NoGuarda, Otras));
    MarcaLoQueGuarda(Info, NoGuarda, Otras);
    Result := F.Doc.Guarda; // solo si el parser del IDE lee el resultado (9.B)
    if Result <> '' then
      Exit;
    // el arbol se releyo al guardar: su linea, la de ahora
    LineaN := 0;
    Obj := ObjetoPorNombre(F.Doc, Nombre);
    if not Info.Quitada and (Obj <> nil) and F.Doc.PropLines(Obj, Info.Prop, Ini, Fin) then
      LineaN := Ini + 1
    // una stored False no tiene su linea: la de lo que el IDE escribe por ella
    else if (Obj <> nil) and (Info.GuardadaEnProp <> '') and
      F.Doc.PropLines(Obj, Info.GuardadaEnProp, Ini, Fin) then
      LineaN := Ini + 1;
    Ret := TJSONObject.Create;
    try
      Ret.AddPair('set', Nombre + '.' + Info.Prop);
      PonValorPuesto(Ret, Nombre, Info);
      Ret.AddPair('file', F.DfmNombre);
      Ret.AddPair('line', TJSONNumber.Create(LineaN));
      if NotaLector <> '' then
        Ret.AddPair('readerNote', NotaLector);
      if NotaIde <> '' then
        Ret.AddPair('ideNote', NotaIde);
      PonLista(Ret, 'lint', AvisosDespues(F, F.Doc.TextoDe(F.Doc.Lines)));
      Result := Ret.ToJSON;
    finally
      Ret.Free;
    end;
  finally
    F.Doc.Free;
  end;
end;

{ Los pares 'Prop=valor' de una lista de props (TrozosDeEstado: EL lector de
  esa sintaxis), cada uno con lo que set mira antes de abrir nada. '' si
  valen; si no, la negativa con el numero de la entrada. Name no entra (se
  renombra solo: toca la unidad) ni una propiedad dos veces. }
function ParesDeProps(const AProps: string; out AProps_, AValores: TArray<string>): string;
begin
  Result := '';
  AProps_ := [];
  AValores := [];
  var Trozos: TArray<string>;
  Result := TrozosDeEstado(AProps, Trozos);
  if Result <> '' then
    Exit;
  if Length(Trozos) = 0 then
    Exit(MsgText(SR_DESIGNER_PROPS_VACIO));
  for var I := 0 to High(Trozos) do
  begin
    var P := Pos('=', Trozos[I]);
    if P = 0 then
      Exit(MsgFmt(SR_DESIGNER_PROPS_PAR_FMT, [I + 1, Trozos[I]]));
    var Prop := Copy(Trozos[I], 1, P - 1).Trim;
    var Valor := Copy(Trozos[I], P + 1, MaxInt).Trim;
    var Mal := PropiedadQueNoVa(Prop, Valor);
    if Mal <> '' then
      Exit(MsgFmt(SR_DESIGNER_PROPS_ENTRADA_FMT, [I + 1, Prop, Mal]));
    if SameText(Prop, 'Name') then
      Exit(MsgFmt(SR_DESIGNER_PROPS_NAME_FMT, [I + 1]));
    for var J := 0 to High(AProps_) do
      if SameText(AProps_[J], Prop) then
        Exit(MsgFmt(SR_DESIGNER_PROPS_DOBLE_FMT, [Prop, J + 1, I + 1]));
    AProps_ := AProps_ + [Prop];
    AValores := AValores + [Valor];
  end;
end;

{ set de VARIAS propiedades de un componente (props, 3.10 de la 1.18.0): cada
  una juzgada como set juzga una (PonEnMemoria), todas en memoria y una sola
  escritura - todo o nada: si una no vale, no se escribe ninguna y se dice
  cual. }
function PoneValores(const APath, AComponente, AProps: string): string;
var
  F: TFormEnEdicion;
  Obj: TStyleObj;
  Props, Valores: TArray<string>;
  Infos: TArray<TValorPuesto>;
  Nombre, NotaLector: string;
  Ret, Una: TJSONObject;
  Lista: TJSONArray;
begin
  Result := ParesDeProps(AProps, Props, Valores);
  if Result <> '' then
    Exit;
  Result := AbreForm(APath, False, True, F);
  if Result <> '' then
    Exit;
  try
    Result := BuscaComponente(F, AComponente, Obj);
    if Result <> '' then
      Exit;
    Nombre := NombreDe(Obj);
    SetLength(Infos, Length(Props));
    for var I := 0 to High(Props) do
    begin
      Result := PonEnMemoria(F, Nombre, Props[I], Valores[I], Infos[I]);
      if Result <> '' then
        Exit(MsgFmt(SR_DESIGNER_PROPS_ENTRADA_FMT, [I + 1, Props[I], Result]));
    end;
    // ninguna cambia nada (solo nil sobre referencias que no estan): no se
    // escribe, como set de una - reescribia, con copia en la papelera y el EOL
    // normalizado, y decia OK (revisor 2 de la noche, B-3)
    var Cambia := False;
    for var I := 0 to High(Infos) do
      if not Infos[I].NadaQueQuitar then
        Cambia := True;
    if not Cambia then
      Exit(MsgFmt(SN_DESIGNER_NADA_QUE_QUITAR_FMT, [Nombre, string.Join(', ', Props)]));
    Result := CargaLoPuesto(F, Nombre, Infos, NotaLector);
    if Result <> '' then
      Exit;
    // sus propiedades como las guarda el escritor del IDE (1.22.1)
    var NotaIde: string;
    var NoGuarda: TArray<string>;
    var Otras: TArray<TGuardadaComo>;
    F.Doc.SetLines(ConLasPropiedadesDelIde(F, F.Doc.Lines, Nombre, PropsDe(Infos), NotaIde, NoGuarda, Otras));
    for var I := 0 to High(Infos) do
      MarcaLoQueGuarda(Infos[I], NoGuarda, Otras);
    Result := F.Doc.Guarda; // una escritura, si el parser del IDE la lee (9.B)
    if Result <> '' then
      Exit;
    Ret := TJSONObject.Create;
    try
      Ret.AddPair('set', Nombre);
      Lista := TJSONArray.Create;
      Ret.AddPair('props', Lista);
      for var I := 0 to High(Infos) do
      begin
        Una := TJSONObject.Create;
        Lista.AddElement(Una);
        Una.AddPair('prop', Infos[I].Prop);
        PonValorPuesto(Una, Nombre, Infos[I]);
      end;
      Ret.AddPair('file', F.DfmNombre);
      if NotaLector <> '' then
        Ret.AddPair('readerNote', NotaLector);
      if NotaIde <> '' then
        Ret.AddPair('ideNote', NotaIde);
      PonLista(Ret, 'lint', AvisosDespues(F, F.Doc.TextoDe(F.Doc.Lines)));
      Result := Ret.ToJSON;
    finally
      Ret.Free;
    end;
  finally
    F.Doc.Free;
  end;
end;

// quita (ADelta < 0) o pone (ADelta > 0) espacios de sangria a una linea
function Resangra(const S: string; ADelta: Integer): string;
var
  K: Integer;
begin
  if (S = '') or (ADelta = 0) then
    Exit(S);
  if ADelta > 0 then
    Exit(StringOfChar(' ', ADelta) + S);
  K := 0;
  while (K < -ADelta) and (K < Length(S)) and (S[K + 1] = ' ') do
    Inc(K);
  Result := Copy(S, K + 1, MaxInt);
end;

function MueveComponente(const APath, AComponente, AParent: string): string;
var
  F: TFormEnEdicion;
  Obj, Padre, Viejo: TStyleObj;
  Bloque, Lineas: TArray<string>;
  Delta, I, Ini, Fin, Largo, Dest, Tab, TIni, TFin: Integer;
  ClsId, NomObj, NomViejo, NomPadre, NotaOrden: string;
  ConTab: Boolean;
  Ret: TJSONObject;
  Antes, AntesPas: TArray<Byte>;
begin
  // los bytes que se juzgan (el juez del orden, abajo), leidos con el cerrojo
  Result := AbreFormParaJuzgar(APath, False, True, F, Antes, AntesPas);
  if Result <> '' then
    Exit;
  try
    Result := BuscaComponente(F, AComponente, Obj);
    if Result <> '' then
      Exit;
    Result := QueNoSeToca(F, Obj);
    if Result <> '' then
      Exit;
    Result := BuscaComponente(F, AParent, Padre);
    if Result <> '' then
      Exit;
    if EsDescendiente(Padre, Obj) then
      Exit(MsgFmt(SR_DESIGNER_PADRE_CICLO_FMT, [NombreDe(Obj), NombreDe(Padre)]));
    if Padre = Obj.Parent then
      Exit(MsgFmt(SN_DESIGNER_YA_ESTA_FMT, [NombreDe(Obj), NombreDe(Padre)]));
    Result := PadreQueNoVale(F, Padre, True);
    if Result <> '' then
      Exit;
    Viejo := Obj.Parent;
    Ini := Obj.StartLine - 1;
    Fin := Obj.EndLine - 1;
    Largo := Fin - Ini + 1;
    // el bloque entero, con sus hijos, a la sangria de su nuevo nivel
    Delta := ((Padre.Depth + 1) - Obj.Depth) * 2;
    Bloque := Copy(F.Doc.Lines, Ini, Largo);
    for I := 0 to High(Bloque) do
      Bloque[I] := Resangra(Bloque[I], Delta);
    // la cabecera SIN su [n]: es la posicion entre los hijos del ancestro del
    // padre VIEJO, y TReader la aplica igual en el nuevo - un 'ButtonX: TButton
    // [0]' llevado a otro padre quedaba el primero de sus hermanos nuevos. El
    // sitio lo decide el juez del orden, abajo (revisor de version de la
    // 1.18.0, medido)
    var ClaveC, NomC, ClaseC, RestoC: string;
    if LineaDeObjeto(Bloque[0], ClaveC, NomC, ClaseC, RestoC) and RestoC.TrimLeft.StartsWith('[') and
       (RestoC.IndexOf(']') >= 0) then
      Bloque[0] := LeadingWhite(Bloque[0]) + ComponeLineaDeObjeto(ClaveC, NomC, ClaseC) +
        Copy(RestoC, RestoC.IndexOf(']') + 2, MaxInt);
    // y el TabOrder en el padre nuevo: el ultimo de su tabulador, el que diga
    // el juez (abajo, que le pregunta SIN esta linea); el propio, si no
    // contesta o si su escritor no lo escribe
    Tab := 0;
    ConTab := (ClaseDeJuez(F, Obj, ClsId) = '') and Publica(F.Tabla, ClsId, 'TabOrder');
    if ConTab then
    begin
      Tab := SiguienteTabOrder(F.Doc, Padre);
      if F.Doc.PropLines(Obj, 'TabOrder', TIni, TFin) then
        Bloque[TIni - Ini] := LineasDePropiedad(LeadingWhite(Bloque[TIni - Ini]), 'TabOrder',
          [IntToStr(Tab)])[0]
      else
        Insert(LineasDePropiedad(SangriaDeNivel(Padre.Depth + 2), 'TabOrder', [IntToStr(Tab)]),
          Bloque, 1);
    end;
    Dest := Padre.EndLine - 1;
    Lineas := ConBloqueMovido(F.Doc.Lines, Bloque, Ini, Largo, Dest);
    // los nombres ANTES de guardar: Guarda relee el arbol y estos objetos se van
    NomObj := NombreDe(Obj);
    NomViejo := NombreDe(Viejo);
    NomPadre := NombreDe(Padre);
    // donde lo deja el IDE entre sus hermanos nuevos, no siempre el ultimo
    // (3.11: el juez del orden)
    var TabDelIde: Integer;
    Lineas := DondeLoDejaElIde(F, Lineas, NomObj, NomPadre, Dest, Length(Bloque), ConTab, NotaOrden, TabDelIde);
    if ConTab and (TabDelIde >= 0) then
    begin
      Tab := TabDelIde;
      PonSuTabOrder(F, Lineas, NomObj, Tab);
    end;
    // con el cerrojo: el form es el que se juzgo
    EnterFileEdit;
    try
      Result := CambioDesdeQueSeJuzgo(F, Antes, AntesPas);
      if Result = '' then
      begin
        F.Doc.SetLines(Lineas);
        Result := F.Doc.Guarda; // solo si el parser del IDE lee el resultado (9.B)
      end;
    finally
      LeaveFileEdit;
    end;
    if Result <> '' then
      Exit;
    Ret := TJSONObject.Create;
    try
      Ret.AddPair('moved', NomObj);
      Ret.AddPair('from', NomViejo);
      Ret.AddPair('to', NomPadre);
      Ret.AddPair('file', F.DfmNombre);
      Ret.AddPair('line', TJSONNumber.Create(Dest + 1));
      Ret.AddPair('endLine', TJSONNumber.Create(Dest + Length(Bloque)));
      if ConTab then
        Ret.AddPair('tabOrder', TJSONNumber.Create(Tab));
      if NotaOrden <> '' then
        Ret.AddPair('orderNote', NotaOrden);
      PonLista(Ret, 'lint', AvisosDespues(F, F.Doc.TextoDe(F.Doc.Lines)));
      Result := Ret.ToJSON;
    finally
      Ret.Free;
    end;
  finally
    F.Doc.Free;
  end;
end;

function RenombraComponente(const APath, AComponente, ANuevo: string): string;
var
  F: TFormEnEdicion;
  Obj: TStyleObj;
  Nuevo, Viejo, Dfm, Pas: string;
  Imp: TImpacto;
  U: TUnidadPas;
  Lista: TArray<string>;
  LineaCampo, Linea: Integer;
  Ret: TJSONObject;
begin
  // la tabla tambien: que lineas del form son referencias (JuezDeReferencias)
  Result := AbreForm(APath, True, True, F);
  if Result <> '' then
    Exit;
  try
    Result := BuscaComponente(F, AComponente, Obj);
    if Result <> '' then
      Exit;
    Result := QueNoSeToca(F, Obj);
    if Result <> '' then
      Exit;
    Viejo := Obj.ObjName;
    U := LeeFuentePascal(F.PasTexto);
    try
      Result := NombreQueNoVale(F, U.Clase(F.Doc.Root.ClassName_), ANuevo, Obj, Nuevo);
    finally
      U.Free;
    end;
    if Result <> '' then
      Exit;
    if Nuevo = Viejo then
      Exit(MsgFmt(SN_DESIGNER_YA_SE_LLAMA_FMT, [Viejo]));
    // donde va su texto si sigue al nombre lo dice la tabla, si ya esta (no
    // se espera: renombrar no la necesita); sin ella, como el TControl del IDE
    var Id: string;
    if not F.Tabla.ClaseDeNombre(Obj.ClassName_, Id) then
      Id := '';
    Result := PlanDeRenombre(F.Doc, Obj, Nuevo, F.PasTexto, F.PasNombre,
      PropiedadesDeTexto(F.Tabla, F.EsFmx, Id), Imp, Dfm, Pas, JuezDeReferencias(F), F.Tabla);
    if Result <> '' then
      Exit;
    Linea := Obj.StartLine;
    Result := EscribeFormYUnidad(F, Dfm, Pas, Pas <> F.PasTexto);
    if Result <> '' then
      Exit;
    LineaCampo := 0;
    for var C in Imp.Campos do
      if MismoIdentificador(C.Nombre, Viejo) then
        LineaCampo := C.Ini + 1;
    Ret := TJSONObject.Create;
    try
      Ret.AddPair('renamed', Viejo);
      Ret.AddPair('to', Nuevo);
      Ret.AddPair('file', F.DfmNombre);
      Ret.AddPair('line', TJSONNumber.Create(Linea));
      if LineaCampo > 0 then
        Ret.AddPair('fieldAt', Donde(F.PasNombre, LineaCampo))
      else
        Ret.AddPair('fieldNote', MsgFmt(SF_DESIGNER_SIN_CAMPO_FMT, [Viejo, F.PasNombre]));
      Lista := [];
      for var I in Imp.Referencias do
        Lista := Lista + [Donde(F.DfmNombre, I + 1)];
      PonLista(Ret, 'referencesRenamed', Lista);
      Lista := [];
      for var Mt in Imp.Metodos do
        if Mt.PorNombre then
          Lista := Lista + [Mt.Nombre + ' (' + Donde(F.PasNombre, Mt.Linea) + ')'];
      PonLista(Ret, 'methodsWithOldName', Lista);
      PonLista(Ret, 'usesInCode', Imp.Usos);
      Ret.AddPair('note', MsgText(SN_DESIGNER_RENAME_NOTE));
      Result := Ret.ToJSON;
    finally
      Ret.Free;
    end;
  finally
    F.Doc.Free;
  end;
end;

{ ---- el orden entre hermanos (3.11 de la 1.18.0) ---- }

{ Los nombres de los hijos de ANombre en un texto de form, en su orden (la
  raiz por su nombre tambien): lo que se compara con el juez. El parser de
  siempre (TStyleDoc.DeTexto), sobre la propuesta y sobre lo que escribio
  TWriter. }
{ LA clave de un hijo de APadre en las listas del juez del orden: su Name, o
  -sin nombre- '(unnamed <clase> #n)', n su numero entre los hermanos sin
  nombre de esa clase (SF_DESIGNER_SIN_NOMBRE_FMT; los parentesis no caben en
  un Name). Solo contaban los que tienen nombre, y un orden que el IDE no
  guarda respecto a uno sin nombre se escribia diciendo DSGN-142 (B3 rev6 de
  la 1.18.2). }
// EL compositor de la clave de un hijo sin nombre: la de ClaveDeHijo y la que
// HijosAlineados renumera en lo escrito por el IDE
function ClaveSinNombre(const AClase: string; N: Integer): string;
begin
  Result := MsgFmt(SF_DESIGNER_SIN_NOMBRE_FMT, [AClase, N]);
end;

// ...y su inversa: si un texto ES una de esas claves (y no un Name), leido de
// la MISMA plantilla que la compone: su prefijo hasta el primer %s y su cierre
function EsClaveSinNombre(const S: string): Boolean;
var
  Fmt, Pre: string;
begin
  Fmt := MsgText(SF_DESIGNER_SIN_NOMBRE_FMT);
  Pre := Copy(Fmt, 1, Pos('%s', Fmt) - 1);
  Result := (Pre <> '') and S.Trim.StartsWith(Pre) and S.Trim.EndsWith(Fmt[Length(Fmt)]);
end;

function ClaveDeHijo(APadre, AHijo: TStyleObj): string;
var
  N: Integer;
begin
  if AHijo.ObjName <> '' then
    Exit(AHijo.ObjName);
  N := 0;
  for var H in APadre.Children do
  begin
    if (H.ObjName = '') and SameText(H.ClassName_, AHijo.ClassName_) then
      Inc(N);
    if H = AHijo then
      Break;
  end;
  Result := ClaveSinNombre(AHijo.ClassName_, N);
end;

{ Los hijos de ANomPadre en ATexto (ANuestro) y en AEscrito, lo que escribe el
  IDE (ASuyo), por su clave (ClaveDeHijo), con los SIN nombre emparejados por
  clase. El escritor escribe tambien los de un ANCESTRO, que se crean antes:
  si escribe mas sin nombre de una clase que el texto, los primeros son del
  ancestro y no estan en la form - fuera, como los heredados con nombre - y
  los demas se numeran desde ahi. Si escribe MENOS, los que faltan los saca el
  IDE de ese padre (un TTimer metido a mano en un TPanel lo escribe en la
  raiz): no son hermanos que juzgar y salen de las dos listas, como antes del
  B3. Contados cada uno por su lado se descuadraban: '(unnamed TTimer #2)',
  que no estaba en el fichero, un DSGN-136 falso y un DSGN-143 con la causa
  falsa (D3 y D4 del revisor de cierre de la 1.18.2, medidos). }
procedure HijosAlineados(const ATexto, AEscrito, ANomPadre: string; out ANuestro, ASuyo: TArray<string>);

  function PadreEn(ADoc: TStyleDoc): TStyleObj;
  begin
    if (ADoc.Root <> nil) and SameText(ADoc.Root.ObjName, ANomPadre) then
      Result := ADoc.Root
    else
      Result := ObjetoPorNombre(ADoc, ANomPadre);
  end;

  function SinNombre(P: TStyleObj; const AClase: string): Integer;
  begin
    Result := 0;
    if P <> nil then
      for var H in P.Children do
        if (H.ObjName = '') and SameText(H.ClassName_, AClase) then
          Inc(Result);
  end;

var
  DocN, DocS: TStyleDoc;
  PN, PS: TStyleObj;
  Vistos: TDictionary<string, Integer>; // clase -> los sin nombre que el IDE lleva ya
begin
  ANuestro := [];
  ASuyo := [];
  DocN := TStyleDoc.DeTexto(ATexto);
  DocS := TStyleDoc.DeTexto(AEscrito);
  Vistos := TDictionary<string, Integer>.Create;
  try
    PN := PadreEn(DocN);
    PS := PadreEn(DocS);
    if PN <> nil then
      for var H in PN.Children do
        if (H.ObjName <> '') or (SinNombre(PS, H.ClassName_) >= SinNombre(PN, H.ClassName_)) then
          ANuestro := ANuestro + [ClaveDeHijo(PN, H)];
    if PS <> nil then
      for var H in PS.Children do
        if H.ObjName <> '' then
          ASuyo := ASuyo + [H.ObjName]
        else
        begin
          // los del ancestro van delante: De, cuantos son
          var De := SinNombre(PS, H.ClassName_) - SinNombre(PN, H.ClassName_);
          var N := 0;
          Vistos.TryGetValue(H.ClassName_.ToUpper, N);
          Inc(N);
          Vistos.AddOrSetValue(H.ClassName_.ToUpper, N);
          if (De >= 0) and (N > De) then
            ASuyo := ASuyo + [ClaveSinNombre(H.ClassName_, N - De)];
        end;
  finally
    Vistos.Free;
    DocS.Free;
    DocN.Free;
  end;
end;

// la posicion de AN en AL (un Name: sin mayusculas), -1 si no esta
function NombreEn(const AL: TArray<string>; const AN: string): Integer;
begin
  for var I := 0 to High(AL) do
    if SameText(AL[I], AN) then
      Exit(I);
  Result := -1;
end;

{ El juez guarda a ANombre donde lo pusimos. Con before=/after= (ARef, el
  hermano que nombra el agente): respecto a ARef queda del lado pedido, y
  respecto a CADA hermano que la orden le hace SALTAR (el que estaba delante y
  queda detras, o al reves) del mismo lado en lo escrito; los que no salta no
  son de esta llamada: un fichero que ya no estaba en el orden del IDE lo
  guardaria el IDE a su manera de todas formas (revisor 5 de la noche, M3:
  comparar con todos negaba en falso). Con index= (ARef vacio) la promesa es
  una POSICION: respecto a todos (revisor 6, A1: sin la referencia, un TLabel
  'detras de Button1' lo guardaba el IDE delante, y uno 'en la 2' en la 1).
  Que lo escrito los traiga a todos lo mira quien llama. }
function MismaPosicion(const ANombre, ARef: string; const AOriginal, ANuestro, ASuyo: TArray<string>): Boolean;
var
  PO, PN, PS: Integer;
begin
  PO := NombreEn(AOriginal, ANombre);
  PN := NombreEn(ANuestro, ANombre);
  PS := NombreEn(ASuyo, ANombre);
  if (PO < 0) or (PN < 0) or (PS < 0) then
    Exit(False);
  for var S in ANuestro do
    if not SameText(S, ANombre) then
    begin
      var Delante := NombreEn(ANuestro, S) < PN;
      if (ARef = '') or SameText(S, ARef) or (Delante <> (NombreEn(AOriginal, S) < PO)) then
      begin
        var SS := NombreEn(ASuyo, S);
        if (SS < 0) or ((SS < PS) <> Delante) then
          Exit(False);
      end;
    end;
  Result := True;
end;

{ ALineas sin el bloque [AIni, AIni + ALargo) y con ABloque en ADest (un
  indice de ALineas ANTES de quitarlo, fuera del bloque); ADest sale donde
  quedo. EL movimiento de un bloque de form: el de set parent= y el de
  before=/after=/index= (revisor 4 de la noche, B4: estaba dos veces) }
function ConBloqueMovido(const ALineas, ABloque: TArray<string>; AIni, ALargo: Integer;
  var ADest: Integer): TArray<string>;
begin
  Result := Copy(ALineas);
  Delete(Result, AIni, ALargo);
  if ADest > AIni + ALargo - 1 then
    Dec(ADest, ALargo);
  Insert(ABloque, Result, ADest);
end;

{ EL JUEZ DEL ORDEN de los hijos de ANomPadre (3.11 de la 1.18.0): como los
  escribiria el IDE si cargara ATexto (ComoLoEscribeElIde), en ASuyo, y como
  van en ATexto, en ANuestro. '' si contesto por TODOS; si no, por que no se
  sabe, con ANomObj -el que se coloca- en el mensaje: un ancestro sin leer,
  una clase que el ayudante no cargo (el padre o un hermano: su sustituto no
  sabe donde lo dejaria el IDE) o un hijo que no escribio. Estaba dentro de
  set before=/after=/index=, que niega con eso; insert y set parent= dejan el
  componente donde lo dejaria el IDE, o el ultimo si no se sabe. }
function JuezDelOrden(var F: TFormEnEdicion; const ATexto, ANomObj, ANomPadre: string;
  out ANuestro, ASuyo: TArray<string>; out AEscrito: string): string;
var
  Escrito, ErrorAyudante: string;
  Sustituidas, Avisos, SinLeer, Faltan: TArray<string>;
  Leidos: TArray<TLeidoPorElJuez>;
  Parada: TIgnorada;
  Doc: TStyleDoc;
  P: TStyleObj;
begin
  ANuestro := [];
  ASuyo := [];
  AEscrito := '';
  Result := ComoLoEscribeElIde(F.Dfm, ATexto, F.Doc.Encoding, Escrito, Sustituidas, Avisos, SinLeer,
    Leidos, ErrorAyudante, Parada);
  // lo que leyo, para mirarlo otra vez antes de escribir (B5 rev6)
  F.LeidoPorElJuez := F.LeidoPorElJuez + Leidos;
  if Result <> '' then
    Exit;
  // lo que escribio el IDE: de ahi sale tambien el TabOrder que le da
  AEscrito := Escrito;
  // un ancestro que el ayudante no encontro (sin .pas que lo diga o sin
  // fichero en la carpeta): leyo el form SIN el y su orden no es el del IDE,
  // aunque ningun hermano escrito falte (revisor 6 del 3.11, A2: un [n]
  // propio se colocaba sobre la lista sin los heredados)
  if Length(SinLeer) > 0 then
    Exit(MsgFmt(SR_DESIGNER_ORDEN_INCOMPLETO_FMT, [ANomObj, string.Join(', ', SinLeer),
      (if Length(Avisos) > 0 then string.Join('; ', Avisos) else '-')]));
  // un hermano - o el PADRE (revisor 5, M2) - que el ayudante no pudo cargar
  // lo escribe su sustituto, no su clase: donde lo dejaria el IDE no se sabe
  Doc := TStyleDoc.DeTexto(ATexto);
  try
    if (Doc.Root <> nil) and SameText(Doc.Root.ObjName, ANomPadre) then
      P := Doc.Root
    else
      P := ObjetoPorNombre(Doc, ANomPadre);
    if P <> nil then
      for var S in Sustituidas do
      begin
        if SameText(P.ClassName_, S) then
          Exit(MsgFmt(SR_DESIGNER_ORDEN_SIN_CLASE_FMT, [ANomObj, P.ClassName_, ANomPadre]));
        for var H in P.Children do
          if SameText(H.ClassName_, S) then
            Exit(MsgFmt(SR_DESIGNER_ORDEN_SIN_CLASE_FMT, [ANomObj, H.ClassName_, NombreDe(H)]));
      end;
  finally
    Doc.Free;
  end;
  HijosAlineados(ATexto, Escrito, ANomPadre, ANuestro, ASuyo);
  // lo que el juez no escribio no lo cargo (un componente que el lector
  // salto; un ancestro sin leer ya lo dijo PARTIAL= arriba): juzgaria un
  // form a medias (revisor 5 de la noche, A2 y B6)
  Faltan := [];
  for var N in ANuestro do
    if NombreEn(ASuyo, N) < 0 then
      Faltan := Faltan + [N];
  if (Length(ANuestro) = 0) or (Length(Faltan) > 0) then
    Exit(MsgFmt(SR_DESIGNER_ORDEN_INCOMPLETO_FMT, [ANomObj,
      (if Length(Faltan) > 0 then string.Join(', ', Faltan) else ANomPadre),
      (if Length(Avisos) > 0 then string.Join('; ', Avisos) else '-')]));
end;

{ ALineas -un form con el bloque de ANomObj, [AIni, AIni + ALargo), como
  ULTIMO hijo de ANomPadre- con ese bloque donde lo deja el IDE entre sus
  hermanos: detras del que el juez escribe justo delante de el (JuezDelOrden;
  la VCL escribe los graficos antes que las ventanas, una form heredada
  coloca por su [n]...). AIni sale donde quedo. Si el juez no contesta, el
  bloque se queda el ultimo, como antes, y ANota lo dice: insert y set
  parent= no se niegan por eso. Era siempre el ultimo, y el IDE lo movia al
  guardar (3.11, el juez para dos llamadores mas). }
function DondeLoDejaElIde(var F: TFormEnEdicion; const ALineas: TArray<string>;
  const ANomObj, ANomPadre: string; var AIni: Integer; ALargo: Integer; ASinTabOrder: Boolean;
  out ANota: string; out ATabOrder: Integer): TArray<string>;
var
  Nuestro, Suyo: TArray<string>;
  Doc: TStyleDoc;
  Escrito: string;
begin
  Result := ALineas;
  ANota := '';
  ATabOrder := -1;
  // con el motivo del juez: la nota afirmaba "el renderizador no cargo el form"
  // tambien cuando el juez nego otra cosa (DSGN-115...; revisor de version de
  // la 1.18.0)
  // con ASinTabOrder, sin su linea TabOrder: que el IDE le de la suya
  var Texto := F.Doc.TextoDe(ALineas);
  if ASinTabOrder then
    Texto := SinSuTabOrder(Texto, ANomObj);
  var Motivo := JuezDelOrden(F, Texto, ANomObj, ANomPadre, Nuestro, Suyo, Escrito);
  if Motivo <> '' then
  begin
    ANota := MsgFmt(SN_DESIGNER_ULTIMO_SIN_JUEZ_FMT, [ANomObj, ANomPadre, Motivo.Trim]);
    Exit;
  end;
  // el TabOrder que el IDE le da: el que escribe su escritor con el form
  // cargado como el disenador, ancestros incluidos (SiguienteTabOrder solo
  // cuenta los del texto: en un panel heredado salia 0; punto 7 de la 1.18.2)
  Doc := TStyleDoc.DeTexto(Escrito);
  try
    var OE := ObjetoPorNombre(Doc, ANomObj);
    if OE <> nil then
      ATabOrder := TabOrderDe(Doc, OE);
  finally
    Doc.Free;
  end;
  // DETRAS del que el IDE escribe justo delante (delante del de detras si es
  // el primero): en un fichero que ya no estaba en el orden del IDE, anclar
  // delante del siguiente lo cambiaba de sitio respecto a los graficos de
  // antes, su z-order (revisor del 17f4edd, M1: LabelB quedaba debajo de
  // LabelA). El ancla, entre los HIJOS del padre en la propuesta: por nombre
  // en todo el form podia caer dentro de un frame inline (revisor, B)
  Doc := TStyleDoc.DeTexto(F.Doc.TextoDe(ALineas));
  try
    var P: TStyleObj;
    if (Doc.Root <> nil) and SameText(Doc.Root.ObjName, ANomPadre) then
      P := Doc.Root
    else
      P := ObjetoPorNombre(Doc, ANomPadre);
    if P = nil then
    begin
      ANota := MsgFmt(SN_DESIGNER_ULTIMO_SIN_JUEZ_FMT, [ANomObj, ANomPadre,
        MsgFmt(SF_DESIGNER_PADRE_FUERA_DEL_TEXTO_FMT, [ANomPadre])]);
      Exit;
    end;
    // el orden del IDE con los hijos que ESTAN en el texto: los del ancestro que
    // la form no toca no se escriben en ella (el juez los ve, el fichero no), y
    // un ancla de esas daba DSGN-145 con el bloque ya en su sitio (revisor de
    // version de la 1.18.0)
    var SuyoP: TArray<string> := [];
    for var N in Suyo do
      for var H in P.Children do
        if SameText(ClaveDeHijo(P, H), N) then
        begin
          SuyoP := SuyoP + [N];
          Break;
        end;
    var PS := NombreEn(SuyoP, ANomObj);
    if (PS < 0) or (PS = High(SuyoP)) then
      Exit; // el IDE tambien lo deja el ultimo de los que estan: donde ya esta
    var NomAncla := SuyoP[(if PS > 0 then PS - 1 else 1)];
    var Ancla: TStyleObj := nil;
    for var H in P.Children do
      if SameText(ClaveDeHijo(P, H), NomAncla) then
        Ancla := H;
    var Dest := (if PS > 0 then Ancla.EndLine else Ancla.StartLine - 1);
    Result := ConBloqueMovido(ALineas, Copy(ALineas, AIni, ALargo), AIni, ALargo, Dest);
    AIni := Dest;
  finally
    Doc.Free;
  end;
end;

{ El form ABIERTO para juzgarlo y escribirlo despues: el juez del orden corre
  SIN el cerrojo (segundos), y lo que se escribe al final tiene que salir de
  lo mismo. Abrir y leer los bytes CON el cerrojo, y lo parseado sale de ESOS
  bytes: un escritor de fuera (el IDE) entre las dos lecturas haria juzgar
  unos y escribir otros (revisor 6 del 3.11, B1). Con ANecesitaPas, tambien
  los de la unidad. '' y F abierto (lo libera quien llama), o el fallo y F
  sin nada. Antes de escribir, CambioDesdeQueSeJuzgo. Estaba al principio de
  set before=/after=/index=; insert y set parent= preguntan ahora al juez. }
function AbreFormParaJuzgar(const APath: string; ANecesitaPas, ANecesitaTabla: Boolean;
  out F: TFormEnEdicion; out AAntes, AAntesPas: TArray<Byte>): string;
begin
  F := Default(TFormEnEdicion);
  AAntes := nil;
  AAntesPas := nil;
  EnterFileEdit;
  try
    try
      // la tabla, NO: se carga abajo, fuera del cerrojo (PonTabla)
      Result := AbreForm(APath, ANecesitaPas, False, F);
      if Result = '' then
      begin
        AAntes := LeeBytes(F.Dfm, [ltJaula]);
        var EncAntes: string;
        var LineasAntes := SplitToLines(TextoDeBytes(AAntes, True, EncAntes));
        var Iguales := (EncAntes = F.Doc.Encoding) and (Length(LineasAntes) = Length(F.Doc.Lines));
        for var I := 0 to High(LineasAntes) do
          if Iguales and (LineasAntes[I] <> F.Doc.Lines[I]) then
            Iguales := False;
        // la unidad, por el mismo decodificador que la leyo (PatchLoadText); y
        // el que cambio se NOMBRA, como en CambioDesdeQueSeJuzgo (nombraba
        // siempre el form; revisor de version de la 1.18.1, el gemelo de B3)
        var Cambiado := '';
        if not Iguales then
          Cambiado := F.DfmNombre
        else if ANecesitaPas then
        begin
          AAntesPas := LeeBytes(F.Pas, [ltJaula]);
          var EncPas: string;
          if (TextoDeBytes(AAntesPas, False, EncPas) <> F.PasTexto) or (EncPas <> F.PasEnc) then
            Cambiado := TPath.GetFileName(F.Pas);
        end;
        if Cambiado <> '' then
          Result := MsgFmt(SR_DESIGNER_ORDEN_CAMBIO_FMT, [Cambiado]);
      end;
    except
      FreeAndNil(F.Doc);
      raise;
    end;
  finally
    LeaveFileEdit;
  end;
  if (Result = '') and ANecesitaTabla then
  try
    Result := PonTabla(F);
  except
    FreeAndNil(F.Doc); // quien llama no lo libera si esto lanza
    raise;
  end;
  if Result <> '' then
    FreeAndNil(F.Doc); // nil si AbreForm fallo; abierto si los bytes no eran los leidos
end;

{ CON el cerrojo, justo antes de escribir: '' si el form -y la unidad, si se
  leyo, y lo que leyo el juez para cargarlo (READ=)- son los bytes que se
  juzgaron (AbreFormParaJuzgar, LeidoPorElJuez); si no, DSGN-144
  y no se escribe (revisor 5 de la noche, A3; borrado o renombrado mientras
  se juzgaba: revisor 6 del 3.11, B2). }
function CambioDesdeQueSeJuzgo(const F: TFormEnEdicion; const AAntes, AAntesPas: TArray<Byte>): string;
begin
  Result := MsgFmt(SR_DESIGNER_ORDEN_CAMBIO_FMT, [F.DfmNombre]);
  try
    if not BytesIguales(AAntes, LeeBytes(F.Dfm, [ltJaula])) then
      Exit;
    // el que cambio es la unidad: se nombra ELLA (nombraba siempre el form;
    // revisor de version de la 1.18.0, B3)
    Result := MsgFmt(SR_DESIGNER_ORDEN_CAMBIO_FMT, [TPath.GetFileName(F.Pas)]);
    if (AAntesPas <> nil) and not BytesIguales(AAntesPas, LeeBytes(F.Pas, [ltJaula])) then
      Exit;
    // y lo que leyo el juez para cargar el form: un ancestro, un frame, el
    // .pas de la cadena; el que cambio se nombra (B5 rev6 de la 1.18.2)
    var Leido := CambioEnLoLeido(F.LeidoPorElJuez);
    if Leido <> '' then
      Exit(MsgFmt(SR_DESIGNER_ORDEN_CAMBIO_FMT, [Leido]));
  except
    Exit;
  end;
  Result := '';
end;

{ set before= / after= / index=: el bloque del componente, entero, a su sitio
  nuevo entre sus hermanos, SOLO si el IDE lo guarda ahi - se le pregunta
  (ComoLoEscribeElIde: la propuesta cargada como la carga el designer y
  escrita por TWriter). No hay lista propia de que va delante de que: la
  VCL escribe los graficos antes que las ventanas, un TToolBar en el orden de
  sus botones, una form heredada coloca por su [n], FMX deja al final lo que
  no es TFmxObject... y eso lo dice el juez (norma 6; revisor 4 de la noche,
  M5: la primera version imitaba al juez con una lista y ya se desviaba en
  tres sitios). La sangria no cambia (mismo padre), el TabOrder tampoco. }
function OrdenaComponente(const APath, AComponente, ABefore, AAfter: string;
  AIndex: Integer): string;
var
  F: TFormEnEdicion;
  Obj, Ref, Padre: TStyleObj;
  Hermanos, Resto: TArray<TStyleObj>;
  Lineas: TArray<string>;
  Ini, Largo, Dest, Pos0, Nuevo: Integer;
  NomObj, NomPadre, NomRef, Donde, Texto: string;
  Original, Nuestro, Suyo: TArray<string>;
  Antes, AntesPas: TArray<Byte>;
  Ret: TJSONObject;
begin
  // los bytes que se juzgan, leidos con el cerrojo (el juez corre sin el)
  Result := AbreFormParaJuzgar(APath, False, False, F, Antes, AntesPas);
  if Result <> '' then
    Exit;
  try
    Result := BuscaComponente(F, AComponente, Obj);
    if Result <> '' then
      Exit;
    Result := QueNoSeToca(F, Obj);
    if Result <> '' then
      Exit;
    Padre := Obj.Parent;
    NomObj := NombreDe(Obj);
    NomPadre := NombreDe(Padre);
    // el juez pregunta por los hijos de un padre por su NOMBRE: uno sin
    // nombre se buscaba por su clase y salia DSGN-143 "without TPanel" (B3 rev6)
    if Padre.ObjName = '' then
      Exit(MsgFmt(SR_DESIGNER_ORDEN_PADRE_SIN_NOMBRE_FMT, [NomObj, Padre.ClassName_, Padre.StartLine]));
    Hermanos := [];
    Original := [];
    for var H in Padre.Children do
    begin
      Hermanos := Hermanos + [H];
      Original := Original + [ClaveDeHijo(Padre, H)];
    end;
    Pos0 := -1;
    Resto := [];
    for var I := 0 to High(Hermanos) do
      if Hermanos[I] = Obj then
        Pos0 := I
      else
        Resto := Resto + [Hermanos[I]];
    // la posicion nueva, contada entre los DEMAS hermanos
    NomRef := '';
    if (ABefore.Trim <> '') or (AAfter.Trim <> '') then
    begin
      // '(unnamed X #n)' es la clave de un hijo SIN Name en las listas del
      // juez (DSGN-136/143), no un Name: before/after no pueden senalarlo, y
      // DSGN-078 lo mandaba a la lista de nombres (D5 de los revisores de cierre)
      if EsClaveSinNombre(ABefore.Trim + AAfter.Trim) then
        Exit(MsgFmt(SR_DESIGNER_ORDEN_REF_SIN_NOMBRE_FMT, [(ABefore + AAfter).Trim, NomObj]));
      Result := BuscaComponente(F, ABefore.Trim + AAfter.Trim, Ref);
      if Result <> '' then
        Exit;
      NomRef := NombreDe(Ref);
      if Ref = Obj then
        Exit(MsgFmt(SR_DESIGNER_ORDEN_SI_MISMO_FMT, [NomObj]));
      if Ref.Parent <> Padre then
        Exit(MsgFmt(SR_DESIGNER_ORDEN_NO_HERMANO_FMT, [NomObj, NomPadre, NomRef,
          (if Ref.Parent = nil then MsgText(SF_DESIGNER_ES_EL_FORM) else NombreDe(Ref.Parent))]));
      Nuevo := 0;
      while Resto[Nuevo] <> Ref do
        Inc(Nuevo);
      if AAfter.Trim <> '' then
      begin
        Inc(Nuevo);
        Donde := MsgFmt(SF_DESIGNER_ORDEN_DETRAS_DE_FMT, [NomRef]);
      end
      else
        Donde := MsgFmt(SF_DESIGNER_ORDEN_DELANTE_DE_FMT, [NomRef]);
    end
    else
    begin
      if (AIndex < 1) or (AIndex > Length(Hermanos)) then
        Exit(MsgFmt(SR_DESIGNER_ORDEN_INDICE_FMT, [AIndex, NomObj, Length(Hermanos), NomPadre,
          Length(Hermanos)]));
      Nuevo := AIndex - 1;
      Donde := MsgFmt(SF_DESIGNER_ORDEN_EN_LA_POSICION_FMT, [AIndex]);
    end;
    if Nuevo = Pos0 then
      Exit(MsgFmt(SN_DESIGNER_ORDEN_YA_ESTA_FMT, [NomObj, Pos0 + 1, Length(Hermanos), NomPadre]));
    // el bloque, delante del que ocupara su sitio o detras del ultimo hermano
    Ini := Obj.StartLine - 1;
    Largo := Obj.EndLine - Obj.StartLine + 1;
    if Nuevo < Length(Resto) then
      Dest := Resto[Nuevo].StartLine - 1
    else
      Dest := Resto[High(Resto)].EndLine;
    Lineas := ConBloqueMovido(F.Doc.Lines, Copy(F.Doc.Lines, Ini, Largo), Ini, Largo, Dest);
    Texto := F.Doc.TextoDe(Lineas);
    // EL JUEZ: el IDE, cargando la propuesta, la guardaria con el ahi?
    var Escrito: string;
    Result := JuezDelOrden(F, Texto, NomObj, NomPadre, Nuestro, Suyo, Escrito);
    if Result <> '' then
      Exit;
    if not MismaPosicion(NomObj, NomRef, Original, Nuestro, Suyo) then
      Exit(MsgFmt(SR_DESIGNER_ORDEN_EL_IDE_FMT, [NomObj, Donde, NomPadre, string.Join(', ', Suyo)]));
    // con el cerrojo, solo releer y escribir: el fichero tiene que ser el que
    // se juzgo (revisor 5 de la noche, A3)
    EnterFileEdit;
    try
      Result := CambioDesdeQueSeJuzgo(F, Antes, AntesPas);
      if Result <> '' then
        Exit;
      F.Doc.SetLines(Lineas);
      Result := F.Doc.Guarda; // solo si el parser del IDE lee el resultado (9.B)
    finally
      LeaveFileEdit;
    end;
    if Result <> '' then
      Exit;
    Ret := TJSONObject.Create;
    try
      Ret.AddPair('ordered', NomObj);
      if ABefore.Trim <> '' then
        Ret.AddPair('before', NomRef)
      else if AAfter.Trim <> '' then
        Ret.AddPair('after', NomRef);
      Ret.AddPair('parent', NomPadre);
      Ret.AddPair('index', TJSONNumber.Create(Nuevo + 1));
      Ret.AddPair('of', TJSONNumber.Create(Length(Hermanos)));
      Ret.AddPair('file', F.DfmNombre);
      Ret.AddPair('line', TJSONNumber.Create(Dest + 1));
      Ret.AddPair('endLine', TJSONNumber.Create(Dest + Largo));
      Ret.AddPair('note', MsgText(SN_DESIGNER_ORDEN_NOTA));
      PonLista(Ret, 'lint', AvisosDespues(F, F.Doc.TextoDe(F.Doc.Lines)));
      Result := Ret.ToJSON;
    finally
      Ret.Free;
    end;
  finally
    F.Doc.Free;
  end;
end;

function CambiaPropiedad(const APath, AComponente, AProp, AValor, AParent: string;
  const AProps: string; const ABefore: string; const AAfter: string;
  AIndex: Integer): string;
begin
  if AComponente.Trim = '' then
    Exit(MsgText(SR_DESIGNER_NEED_COMPONENT));
  // el orden entre hermanos (3.11 de la 1.18.0): UNO de los tres, solo
  if (ABefore.Trim <> '') or (AAfter.Trim <> '') or (AIndex >= 0) then
  begin
    if (Ord(ABefore.Trim <> '') + Ord(AAfter.Trim <> '') + Ord(AIndex >= 0) > 1) or
       (AProp.Trim <> '') or (AValor.Trim <> '') or (AParent.Trim <> '') or (AProps.Trim <> '') then
      Exit(MsgText(SR_DESIGNER_ORDEN_SOLO));
    Exit(OrdenaComponente(APath, AComponente, ABefore, AAfter, AIndex));
  end;
  // varias de una vez (props, 3.10 de la 1.18.0): sin prop/value ni parent
  if AProps.Trim <> '' then
  begin
    if (AProp.Trim <> '') or (AValor.Trim <> '') or (AParent.Trim <> '') then
      Exit(MsgText(SR_DESIGNER_PROPS_SOLO));
    Exit(PoneValores(APath, AComponente, AProps));
  end;
  if AParent.Trim <> '' then
  begin
    if (AProp.Trim <> '') or (AValor.Trim <> '') then
      Exit(MsgText(SR_DESIGNER_SET_PARENT_SOLO));
    Exit(MueveComponente(APath, AComponente, AParent));
  end;
  if AProp.Trim = '' then
    Exit(MsgText(SR_DESIGNER_NEED_PROP));
  if SameText(AProp.Trim, 'Name') then
  begin
    if AValor.Trim = '' then
      Exit(MsgText(SR_DESIGNER_SET_SIN_VALOR));
    Exit(RenombraComponente(APath, AComponente, AValor));
  end;
  Result := PoneValor(APath, AComponente, AProp, AValor);
end;

{ ---- delete ---- }

function BorraComponente(const APath, AComponente: string): string;
var
  F: TFormEnEdicion;
  Obj: TStyleObj;
  Imp: TImpacto;
  Dfm, Pas: string;
  Lista: TArray<string>;
  Quedan: TJSONArray;
  Ret: TJSONObject;
begin
  if AComponente.Trim = '' then
    Exit(MsgText(SR_DESIGNER_NEED_COMPONENT));
  // la tabla tambien: que lineas del form son referencias (JuezDeReferencias)
  Result := AbreForm(APath, True, True, F);
  if Result <> '' then
    Exit;
  try
    Result := BuscaComponente(F, AComponente, Obj);
    if Result <> '' then
      Exit;
    Result := QueNoSeToca(F, Obj);
    if Result <> '' then
      Exit;
    Result := PlanDeBorrado(F.Doc, Obj, F.PasTexto, F.PasNombre, Imp, Dfm, Pas, JuezDeReferencias(F), F.Tabla);
    if Result <> '' then
      Exit;
    Result := EscribeFormYUnidad(F, Dfm, Pas, Pas <> F.PasTexto);
    // los usos que quedan, con las lineas de la unidad que QUEDA: el campo
    // y los manejadores que se fueron estaban por encima (3.8, Hermes)
    if (Result = '') and (Imp.Nota = '') and (F.PasTexto <> '') then
      Imp.Usos := UsosEnCodigo(Pas, F.PasNombre, Imp.Nombres, nil);
    if Result <> '' then
      Exit;
    Ret := TJSONObject.Create;
    try
      Ret.AddPair('deleted', NombreDe(Obj));
      Ret.AddPair('class', Obj.ClassName_);
      Ret.AddPair('file', F.DfmNombre);
      Ret.AddPair('line', TJSONNumber.Create(Obj.StartLine));
      Ret.AddPair('endLine', TJSONNumber.Create(Obj.EndLine));
      PonLista(Ret, 'alsoDeleted', Copy(Imp.Nombres, 1, MaxInt));
      Lista := [];
      for var I in Imp.Referencias do
        Lista := Lista + [Donde(F.DfmNombre, I + 1) + ': ' + Trim(F.Doc.Lines[I])];
      PonLista(Ret, 'referencesRemoved', Lista);
      Lista := [];
      for var C in Imp.Campos do
        Lista := Lista + [C.Nombre + ' (' + Donde(F.PasNombre, C.Ini + 1) + ')'];
      PonLista(Ret, 'fieldsRemoved', Lista);
      Lista := [];
      for var Mt in Imp.Metodos do
        if Mt.SeBorra then
          Lista := Lista + [Mt.Nombre + ' (' + Donde(F.PasNombre, Mt.Linea) + ')'];
      PonLista(Ret, 'handlersRemoved', Lista);
      Quedan := nil;
      for var Mt in Imp.Metodos do
        if not Mt.SeBorra then
        begin
          if Quedan = nil then
          begin
            Quedan := TJSONArray.Create;
            Ret.AddPair('handlersKept', Quedan);
          end;
          var Q := TJSONObject.Create;
          Q.AddPair('method', Mt.Nombre);
          Q.AddPair('at', Donde(F.PasNombre, Mt.Linea));
          Q.AddPair('why', IfThen(Mt.Compartido <> '', Mt.Compartido, MsgText(SF_DESIGNER_COMPARTE_LINEAS)));
          Quedan.AddElement(Q);
        end;
      PonLista(Ret, 'usesInCode', Imp.Usos);
      PonLista(Ret, 'lint', AvisosDespues(F, Dfm));
      Ret.AddPair('note', MsgText(SN_DESIGNER_DELETE_NOTE));
      Result := Ret.ToJSON;
    finally
      Ret.Free;
    end;
  finally
    F.Doc.Free;
  end;
end;

{ EL CARGADOR de verdad (norma 6) para lo que la tabla no juzga: una propiedad
  que la clase guarda POR CODIGO (DefineProperties) se acepta sin hoja de tipo,
  y set la escribia sin saber si se leia (H2 de Hermes, 1.18.2, medido en
  produccion: FontColor = -65536 en un TEdit FMX -> "ok", y el form ya no
  cargaba: EReadError "Invalid property value"). Solo si alguna de AInfos va
  SinJuez: el form tal como quedaria, cargado como lo carga el designer
  (ComoLoEscribeElIde). '' si carga; la negativa si lo que no carga es UNA de
  esas propiedades de ANombre (DSGN-149, por las partes del error que da el
  ayudante en su idioma), o si falla por otra cosa y el form como se leyo SI
  carga (DSGN-158). Si tampoco cargaba antes, o no se pudo preguntar, el
  valor queda sin juzgar: '' y ANota lo dice (DSGN-159; un form que ya no
  cargaba por otra cosa no niega este set). }
function CargaLoPuesto(var F: TFormEnEdicion; const ANombre: string;
  const AInfos: array of TValorPuesto; out ANota: string): string;
var
  Escrito, ErrorAyudante, Valores: string;
  Sustituidas, Avisos, SinLeer: TArray<string>;
  Leidos: TArray<TLeidoPorElJuez>;
  Lectura: TIgnorada;
begin
  Result := '';
  ANota := '';
  Valores := '';
  for var I := 0 to High(AInfos) do
    if AInfos[I].SinJuez then
      Valores := Valores + (if Valores <> '' then ', ' else '') +
        MsgFmt(SF_DESIGNER_VALOR_PUESTO_FMT, [ANombre, AInfos[I].Prop, AInfos[I].Valor]);
  if Valores = '' then
    Exit;
  var Juicio := ComoLoEscribeElIde(F.Dfm, F.Doc.TextoDe(F.Doc.Lines), F.Doc.Encoding, Escrito, Sustituidas,
    Avisos, SinLeer, Leidos, ErrorAyudante, Lectura);
  // lo que leyo, para mirarlo otra vez antes de escribir (B5 rev6)
  F.LeidoPorElJuez := F.LeidoPorElJuez + Leidos;
  if Juicio = '' then
    Exit;
  // el lector NOMBRA uno de estos valores (las partes de su error, que da el
  // ayudante en su idioma): es el
  if SameText(Lectura.Componente, ANombre) then
    for var I := 0 to High(AInfos) do
      if AInfos[I].SinJuez and SameText(AInfos[I].Prop, Lectura.Propiedad) then
        Exit(MsgFmt(SR_DESIGNER_SET_NO_CARGA_FMT, [ANombre, AInfos[I].Prop, AInfos[I].Valor,
          Lectura.Motivo]));
  // el ayudante no dijo nada (no se le dio el form - un literal que nombra un
  // fichero fuera de la jaula - o no contesto): no se juzgo, y se dice; se
  // escribia sin juzgar y sin decirlo
  if ErrorAyudante = '' then
  begin
    ANota := MsgFmt(SN_DESIGNER_SET_SIN_JUZGAR_FMT, [Valores, MsgCuerpo(Juicio)]);
    Exit;
  end;
  // fallo por otra cosa - otro componente, un error que no es del lector -:
  // el MISMO juez con el form como se leyo, como Guarda con el parser. Si ese
  // carga, lo rompe este cambio; si tampoco, ya no cargaba (y no niega)
  var Motivo := ErrorAyudante;
  var Antes := ComoLoEscribeElIde(F.Dfm, F.Doc.TextoDe(F.Doc.Leidas), F.Doc.Encoding, Escrito, Sustituidas,
    Avisos, SinLeer, Leidos, ErrorAyudante, Lectura);
  F.LeidoPorElJuez := F.LeidoPorElJuez + Leidos;
  if Antes = '' then
    Exit(MsgFmt(SR_DESIGNER_SET_ROMPE_CARGA_FMT, [Valores, Motivo]));
  ANota := MsgFmt(SN_DESIGNER_SET_SIN_JUZGAR_FMT, [Valores, MsgFmt(SF_DESIGNER_LECTOR_YA_NO_CARGABA_FMT,
    [IfThen(ErrorAyudante <> '', ErrorAyudante, MsgCuerpo(Antes))])]);
end;

end.
