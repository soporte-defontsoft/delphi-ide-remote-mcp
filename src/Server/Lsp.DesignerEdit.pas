unit Lsp.DesignerEdit;

{ delphi_designer insert / set / delete: editar un form (.dfm/.fmx) y su
  unidad como lo haria el IDE, y solo lo BASICO (David, 4-oct-2026: "no
  queremos construir un IDE completo, solo ayudar a los agentes"). El
  criterio de lo basico: que el componente SE VEA al abrir el form en el IDE
  y al ejecutar. Y la idea de fondo, suya: una puerta nuestra donde lo que se
  pide se controla contra la realidad del proyecto y del Delphi instalado
  ANTES de escribir.

    insert  un control VISUAL nuevo, ultimo hijo de su padre (el form por
            defecto), en 10,10, con su texto (su Name) si la clase lo tiene,
            su TabOrder, su campo publicado en la clase del form y su unidad
            en el uses. Nada del constructor: el IDE y la app lo crean con el
            suyo, y un Width/Height ausente queda con su tamano.
    set     UNA propiedad, juzgada contra las tablas (JuzgaPropiedad, el juez
            del lint) ANTES de escribir; parent= mueve el bloque entero a otro
            contenedor; Name renombra (el form, sus referencias y el campo).
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
  Lsp.Styles;

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
  referencias (Align = Client en FMX no nombra a un componente Client). }
function AnalizaImpacto(ADoc: TStyleDoc; AObj: TStyleObj; ASoloEl: Boolean;
  const APasTexto, APasNombre: string; AJuez: TJuezDeReferencia = nil): TImpacto;

{ El delete sobre los TEXTOS: '' y el form y la unidad como quedan, o la
  negativa (un metodo propio con cuerpo). AImp, el impacto, con SeBorra
  puesto en los metodos que se van. }
function PlanDeBorrado(ADoc: TStyleDoc; AObj: TStyleObj;
  const APasTexto, APasNombre: string; out AImp: TImpacto;
  out ADfm, APas: string; AJuez: TJuezDeReferencia = nil): string;

{ El renombrado sobre los TEXTOS (ANuevo ya validado): la cabecera del objeto,
  las lineas del form que lo nombran (AImp.Referencias) y su campo; y su
  texto si era su nombre: ATextos, las propiedades donde su clase lo pone al
  nombrarse (PropiedadesDeTexto; [] = no lo hace). }
function PlanDeRenombre(ADoc: TStyleDoc; AObj: TStyleObj;
  const ANuevo, APasTexto, APasNombre: string; const ATextos: TArray<string>;
  out AImp: TImpacto; out ADfm, APas: string; AJuez: TJuezDeReferencia = nil): string;

{ Los comandos. Cada uno devuelve el JSON de lo hecho, o la negativa sin
  haber escrito nada. La jaula de escritura la piden ellos; el cerrojo de
  escritura (EnterFileEdit) lo coge la tool. }
function InsertaComponente(const APath, AClase, AComponente, AParent: string): string;
function CambiaPropiedad(const APath, AComponente, AProp, AValor, AParent: string): string;
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
  Lsp.Pascal,          // EL identificador, CodigoPascal, LineaDePosicion
  Lsp.PascalDecl,      // EL lector de clases: campos, rutinas y cuerpos
  Lsp.DesignerBin,     // el literal de cadena, el flotante, las lineas del form
  Lsp.DesignerForma,   // la linea de objeto y su compositor
  Lsp.DesignerMeta,    // la tabla del framework y su juez (JuzgaPropiedad)
  Lsp.DesignerMetaGen, // la unidad de una clase (UnidadDeIdDeTipo)
  Lsp.DesignerBinding, // EL lector de la linea de evento; los avisos del binding
  Lsp.ProjectUnits,    // UsesConUnidades: el uses de la unidad
  Lsp.TodoONada;       // FicherosTodoONada

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
  end;

{ ---- el form ---- }

procedure RecogeNombres(O: TStyleObj; L: TStringList);
begin
  if O.ObjName <> '' then
    L.Add(O.ObjName);
  // lo de dentro de un frame en linea es del frame: sus nombres no son del
  // form, que puede tener su propio Edit1 (el delete del frame se llevaba el
  // campo y las referencias del Edit1 del form: revision de la 1.17.0)
  if O.Clave = 'inline' then
    Exit;
  for var K in O.Children do
    RecogeNombres(K, L);
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
  if (AForm[AI].Clase <> clfPropiedad) or EventoDeLinea(ADoc.Lines[AI], Ev, Met) then
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
  const APasTexto, APasNombre: string; AJuez: TJuezDeReferencia = nil): TImpacto;
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
    for I := 0 to High(ADoc.Lines) do
      if (Form[I].Clase = clfPropiedad) and EventoDeLinea(ADoc.Lines[I], Ev, Met) then
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
  out ADfm, APas: string; AJuez: TJuezDeReferencia = nil): string;
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
  AImp := AnalizaImpacto(ADoc, AObj, False, APasTexto, APasNombre, AJuez);
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
  out AImp: TImpacto; out ADfm, APas: string; AJuez: TJuezDeReferencia = nil): string;
var
  Lineas, PasLineas, PasSaltos, Nuevas: TArray<string>;
  I, Delta: Integer;
  Nom, Clave, NomObj, ClaseObj, Resto, V, Txt: string;
  Uno: TStringList;
  M: TMatch;
  Form: TArray<TLineaForm>;
begin
  Result := '';
  AImp := AnalizaImpacto(ADoc, AObj, True, APasTexto, APasNombre, AJuez);
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

function AbreFormNucleo(const APath: string; ANecesitaPas, ANecesitaTabla: Boolean;
  var F: TFormEnEdicion): string;
var
  Falta: TFaltaTabla;
  Unidad: TUnidadPas;
begin
  Result := WriteTargetDenied(APath);
  if Result <> '' then
    Exit;
  if not TFile.Exists(APath) then
    Exit(NoEsFichero(APath, MsgFmt(SR_NO_EXISTE_FMT, [APath])));
  if not MatchText(TPath.GetExtension(APath), ['.dfm', '.fmx']) then
    Exit(MsgText(SR_DESIGNER_NOT_FORM));
  F.Dfm := APath;
  F.DfmNombre := TPath.GetFileName(APath);
  F.EsFmx := EsDesignerFmx(APath);
  F.Marco := IfThen(F.EsFmx, 'FMX', 'VCL');
  if IsBinaryDesignerFile(APath) then
    Exit(MsgFmt(SR_DESIGNER_EDIT_BINARIO_FMT, [F.DfmNombre]));
  try
    F.Doc := TStyleDoc.Create(APath);
  except
    on E: Exception do
      Exit(MsgEnvuelve(SR_DESIGNER_ILEGIBLE_FMT, E.Message, [APath, E.Message]));
  end;
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
  begin
    F.Tabla := MetaTable(F.EsFmx, Falta);
    if F.Tabla = nil then
      Exit(Falta.Negativa);
  end;
end;

function AbreForm(const APath: string; ANecesitaPas, ANecesitaTabla: Boolean;
  out F: TFormEnEdicion): string;
begin
  F := Default(TFormEnEdicion);
  Result := AbreFormNucleo(APath, ANecesitaPas, ANecesitaTabla, F);
  if Result <> '' then
    FreeAndNil(F.Doc);
end;

function NombresDelForm(ADoc: TStyleDoc): string;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    RecogeNombres(ADoc.Root, L);
    while L.Count > MAX_NOMBRES do
      L.Delete(L.Count - 1);
    Result := string.Join(', ', L.ToStringArray);
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
  if AObj.Clave = 'inherited' then
    Exit(MsgFmt(SR_DESIGNER_HEREDADO_FMT, [NombreDe(AObj)]));
  var Fr := InlineQueLoContiene(AObj);
  if Fr <> nil then
    Exit(MsgFmt(SR_DESIGNER_DENTRO_DE_INLINE_FMT, [NombreDe(AObj), NombreDe(Fr)]));
end;

function ClaseDeJuez(const F: TFormEnEdicion; AObj: TStyleObj; out AClsId: string): string; forward;

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

// '' si ANombre esta libre en el form y en su clase; si no, quien lo tiene.
// AYo: el componente que se renombra (su propio nombre y su campo no cuentan)
function NombreOcupado(ADoc: TStyleDoc; AClase: TTipoPas; const ANombre: string;
  AYo: TStyleObj): string;
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
end;

// el nombre que pone el IDE: la clase sin su T y el primer numero libre
function NombreLibre(ADoc: TStyleDoc; AClase: TTipoPas; const AClaseComp: string): string;
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
  until NombreOcupado(ADoc, AClase, Result, nil) = '';
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
  Motivo := NombreOcupado(F.Doc, AClase, ALimpio, AYo);
  if Motivo <> '' then
    Exit(MsgFmt(SR_DESIGNER_NOMBRE_OCUPADO_FMT, [ALimpio, Motivo]));
  Result := NombreQueElFicheroNoLee(ALimpio, F.Dfm, F.Doc.Encoding, F.Pas, F.PasEnc);
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

// el TabOrder que sigue entre los hijos de APadre
function SiguienteTabOrder(ADoc: TStyleDoc; APadre: TStyleObj): Integer;
var
  Ini, Fin, N: Integer;
  P, V: string;
begin
  Result := 0;
  for var K in APadre.Children do
    if ADoc.PropLines(K, 'TabOrder', Ini, Fin) and LineaDePropiedad(ADoc.Lines[Ini], P, V) and
       TryStrToInt(V, N) then
      Result := Max(Result, N + 1);
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
var
  Notas, Lineas: TArray<string>;
  Falta: TFaltaTabla;
begin
  Lineas := LineasDelTexto(ATexto);
  Result := DesignerMetaLint(F.EsFmx, Lineas, Notas, Falta, 0) +
    DesignerBindingWarnings(F.Dfm, Lineas);
  if Falta.Razon <> '' then
    Result := Result + [MsgFmt(SN_DESIGNER_LINT_SIN_TABLA_FMT, [Falta.Razon])];
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

{ ---- insert ---- }

function InsertaComponente(const APath, AClase, AComponente, AParent: string): string;
var
  F: TFormEnEdicion;
  Padre: TStyleObj;
  ClsId, Clase, Unidad, Nombre, Ind, Texto, PasNuevo, Sangria, UsesAnadida, UsesNota: string;
  Bloque, DfmLineas, PasLineas, PasSaltos, Faltan, YaEstan, EnOtra: TArray<string>;
  UPas: TUnidadPas;
  Cls: TTipoPas;
  Detras, Ini, LineaCampo: Integer;
  Creada: Boolean;
  Ret: TJSONObject;
begin
  if AClase.Trim = '' then
    Exit(MsgText(SR_DESIGNER_NEED_CLASS));
  Result := AbreForm(APath, True, True, F);
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
        Nombre := NombreLibre(F.Doc, Cls, Clase);
      PasLineas := SplitToLinesConSalto(F.PasTexto, PasSaltos);
      SitioDelCampo(Cls, PasLineas, Detras, Sangria);
      Insert(Sangria + Nombre + ': ' + Clase + ';', PasLineas, Detras + 1);
      Insert(SaltoDominante(F.PasTexto), PasSaltos, Detras + 1);
      PasNuevo := UneConSusSaltos(PasLineas, PasSaltos);
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
    // el bloque, con lo minimo que escribe el IDE, ultimo hijo de su padre
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
    if Publica(F.Tabla, ClsId, 'TabOrder') then
      Bloque := Bloque + LineasDePropiedad(Ind + '  ', 'TabOrder', [IntToStr(SiguienteTabOrder(F.Doc, Padre))]);
    if F.EsFmx and (Texto <> '') then
      Bloque := Bloque + LineasDePropiedad(Ind + '  ', Texto, TrozosDeLiteral(Nombre));
    Bloque := Bloque + [Ind + 'end'];
    DfmLineas := Copy(F.Doc.Lines);
    Ini := Padre.EndLine - 1;
    Insert(Bloque, DfmLineas, Ini);
    Result := EscribeFormYUnidad(F, F.Doc.TextoDe(DfmLineas), PasNuevo, True);
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
      Ret.AddPair('parent', NombreDe(Padre));
      Ret.AddPair('file', F.DfmNombre);
      Ret.AddPair('line', TJSONNumber.Create(Ini + 1));
      Ret.AddPair('endLine', TJSONNumber.Create(Ini + Length(Bloque)));
      PonLista(Ret, 'block', BloqueNumerado(DfmLineas, Ini, Ini + High(Bloque)));
      Ret.AddPair('field', Nombre + ': ' + Clase);
      Ret.AddPair('fieldAt', Donde(F.PasNombre, LineaCampo));
      if UsesAnadida <> '' then
        Ret.AddPair('usesAdded', UsesAnadida);
      if UsesNota <> '' then
        Ret.AddPair('usesNote', UsesNota);
      PonLista(Ret, 'lint', AvisosDespues(F, F.Doc.TextoDe(DfmLineas)));
      Ret.AddPair('note', MsgText(SN_DESIGNER_INSERT_NOTE));
      Result := Ret.ToJSON;
    finally
      Ret.Free;
    end;
  finally
    F.Doc.Free;
  end;
end;

{ ---- set ---- }

{ Los ancestros que declara la unidad de ADir (no AYa) donde esta AClase,
  anadidos a AMapa: la base de un form que es del proyecto (TForm1 =
  class(TBaseForm), con TBaseForm en uBase.pas). False si ninguna la
  declara. Solo la carpeta, y cada fichero por la puerta de leer. }
function AnotaAncestrosDeCarpeta(const ADir, AYa, AClase: string;
  AMapa: TDictionary<string, string>): Boolean;
const
  MAX_UNIDADES = 300;
var
  N: Integer;
  Enc, Texto: string;
  U: TUnidadPas;
begin
  Result := False;
  if (ADir = '') or (AClase = '') or not TDirectory.Exists(ADir) then
    Exit;
  N := 0;
  for var P in TDirectory.GetFiles(ADir, '*.pas') do
  begin
    Inc(N);
    if N > MAX_UNIDADES then
      Break;
    if SameText(P, AYa) or (ReadPathDenied(P) <> '') then
      Continue;
    try
      Texto := PatchLoadText(P, Enc);
    except
      Continue;
    end;
    if not TRegEx.IsMatch(CodigoPascal(Texto), PATRON_NO_IDENT_ANTES + TRegEx.Escape(AClase) +
       '\s*=\s*class\b', [roIgnoreCase]) then
      Continue;
    U := LeeFuentePascal(Texto);
    try
      AnotaAncestros(U, AMapa);
    finally
      U.Free;
    end;
    if AMapa.ContainsKey(ClaveDeIdentificador(AClase)) then
      Exit(True);
  end;
end;

{ La clase contra la que se juzga una propiedad: la del componente; la de un
  frame en linea, si no esta en la tabla (es del proyecto), TFrame - medido
  el 7-oct-2026: su tamano en el form se negaba con DSGN-082; la del form,
  por la primera de su cadena que la tabla conoce (TForm, TFrame...): la suya
  propia no, que un TForm1 de una demo se llama igual. }
function ClaseDeJuez(const F: TFormEnEdicion; AObj: TStyleObj; out AClsId: string): string;
var
  U: TUnidadPas;
  Mapa: TDictionary<string, string>;
  Cadena: TArray<string>;
  Sale: Boolean;
begin
  Result := '';
  AClsId := '';
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
  if F.HayPas then
  begin
    U := LeeFuentePascal(F.PasTexto);
    Mapa := TDictionary<string, string>.Create;
    try
      AnotaAncestros(U, Mapa);
      for var Salto := 0 to 4 do
      begin
        Cadena := CadenaDeAncestros(Mapa, AObj.ClassName_, Sale);
        for var K := 1 to High(Cadena) do
          if F.Tabla.ClaseDeNombre(UltimoTrozo(Cadena[K]), AClsId) then
            Exit;
        // la cadena sale de la unidad por una base del proyecto: su unidad,
        // en la carpeta del form (se negaba con DSGN-082: revision de la
        // 1.17.0)
        if not Sale or (Length(Cadena) = 0) or not AnotaAncestrosDeCarpeta(TPath.GetDirectoryName(F.Pas),
           F.Pas, UltimoTrozo(Cadena[High(Cadena)]), Mapa) then
          Break;
      end;
    finally
      Mapa.Free;
      U.Free;
    end;
  end;
  Result := MsgFmt(SR_DESIGNER_CLASE_SIN_TABLA_FMT, [NombreDe(AObj), AObj.ClassName_,
    F.Marco, MsgText(SF_DESIGNER_QUE_PROPIEDADES), MsgText(SF_DESIGNER_VIA_LINEA)]);
end;

// la propiedad casi bien escrita: la mas parecida del primer trozo, si es una
function ParecidaA(M: TMetaTable; const AClsId, AProp: string): string;
var
  Segs, Nombres: TArray<string>;
  Cand: string;
begin
  Result := '';
  Segs := AProp.Split(['.']);
  if (Length(Segs) = 0) or Publica(M, AClsId, Segs[0]) then
    Exit;
  Nombres := [];
  for var Par in M.Props do
    if Par.Key.StartsWith(ClaveProp(AClsId, '')) and (Par.Value.Kind <> 'm') then
      Nombres := Nombres + [Par.Value.Name];
  Cand := ElMasParecido(Segs[0], Nombres, Max(2, Length(Segs[0]) div 3));
  if Cand = '' then
    Exit;
  Segs[0] := Cand;
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
    while L.Count > MAX_NOMBRES do
      L.Delete(L.Count - 1);
    Result := MsgFmt(SF_DESIGNER_CABEN_FMT, [string.Join(', ', L.ToStringArray)]);
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
    // una referencia: revision de la 1.17.0)
    if F.Tabla.Classes.ContainsKey(ClaveDeIdentificador(AHoja.TypeId)) and
       not F.Tabla.Desciende(AHoja.TypeId, ID_COMPONENTE) then
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
        // un componente ('c'), o un tipo 'o' sin base conocida: una interfaz
        // que guarda un componente (el Reader de un TFDBatchMove, el
        // Provider de REST) se escribe como su nombre y TReader la resuelve
        // igual (segunda revision de la 1.17.0: se quedaba al renombrar)
        Result := (Hoja.Kind = 'c') or
          ((Hoja.Kind = 'o') and not Fm.Tabla.Bases.ContainsKey(ClaveDeIdentificador(Hoja.TypeId)));
    end;
end;

function PoneValor(const APath, AComponente, AProp, AValor: string): string;
var
  F: TFormEnEdicion;
  Obj: TStyleObj;
  ClsId, Prop, V, Juicio, Antes, Nombre, Texto, Aviso: string;
  Trozos: TArray<string>;
  Hoja: TPropRec;
  HayHoja, Comillas, WasThere, Quita: Boolean;
  Ini, Fin, LineaN: Integer;
  Ret: TJSONObject;
begin
  Prop := AProp.Trim;
  if not EsIdentificador(Prop, True) then
    Exit(MsgFmt(SR_DESIGNER_SET_PROP_FMT, [AProp]));
  if AValor.Trim = '' then
    Exit(MsgText(SR_DESIGNER_SET_SIN_VALOR));
  if AValor.Contains(#10) or AValor.Contains(#13) then
    Exit(MsgText(SR_DESIGNER_SET_VALOR_LINEA));
  Result := AbreForm(APath, False, True, F);
  if Result <> '' then
    Exit;
  try
    Result := BuscaComponente(F, AComponente, Obj);
    if Result <> '' then
      Exit;
    Result := ClaseDeJuez(F, Obj, ClsId);
    if Result <> '' then
      Exit;
    // en FMX Left/Top no colocan un control (son el sitio del icono de un no
    // visual, TComponent.DefineProperties): se escribian, se contestaba bien
    // y no se movia nada (3.7, Hermes). Su sitio es Position.X/Y.
    if F.EsFmx and MatchText(Prop, ['Left', 'Top']) and F.Tabla.Desciende(ClsId, ID_FMX_CONTROL) then
      Exit(MsgFmt(SR_DESIGNER_FMX_LEFT_TOP_FMT, [NombreDe(Obj), Prop,
        IfThen(SameText(Prop, 'Left'), 'Position.X', 'Position.Y')]));
    V := AValor.Trim;
    Juicio := JuzgaPropiedad(F.Tabla, ClsId, Prop, V, Hoja, HayHoja);
    if HayHoja and (Hoja.Kind = 'm') then
      Exit(MsgFmt(SR_DESIGNER_SET_EVENTO_FMT, [Prop, NombreDe(Obj), Prop]));
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
    if MatchText(Base, ['string', 'char']) then
    begin
      if not LeeLiteralDeForm(V, Texto) then
      begin
        Texto := AValor;
        Comillas := True;
      end;
      Trozos := TrozosDeLiteral(Texto);
      V := string.Join(' ', Trozos);
      Juicio := JuzgaPropiedad(F.Tabla, ClsId, Prop, V, Hoja, HayHoja);
    end
    // un literal en una propiedad que por su tipo no es una cadena (un
    // Variant, o una que la tabla no conoce): escrito como el IDE tambien;
    // iba en crudo (P6 de la segunda revision de la 1.17.0)
    else if LeeLiteralDeForm(V, Texto) then
    begin
      Trozos := TrozosDeLiteral(Texto);
      V := string.Join(' ', Trozos);
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
    Nombre := NombreDe(Obj);
    if Quita then
    begin
      WasThere := F.Doc.DeleteProp(Obj, Prop);
      // no habia linea: nada que quitar ni que guardar (contestaba removed
      // sin haber quitado nada: segunda revision de la 1.17.0)
      if not WasThere then
        Exit(MsgFmt(SN_DESIGNER_NADA_QUE_QUITAR_FMT, [Nombre, Prop]));
    end
    else
      F.Doc.SetPropTrozos(Obj, Prop, Trozos, WasThere);
    F.Doc.Save;
    // el arbol se releyo al guardar: su linea, la de ahora
    LineaN := 0;
    Obj := ObjetoPorNombre(F.Doc, Nombre);
    if not Quita and (Obj <> nil) and F.Doc.PropLines(Obj, Prop, Ini, Fin) then
      LineaN := Ini + 1;
    Ret := TJSONObject.Create;
    try
      Ret.AddPair('set', Nombre + '.' + Prop);
      Ret.AddPair('value', V);
      if WasThere then
        Ret.AddPair('previous', Antes);
      if Comillas then
        Ret.AddPair('quoted', TJSONBool.Create(True));
      if Quita then
        Ret.AddPair('removed', TJSONBool.Create(True));
      if Aviso <> '' then
        Ret.AddPair('warning', Aviso);
      Ret.AddPair('file', F.DfmNombre);
      Ret.AddPair('line', TJSONNumber.Create(LineaN));
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
  ClsId, NomObj, NomViejo, NomPadre: string;
  ConTab: Boolean;
  Ret: TJSONObject;
begin
  Result := AbreForm(APath, False, True, F);
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
    // y el TabOrder que sigue en el padre nuevo
    Tab := 0;
    ConTab := (ClaseDeJuez(F, Obj, ClsId) = '') and Publica(F.Tabla, ClsId, 'TabOrder');
    if ConTab then
    begin
      Tab := SiguienteTabOrder(F.Doc, Padre);
      if F.Doc.PropLines(Obj, 'TabOrder', TIni, TFin) then
        Bloque[TIni - Ini] := LineasDePropiedad(LeadingWhite(Bloque[TIni - Ini]), 'TabOrder', [IntToStr(Tab)])[0]
      else
        Insert(LineasDePropiedad(SangriaDeNivel(Padre.Depth + 2), 'TabOrder', [IntToStr(Tab)]),
          Bloque, 1);
    end;
    Lineas := Copy(F.Doc.Lines);
    Delete(Lineas, Ini, Largo);
    Dest := Padre.EndLine - 1;
    if Dest > Fin then
      Dec(Dest, Largo);
    Insert(Bloque, Lineas, Dest);
    // los nombres ANTES de guardar: Save relee el arbol y estos objetos se van
    NomObj := NombreDe(Obj);
    NomViejo := NombreDe(Viejo);
    NomPadre := NombreDe(Padre);
    F.Doc.SetLines(Lineas);
    F.Doc.Save;
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
      PropiedadesDeTexto(F.Tabla, F.EsFmx, Id), Imp, Dfm, Pas, JuezDeReferencias(F));
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

function CambiaPropiedad(const APath, AComponente, AProp, AValor, AParent: string): string;
begin
  if AComponente.Trim = '' then
    Exit(MsgText(SR_DESIGNER_NEED_COMPONENT));
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
    Result := PlanDeBorrado(F.Doc, Obj, F.PasTexto, F.PasNombre, Imp, Dfm, Pas, JuezDeReferencias(F));
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

end.
