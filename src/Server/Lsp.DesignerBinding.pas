unit Lsp.DesignerBinding;

{ El form contra su clase: lo que el compilador NO comprueba. Cada objeto del
  .dfm/.fmx con su campo publicado, cada evento (OnX = Metodo) apuntando a un
  metodo que existe Y esta en published - lo unico que ve MethodAddress al
  hacer streaming -, nombres repetidos, eventos sin valor.

  Vivia dentro de la tool delphi_designer (check-binding) y solo lo veia quien
  lo pedia: hermes cableo un OnClick a un metodo que insert=metodo habia
  dejado en public, el build paso y el form murio en Zorin con "Invalid
  property value" (25-sep-2026). Ahora es motor y lo usan check-binding, el
  lint del designer, la ESCRITURA de un designer (delphi_edit avisa al momento)
  e insert=metodo, que pone en published lo que el designer pareja cablea. }

interface

uses
  Lsp.DesignerMeta, // la tabla: que es una propiedad, y donde acaban las clases del usuario
  Lsp.DesignerBin; // TLineaForm: las lineas de un form, por EL lector

{ El informe JSON de check-binding. APas vacio = el .pas del mismo nombre. La
  jaula del segundo path es de la tool, no de aqui. }
function DesignerBindingJson(const ADfm, APas: string): string;

{ Lo mismo, como lineas de aviso para el lint, sobre las lineas del designer
  que se le dan (las de DESPUES de escribir). Vacio = cuadra, o no hay .pas
  pareja contra el que comparar. }
function DesignerBindingWarnings(const ADfm: string;
  const ADfmLines: TArray<string>): TArray<string>;

{ EL juez de una linea de evento de un form ('OnClick = Button1Click',
  'AfterOpen = Tabla1AfterOpen', sangrada o no) en un objeto de clase AClase
  (su nombre o su identidad): el evento y el metodo; False si no lo es. Que
  la propiedad sea un evento lo dice la tabla M (Kind 'm': un metodo); solo
  si no lo sabe - sin tabla, una clase que no tiene, un item de una coleccion
  (AClase vacia: su clase no la dice el form) - lo dice el nombre (On...).
  Lo decidia siempre el nombre, y los eventos de un TDataSet no empiezan por
  On: medido el 18-oct-2026, check-binding daba clean un AfterOpen sin
  manejador o con el suyo en public, e insert=metodo lo dejaba en public.
  Lo usan el informe, insert=metodo y el analizador de impacto de
  delphi_designer (delete, set de Name). }
function EventoDeObjeto(M: TMetaTable; const AClase, ALinea: string;
  out AEvento, AMetodo: string): Boolean;

{ La clase de cada linea de un form, por su indice: la del objeto que la
  contiene (su linea de objeto la dice; la RAIZ, ARaiz: la clase que la
  juzga, que la suya es del usuario), o '' dentro de un item de una coleccion
  (su clase no la dice el form). Lo que EventoDeObjeto le pregunta a la
  tabla. }
function ClasesDeLasLineas(const AForm: TArray<TLineaForm>; const ARaiz: string): TArray<string>;

{ La clase que juzga la RAIZ de un form (ClaseDeJuezDeRaiz, sin el motor: lo
  piden el lint tras cada escritura e insert=metodo con el cerrojo de
  escribir): '' sin tabla o si su cadena sale a una base del usuario de otra
  unidad. APas, su .pas; APasTexto, su texto si ya se tiene. }
function JuezDeLaRaiz(M: TMetaTable; const AForm: TArray<TLineaForm>; const APas, APasTexto: string): string;

{ El designer (texto o binario) cablea AMethod como evento (Evento = AMethod,
  juzgado por EventoDeObjeto con la tabla sin esperarla). }
function DesignerWiresMethodFile(const ADfm, AMethod: string): Boolean;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.JSON,
  System.RegularExpressions,
  Lsp.Texts,
  Lsp.Patch,
  Lsp.DesignerForma, // UnidadDeDesigner: el .pas de un form
  System.Generics.Collections,
  Lsp.Pascal,
  Lsp.PascalDecl, // EL lector de clases y LA cadena de ancestros
  Lsp.ProjectUnits, // ResolutorDeUnidades: EL juez de "es la misma unidad" (V79)
  Lsp.Json;

const
  // la FORMA de una linea de evento - Prop = Metodo, y Prop = sin manejador -;
  // que Prop sea un evento lo dice EsEvento. Los nombres, con EL
  // identificador (Lsp.Pascal): un manejador con enye no casaba.
  LINEA_DE_EVENTO_RE = '^(' + PATRON_IDENT + ')\s*=\s*(' + PATRON_IDENT + ')\s*$';
  LINEA_SIN_VALOR_RE = '^(' + PATRON_IDENT + ')\s*=\s*$';

{ La propiedad AProp de un objeto de clase AClase es un evento: lo dice la
  tabla (Kind 'm'), si conoce la clase y llega a la propiedad; si no, el
  nombre (On...: la gramatica de la casa donde no hay juez, declarada). }
function EsEvento(M: TMetaTable; const AClase, AProp: string): Boolean;
const
  EVENTO_POR_EL_NOMBRE = '\AOn' + PATRON_IDENT + '\z';
var
  Id: string;
  Hoja: TPropRec;
  Hay: Boolean;
begin
  if (M <> nil) and (AClase <> '') and M.ClaseDeNombre(AClase, Id) then
  begin
    JuzgaPropiedad(M, Id, AProp, '', Hoja, Hay);
    if Hay and (Hoja.Kind <> '?') then
      Exit(Hoja.Kind = 'm');
  end;
  Result := TRegEx.IsMatch(AProp, EVENTO_POR_EL_NOMBRE);
end;

function EventoDeObjeto(M: TMetaTable; const AClase, ALinea: string;
  out AEvento, AMetodo: string): Boolean;
var
  Mt: TMatch;
begin
  AEvento := '';
  AMetodo := '';
  // sobre la linea RECORTADA, sin sangria
  Mt := TRegEx.Match(ALinea.Trim, LINEA_DE_EVENTO_RE);
  Result := Mt.Success and EsEvento(M, AClase, Mt.Groups[1].Value);
  if Result then
  begin
    AEvento := Mt.Groups[1].Value;
    AMetodo := Mt.Groups[2].Value;
  end;
end;

// un evento que se quedo sin manejador ('OnClick =')
function EventoSinValor(M: TMetaTable; const AClase, ALinea: string): Boolean;
var
  Mt: TMatch;
begin
  Mt := TRegEx.Match(ALinea.Trim, LINEA_SIN_VALOR_RE);
  Result := Mt.Success and EsEvento(M, AClase, Mt.Groups[1].Value);
end;

function ClasesDeLasLineas(const AForm: TArray<TLineaForm>; const ARaiz: string): TArray<string>;
var
  Pila: TArray<string>;
begin
  SetLength(Result, Length(AForm));
  Pila := [];
  for var I := 0 to High(AForm) do
  begin
    if AForm[I].Clase = clfObjeto then
      Pila := Pila + [IfThen(Length(Pila) = 0, ARaiz, AForm[I].ClaseObj)];
    if (Length(Pila) > 0) and (AForm[I].Coleccion = 0) then
      Result[I] := Pila[High(Pila)];
    if (AForm[I].Clase = clfFin) and (Length(Pila) > 0) then
      SetLength(Pila, Length(Pila) - 1);
  end;
end;

function JuezDeLaRaiz(M: TMetaTable; const AForm: TArray<TLineaForm>; const APas, APasTexto: string): string;
var
  Propias: TArray<TPropiedadDelUsuario>;
begin
  Result := '';
  if M = nil then
    Exit;
  for var I := 0 to High(AForm) do
    if AForm[I].Clase = clfObjeto then
      Exit(ClaseDeJuezDeRaiz(M, APas, APasTexto, AForm[I].ClaseObj, Propias, False));
end;

function BindingReport(const DfmLines: TArray<string>; const APasTexto, Pas: string;
  AIsFmx: Boolean; const ADfm: string): string;
var
  L, Nm, Cl2, Ev, Handler, RootClass, Chain, OClave: string;
  Ret: TJSONObject;
  Miss, MissEv, NotPub, Extra, Dups, Empty, SinPresentacion: TJSONArray;
  Fields, PubMethods, AnyMethods, Seen, Objetos: TStringList;
  I, Depth, SkipBelow: Integer;
  AncestorOutside, ClassFound, Complete: Boolean;
  Form: TArray<TLineaForm>;
  Clases: TArray<string>; // la clase de cada linea: la que juzga sus eventos
  Tabla: TMetaTable;
  FaltaTabla: TFaltaTabla;
  UsosDeLaUnidad: TArray<string>; // los dos uses de la unidad del form

  { Los campos y metodos publicados de UNA clase, del lector de clases
    (Lsp.PascalDecl): lo que va antes de cualquier palabra de visibilidad es
    published en una clase $M+, que es justo donde el IDE escribe los campos
    del designer. "A, B: TButton;" son dos componentes, y el tipo puede ir
    cualificado (Vcl.StdCtrls.TButton); uno generico (una lista) no es un
    componente. Cada clase con lo SUYO: se leia por lineas hasta el primer
    'end;', y un record anidado la cortaba (censo del 4-oct-2026). }
  procedure LeeMiembros(AClase: TTipoPas);
  begin
    for var C in AClase.Campos do
      // un class var no es el campo de un componente: el streaming busca
      // campos de la instancia
      if (C.Visibilidad in [vpDefecto, vpPublicada]) and (C.Tipo <> '') and not C.Generico and
         not C.DeClase then
        Fields.Values[C.Nombre] := UltimoTrozo(C.Tipo);
    for var R in AClase.Rutinas do
      if not R.DeClase and ((R.Rutina = 'procedure') or (R.Rutina = 'function')) then
      begin
        AnyMethods.Add(R.Nombre);
        if R.Visibilidad in [vpDefecto, vpPublicada] then
          PubMethods.Add(R.Nombre);
      end;
  end;

  { Algun campo publicado de la cadena es de la clase AClase (sin unidad
    delante): lo que mira TReader.GetFieldClass para crear un componente que
    no tiene campo propio. }
  function ClaseConCampo(const AClase: string): Boolean;
  begin
    for var K := 0 to Fields.Count - 1 do
      if SameText(Fields.ValueFromIndex[K], UltimoTrozo(AClase)) then
        Exit(True);
    Result := False;
  end;

  { La unidad de AClase la registra al ejecutar (RegisterClass, RegisterClasses,
    RegisterFmxClasses: hecho R de la tabla): TReader la crea sin campo, con
    GetClass. Sin tabla no se sabe, y se avisa como cuando no hay campo (el
    aviso dice que carga si la clase esta registrada). }
  function ClaseRegistrada(const AClase: string): Boolean;
  var
    Falta: TFaltaTabla;
    Id: string;
  begin
    var M := MetaTable(AIsFmx, Falta, 0);
    Result := (M <> nil) and M.ClaseDeNombre(UltimoTrozo(AClase), Id) and M.RegistradaAlEjecutar(Id);
  end;

  { Una clase de la instalacion - la tabla de su marco la conoce (sin
    esperarla) -: sus miembros no son del programador ni salen en el .dfm
    como objetos. Donde acaban las clases del usuario, como para el juez de
    la raiz (Lsp.DesignerMeta.ClaseDeJuezDeRaiz). Era una lista de seis
    nombres (TForm, TFrame, TDataModule...): un TForm3D, un TWebModule o un
    TQuickRep eran una base del usuario y el informe salia a medias. Sin
    tabla no se sabe, y se dice (a medias). }
  function DeLaInstalacion(const AClase: string): Boolean;
  var
    Falta: TFaltaTabla;
    Id: string;
  begin
    var M := MetaTable(AIsFmx, Falta, 0);
    Result := (M <> nil) and M.ClaseDeNombre(UltimoTrozo(AClase), Id);
  end;

  { La clase y sus ancestros HASTA DONDE LLEGA ESTA UNIDAD (LA cadena,
    Lsp.PascalDecl.CadenaDeAncestros). Un form cuyo ancestro vive en otra
    unidad hereda componentes que este fichero no ve: llamarlos ausentes seria
    mentir, asi que se para y se dice. }
  procedure CollectClass(const AName: string);
  var
    U: TUnidadPas;
    Mapa: TDictionary<string, string>;
    Cadena: TArray<string>;
    Sale: Boolean;
    T: TTipoPas;
  begin
    U := LeeFuentePascal(APasTexto);
    Mapa := TDictionary<string, string>.Create;
    try
      AnotaAncestros(U, Mapa);
      Cadena := CadenaDeAncestros(Mapa, AName, Sale);
      for var K := 0 to High(Cadena) do
      begin
        if Sale and (K = High(Cadena)) then
        begin
          // por donde sale de la unidad: o la clase no esta declarada aqui, o
          // su cadena sigue en otra unidad (una de la instalacion no:
          // Vcl.Forms.TForm tambien lo es)
          if K = 0 then
            ClassFound := False
          else if not DeLaInstalacion(Cadena[K]) then
          begin
            AncestorOutside := True;
            Chain := Chain + ' -> ' + Cadena[K];
          end;
          Break;
        end;
        if Chain <> '' then
          Chain := Chain + ' -> ';
        Chain := Chain + Cadena[K];
        T := U.Clase(UltimoTrozo(Cadena[K]));
        if T <> nil then
          LeeMiembros(T);
      end;
    finally
      Mapa.Free;
      U.Free;
    end;
  end;

begin
  Fields := TStringList.Create;
  PubMethods := TStringList.Create;
  AnyMethods := TStringList.Create;
  Seen := TStringList.Create;
  Objetos := TStringList.Create;
  Ret := TJSONObject.Create;
  try
    Fields.CaseSensitive := False;
    PubMethods.CaseSensitive := False;
    AnyMethods.CaseSensitive := False;
    Seen.CaseSensitive := False;
    Objetos.CaseSensitive := False;
    // EL lector de las lineas (Lsp.DesignerBin.LineasDeForm): el end de un
    // item de una coleccion no cierra un objeto. Aqui se contaba, el siguiente
    // componente pasaba por el form mismo y no se comprobaba: clean=true en
    // 20 .dfm de ejemplo que no lo estaban (revision de la 1.17.0)
    Form := LineasDeForm(DfmLines);
    // the names of every object of the .dfm, at any depth (for the fields
    // without a component, below)
    for I := 0 to High(DfmLines) do
      if (Form[I].Clase = clfObjeto) and (Form[I].Nombre <> '') then
        Objetos.Add(Form[I].Nombre);
    // ...y en una VISTA FMX, los de su maestro: la vista se carga ENCIMA de
    // el, y el campo de un componente que solo esta en el maestro no es un
    // campo sin componente (V122 de la 1.23.1, una vista de los Samples)
    var Maestro := MaestroDeVistaDeclarada(ADfm);
    if Maestro <> '' then
    begin
      var DelMaestro := SplitToLines(GTextoDeUnidad(Maestro));
      var FormMaestro := LineasDeForm(DelMaestro);
      for var K := 0 to High(FormMaestro) do
        if (FormMaestro[K].Clase = clfObjeto) and (FormMaestro[K].Nombre <> '') then
          Objetos.Add(FormMaestro[K].Nombre);
    end;

    // the root object of the .dfm names the class this form really is
    RootClass := '';
    // (THE reader of an object line: Lsp.DesignerBin.LineaDeObjeto)
    for I := 0 to High(DfmLines) do
      if Form[I].Clase = clfObjeto then
      begin
        // la clase de su unidad: la de una vista FMX es la de su maestro
        // (ClaseEnSuUnidad; V122 de la 1.23.1)
        RootClass := ClaseEnSuUnidad(ADfm, Form[I].ClaseObj);
        Ret.AddPair('form', Form[I].Nombre);
        Ret.AddPair('class', RootClass);
        Break;
      end;
    if RootClass = '' then
      Exit(MsgText(SR_DESIGNER_BINDING_NO_ROOT));

    ClassFound := True;
    AncestorOutside := False;
    Chain := '';
    CollectClass(RootClass);
    // que propiedad es un evento lo dice la tabla, sin esperarla (esto corre
    // tras cada escritura); la raiz, por la clase que la juzga
    Tabla := MetaTable(AIsFmx, FaltaTabla, 0);
    Clases := ClasesDeLasLineas(Form, JuezDeLaRaiz(Tabla, Form, Pas, APasTexto));
    Ret.AddPair('inheritanceChain', Chain);

    Miss := TJSONArray.Create;
    Ret.AddPair('componentsWithoutField', Miss);
    MissEv := TJSONArray.Create;
    Ret.AddPair('eventsWithoutMethod', MissEv);
    NotPub := TJSONArray.Create;
    Ret.AddPair('eventsWithMethodNotPublished', NotPub);
    Extra := TJSONArray.Create;
    Ret.AddPair('fieldsWithoutComponent', Extra);
    Dups := TJSONArray.Create;
    Ret.AddPair('duplicateNames', Dups);
    Empty := TJSONArray.Create;
    Ret.AddPair('eventsWithNoHandler', Empty);
    SinPresentacion := TJSONArray.Create;
    Ret.AddPair('presentationUnitsMissing', SinPresentacion);
    // sus dos uses: la unidad que registra la presentacion estilada de un
    // componente tiene que estar en el programa (V69)
    var UL := LeeFuentePascal(APasTexto);
    try
      UsosDeLaUnidad := UL.UsesInterface + UL.UsesImplementation;
    finally
      UL.Free;
    end;
    // ...juzgados como dcc, con los ambitos de SU proyecto (V79)
    var Resolutor := ResolutorDeUnidades(Pas);

    // Anything the class could not be read from makes the two "missing" lists
    // unsafe: what looks absent may simply live where we cannot see.
    Complete := ClassFound and not AncestorOutside;

    Depth := 0;
    SkipBelow := -1;
    for I := 0 to High(DfmLines) do
    begin
      L := DfmLines[I].Trim;
      // every object line counts for the nesting, named or not: an unnamed
      // one ('object TMemo') or a name with an accent did not match, its end
      // popped the parent, and the next component was taken for the form
      // itself and never checked (live test of 1.12.0)
      if Form[I].Clase = clfObjeto then
      begin
        OClave := Form[I].Clave;
        Nm := Form[I].Nombre;
        Cl2 := Form[I].ClaseObj;
        Inc(Depth);
        if Depth = 1 then
          Continue; // the form itself
        // Inside an inline FRAME the objects belong to the frame's own class,
        // not to this form: checking them here called every one missing.
        if (SkipBelow >= 0) and (Depth > SkipBelow) then
          Continue;
        // an unnamed object has no field to check
        if Nm <> '' then
        begin
          if Seen.IndexOf(Nm) >= 0 then
            Dups.Add(MsgFmt(SF_DSGN_REPITE_UN_NOMBRE_FMT, [Nm, I + 1]))
          else
            Seen.Add(Nm);
          // sin campo, TReader lo crea igual si su CLASE la nombra otro campo
          // publicado de la cadena (System.Classes, GetFieldClass) o si su
          // unidad la registra al ejecutar (GetClass; FMX.Menus registra
          // TMainMenu, FMX.ListBox TListBoxGroupHeader: cuatro Samples salian
          // como que no cargaban): solo se avisa cuando ninguna de las dos
          // (un Sample con cuatro TLabel sin campo y otros con el; 18-oct-2026)
          if Complete and (Fields.IndexOfName(Nm) < 0) and not ClaseConCampo(Cl2) and
             not ClaseRegistrada(Cl2) then
            Miss.Add(MsgFmt(SF_DSGN_NO_TIENE_CAMPO_PUBLICADO_FMT, [Nm, Cl2, I + 1, Cl2]));
        end;
        // la presentacion estilada de su clase, de una unidad que esta no usa
        // (hecho U): compila, carga, y FMX pinta su aviso en su lugar (V69)
        var IdP: string;
        if (Tabla <> nil) and Tabla.ClaseDeNombre(UltimoTrozo(Cl2), IdP) then
          for var UP in Tabla.UnidadesDePresentacion(IdP) do
            if not Resolutor.EnUses(UsosDeLaUnidad, UP) then
              SinPresentacion.Add(MsgFmt(SF_DSGN_SIN_UNIDAD_DE_PRESENTACION_FMT,
                [IfThen(Nm = '', Cl2, Nm), Cl2, I + 1, UP, TPath.GetFileName(Pas), UP]));
        if OClave = 'inline' then
          SkipBelow := Depth;
        Continue;
      end;
      if Form[I].Clase = clfFin then
      begin
        if (SkipBelow >= 0) and (Depth <= SkipBelow) then
          SkipBelow := -1;
        Dec(Depth);
        Continue;
      end;
      // un evento es una propiedad, tambien la de un item de una coleccion
      // (el OnClick de un TButtonItem); un trozo de una cadena partida no
      if (Form[I].Clase <> clfPropiedad) or ((SkipBelow >= 0) and (Depth > SkipBelow)) then
        Continue;
      if EventoSinValor(Tabla, Clases[I], L) then
      begin
        Empty.Add(MsgFmt(SF_DSGN_QUEDADO_SIN_VALOR_FMT, [L, I + 1]));
        Continue;
      end;
      if EventoDeObjeto(Tabla, Clases[I], L, Ev, Handler) then
      begin
        if PubMethods.IndexOf(Handler) >= 0 then
          Continue;
        // Declared, but not where the form loader can find it: the one case
        // the compiler and the first version of this tool both waved through.
        if AnyMethods.IndexOf(Handler) >= 0 then
          NotPub.Add(MsgFmt(SF_DSGN_NO_ESTA_EN_PUBLISHED_FMT, [Ev, Handler, I + 1, Handler]))
        else if Complete then
          MissEv.Add(MsgFmt(SF_DSGN_METODO_NO_DECLARADO_FMT, [Ev, Handler, I + 1, Handler]));
      end;
    end;

    // a published field with no component is the other half of the same slip:
    // the names of every object of the .dfm, by THE reader of that line (it
    // was a third regex here, built per field)
    if Complete then
      for I := 0 to Fields.Count - 1 do
        if Objetos.IndexOf(Fields.Names[I]) < 0 then
          Extra.Add(Fields.Names[I]);

    // clean = el form cuadra. Se llamaba ok, el mismo nombre que "la llamada
    // fue bien" en toda tool: dos significados en un campo (novena revision)
    Ret.AddPair('clean', TJSONBool.Create(ClassFound and (Miss.Count = 0) and
      (MissEv.Count = 0) and (NotPub.Count = 0) and (Extra.Count = 0) and
      (Dups.Count = 0) and (Empty.Count = 0) and (SinPresentacion.Count = 0)));
    if not ClassFound then
      Ret.AddPair('note', MsgFmt(SN_DESIGNER_BINDING_NOCLASS_FMT,
        [RootClass, TPath.GetFileName(Pas)]))
    else
    begin
      if not Complete then
        Ret.AddPair('partialNote', MsgFmt(SN_DESIGNER_BINDING_PARTIAL_FMT,
          [Chain]));
      Ret.AddPair('note', IfThen((Miss.Count = 0) and (MissEv.Count = 0) and
        (NotPub.Count = 0) and (Extra.Count = 0) and (Dups.Count = 0) and
        (Empty.Count = 0) and (SinPresentacion.Count = 0), MsgText(SN_DESIGNER_BINDING_OK),
        MsgText(SN_DESIGNER_BINDING_BAD)));
    end;
    Result := Ret.ToJSON;
  finally
    Ret.Free;
    Objetos.Free;
    Seen.Free;
    AnyMethods.Free;
    PubMethods.Free;
    Fields.Free;
  end;
end;

function DesignerBindingJson(const ADfm, APas: string): string;
var
  Pas, Enc, DfmTxt: string;
begin
  Pas := APas;
  if not EsRutaDeDesigner(ADfm) then
    Exit(MsgText(SR_DESIGNER_BINDING_NOT_FORM));
  if not TFile.Exists(ADfm) then
    Exit(MsgFmt(SR_DESIGNER_NO_FORM_FMT, [ADfm]));
  // Un binario DANADO antes de buscar la unit: "no encuentro la unit" sobre
  // un form ilegible manda a buscar un fichero que nunca fue el problema.
  // (el motivo es lo que DEVUELVE DesignerFileToText; Enc es el texto, y
  // cuando falla queda vacio: el rechazo salia sin motivo desde el 25-sep)
  // (por EL lector de designers, Lsp.Patch.TextoDeDesigner: binario o texto)
  var MotivoBin := TextoDeDesigner(ADfm, DfmTxt, Enc);
  if MotivoBin <> '' then
    Exit(MsgEnvuelve(SR_RECHAZADO_FMT, MotivoBin));
  // el troceador de todos (Lsp.Patch.SplitToLines: un CR suelto es salto)
  var Lineas := SplitToLines(DfmTxt);
  // uno que el parser del IDE no lee por lineas como LineasDeForm: el informe
  // saldria de otras lineas (DSGN-160, 3b del censo de jueces)
  Result := FormaDistintaDeLineas(Lineas, ExtractFileName(ADfm));
  if Result <> '' then
    Exit;
  if Pas = '' then
    Pas := UnidadDeDesigner(ADfm);
  if not TFile.Exists(Pas) then
    Exit(MsgFmt(SR_DESIGNER_NO_UNIT_FMT, [Pas]));
  // la unit, entera: sus clases las lee EL lector (LeeFuentePascal, sobre su
  // codigo: un bloque comentado no declara componentes)
  Result := BindingReport(Lineas, PatchLoadText(Pas, Enc), Pas, EsDesignerFmx(ADfm), ADfm);
end;

function DesignerBindingWarnings(const ADfm: string;
  const ADfmLines: TArray<string>): TArray<string>;
var
  Pas, Enc, S, Nombre: string;
  O: TJSONObject;
  Arr: TJSONArray;
  Res: TStringList;
  I: Integer;
begin
  Result := [];
  Pas := UnidadDeDesigner(ADfm);
  if not TFile.Exists(Pas) then
    Exit;
  S := BindingReport(ADfmLines, PatchLoadText(Pas, Enc), Pas, EsDesignerFmx(ADfm), ADfm);
  O := ObjetoJson(S); // EL lector (Lsp.Json): estaba su cuerpo aqui
  if O = nil then
    Exit;
  Res := TStringList.Create;
  try
    for Nombre in ['eventsWithMethodNotPublished', 'eventsWithoutMethod',
                   'eventsWithNoHandler', 'componentsWithoutField', 'duplicateNames',
                   'presentationUnitsMissing'] do
      if O.TryGetValue<TJSONArray>(Nombre, Arr) then
        for I := 0 to Arr.Count - 1 do
          Res.Add('  ' + Arr.Items[I].Value);
    if O.TryGetValue<TJSONArray>('fieldsWithoutComponent', Arr) then
      for I := 0 to Arr.Count - 1 do
        Res.Add(MsgFmt(SF_DSGN_CAMPO_SIN_OBJETO_FMT, [Arr.Items[I].Value]));
    if (Res.Count = 0) and not O.GetValue<Boolean>('clean', True) and
       O.TryGetValue<string>('note', S) then
      Res.Add('  ' + S);
    Result := Res.ToStringArray;
  finally
    Res.Free;
    O.Free;
  end;
end;

function DesignerWiresMethodFile(const ADfm, AMethod: string): Boolean;
var
  Txt, Enc, Ev, Metodo: string;
  Lineas, Clases: TArray<string>;
  Form: TArray<TLineaForm>;
  Falta: TFaltaTabla;
begin
  Result := False;
  if not TFile.Exists(ADfm) then
    Exit;
  if TextoDeDesigner(ADfm, Txt, Enc) <> '' then
    Exit;
  // EL juez del informe, y como lo aplica el informe: la tabla sin esperarla
  // (esto corre con el cerrojo de escribir: insert=metodo) y la raiz por la
  // clase que la juzga, sin el motor; un trozo de una cadena no es una linea
  Lineas := SplitToLines(Txt);
  Form := LineasDeForm(Lineas);
  var Tabla := MetaTable(EsDesignerFmx(ADfm), Falta, 0);
  Clases := ClasesDeLasLineas(Form, JuezDeLaRaiz(Tabla, Form, UnidadDeDesigner(ADfm), ''));
  for var I := 0 to High(Lineas) do
    // el mismo metodo aunque la caja de una letra acentuada difiera: asi lo
    // encuentra el streaming (MethodAddress) al cargar el form
    if (Form[I].Clase = clfPropiedad) and EventoDeObjeto(Tabla, Clases[I], Lineas[I], Ev, Metodo) and
       MismoIdentificador(Metodo, AMethod) then
      Exit(True);
end;

end.
