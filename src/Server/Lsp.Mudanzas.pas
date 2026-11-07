unit Lsp.Mudanzas;

{ LO QUE CRUZA EL BORDE de una mudanza y como se re-apunta: la nota de un
  move, una copia o un borrado como un operador (NotaDeMudanza: el par
  partido y lo que cruza el borde, sin re-apuntar nada), fix-references
  (ArreglaReferencias: lo que un proyecto o un grupo lista y ya no esta donde
  dice), y los grupos de proyectos (.groupproj), que fix-references recorre y
  que comparten con el el cambio de un texto por trozos. Vivia en
  Lsp.ProjectUnits (V94 de la depuracion de la 1.23, B6 de la 1.28): se mudo
  sin cambiar una linea. }

interface

{ ---- grupos de proyectos (.groupproj) ---- }

{ El Include de cada <Projects> de un grupo, en orden. }
function ProyectosDeGrupo(const AGroup: string): TArray<string>;

{ Anade AProject (su .dproj) al grupo como "Add existing project" del IDE: el
  item <Projects>, sus tres targets (X, X:Clean, X:Make) y su nombre en los
  CallTarget de Build, Clean y Make. Idempotente. }
function AnadeProyectoAGrupo(const AGroup, AProject: string): string;

{ La inversa: el item, sus targets y su nombre en los CallTarget. El
  proyecto se busca por su ruta, exista o no ya en el disco. }
function QuitaProyectoDeGrupo(const AGroup, AProject: string): string;

{ fix-references: re-apunta lo que un proyecto (sus units) o un grupo (sus
  proyectos) lista y ya no esta donde dice - lo movio alguien por fuera de
  las tools -, buscando el fichero por su NOMBRE bajo el borde del workspace.
  Con UNA coincidencia se re-apunta; con ninguna o varias se dice, y no se
  adivina. Los search paths que no existen se dicen: no hay nombre que
  buscar. }
function ArreglaReferencias(const AProject: string): string;

type
  { Que hizo el operador con lo que se nombro (V19): la nota informativa mira
    dentro de lo movido o copiado y, en un move o un borrado, fuera. }
  TMudanza = (mzMueve, mzCopia, mzBorra);

{ LA NOTA de un move, una copia o un borrado como un operador (V19 de la 1.23;
  David, 17-oct-2026: "nosotros como mucho informamos de lo que hemos
  detectado en la respuesta para que lo sepa"), la de delphi_move,
  delphi_delete y el commit de delphi_changeset: NO re-apunta ni lleva nada.
  Cada AViejos[I] (una carpeta o un fichero) esta ahora en ANuevos[I] (en un
  borrado, su copia de la papelera). Dice el par partido (una unit que se fue
  sin su .dfm/.fmx, o al reves, con la salida del comodin) y lo que cruza el
  borde de lo movido, copiado o borrado; de lo que salio de la papelera, solo
  lo primero. Cada parte con su salto delante; '' si no hay nada que decir. }
function NotaDeMudanza(const AViejos, ANuevos: TArray<string>;
  AMudanza: TMudanza): string;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.StrUtils,
  System.Generics.Collections,
  Lsp.JuicioDeForms,
  Lsp.Texts,
  Lsp.Guard,
  System.Generics.Defaults,
  Lsp.DesignerForma, // UnidadDeDesigner: la unit de un form, para el par partido
  Lsp.Dproj,       // el lector del .dproj y sus atributos
  Lsp.References,
  Lsp.NetDrives,  // SkipIdeArtifacts: una mudanza no entra en artefactos
  Lsp.Pascal,
  Lsp.Rutas,
  Lsp.Args,
  Lsp.Lugares,
  Lsp.Lineas,
  Lsp.Extensiones,
  Lsp.Puertas,
  // la ultima: lo suyo pesaba mas que lo de cualquier otra unidad cuando
  // esto vivia dentro de ella, y asi sigue
  Lsp.ProjectUnits;

type
  { Un trozo del texto a sustituir: se aplican de atras adelante. }
  TCambioTexto = record
    Inicio, Largo: Integer;
    Texto: string;
  end;

function AplicaCambios(const ATexto: string; ACambios: TArray<TCambioTexto>): string;
begin
  TArray.Sort<TCambioTexto>(ACambios, TComparer<TCambioTexto>.Construct(
    function(const L, R: TCambioTexto): Integer
    begin
      Result := R.Inicio - L.Inicio;
    end));
  Result := ATexto;
  for var C in ACambios do
    Result := Copy(Result, 1, C.Inicio - 1) + C.Texto + Copy(Result, C.Inicio + C.Largo, MaxInt);
end;

function DentroDe(const ARuta, AArbol: string): Boolean;
begin
  // por EL juez de rutas (el del sistema de ficheros, H1 de la 1.23)
  Result := RutaDentroDe(NormPath(AArbol), NormPath(ARuta));
end;

{ Donde esta AHORA ARuta si estaba en AViejo, que ahora es ANuevo ('' si no
  estaba dentro): juzgada y cortada en LA forma de DentroDe (sin su clave: el
  trozo conserva sus letras). Cortar el texto crudo por el largo de AViejo
  despues de juzgar en la forma larga daba un trozo desplazado con una de las
  dos en 8.3: MOVE-021 decia que la lib movida estaba en la carpeta, sin el
  \lib (V106 de la 1.23.1, medido). }
function Trasladada(const ARuta, AViejo, ANuevo: string): string;
begin
  Result := RutaTrasladada(FormaDeComparar(ARuta), FormaDeComparar(AViejo), ANuevo);
end;

{ La ruta nueva de AValor (relativa a ABaseVieja, visto desde AFicheroNuevo)
  si AMapa dice a donde fue su destino; '' si no se toca: absoluta, empieza
  por una macro ($(BDS)...), comodin, o AMapa contesta ''. La barra final se
  conserva: una carpeta sigue escrita como carpeta. }
function RutaReapuntada(const AValor, ABaseVieja, AFicheroNuevo: string;
  const AMapa: TFunc<string, string>; ADebeExistir: Boolean = False): string;
var
  V, Viejo, Nuevo: string;
  Barra: Boolean;
begin
  Result := '';
  V := AValor.Trim;
  if (V = '') or V.StartsWith('$(') or TPath.IsPathRooted(V) or V.Contains('*') then
    Exit;
  Barra := V.EndsWith('\') or V.EndsWith('/');
  try
    Viejo := SinBarraFinal(TPath.GetFullPath(TPath.Combine(ABaseVieja, V)));
  except
    Exit;
  end;
  Nuevo := AMapa(Viejo);
  if Nuevo = '' then
    Exit;
  // Una directiva cuyo fichero NO esta donde dice su ruta la resolvio el
  // compilador por el include/resource path: no se toca. {$I jedi.inc}
  // se reescribia a ..\jedi.inc y el build moria con F1026 (revision
  // del 26-sep-2026). Lo que esta sesion no lee ni se pregunta (ExisteYSeLee)
  if ADebeExistir and not ExisteYSeLee(Nuevo, True) then
    Exit;
  Result := IncludeFor(AFicheroNuevo, Nuevo);
  if Barra then
    Result := IncludeTrailingPathDelimiter(Result);
  if SameText(Result, V) then
    Result := '';
end;

{ Una lista ESCRITA de rutas (a;b;c, o una sola) con cada trozo re-apuntado
  por RutaReapuntada: solo se reescriben los trozos que cambian (XmlEscapeEn
  del nuevo, con la comilla del atributo que la lleva, #0 si no es uno) y el
  resto queda byte a byte. '' si no cambia ninguno; ACuenta suma los que
  cambian. }
function ListaReapuntada(const AEscrito, ABaseVieja, AFichero: string;
  const AMapa: TFunc<string, string>; AComilla: Char; var ACuenta: Integer): string;
var
  Partes: TArray<string>;
  Cambiado: Boolean;
begin
  Result := '';
  Partes := TrozosEscritos(AEscrito);
  Cambiado := False;
  for var I := 0 to High(Partes) do
  begin
    var R := RutaReapuntada(XmlUnescape(Partes[I]), ABaseVieja, AFichero, AMapa);
    if R <> '' then
    begin
      Partes[I] := XmlEscapeEn(R, AComilla);
      Cambiado := True;
      Inc(ACuenta);
    end;
  end;
  if Cambiado then
    Result := string.Join(';', Partes);
end;

type
  { Un sitio de un fichero de proyecto que lleva rutas relativas a el: el
    valor de una etiqueta (Atributo = '') o uno de sus atributos; Extension,
    si no es '', deja solo las que acaban asi; EnExists, las de los
    Exists('...') del atributo (una Condition, por RutasDeExists). }
  TSitioDeRutas = record
    Etiqueta, Atributo, Extension: string;
    EnExists: Boolean;
  end;

function Sitio(const AEtiqueta: string; const AAtributo: string = '';
  const AExtension: string = ''; AEnExists: Boolean = False): TSitioDeRutas;
begin
  Result.Etiqueta := AEtiqueta;
  Result.Atributo := AAtributo;
  Result.Extension := AExtension;
  Result.EnExists := AEnExists;
end;

{ EL esqueleto de las reescrituras de XML de la mudanza: en AFichero, cada
  sitio es una lista escrita de rutas relativas a AFichero, y se re-apuntan
  las que cruzan el borde, en su sitio; se guarda UNA vez. Era el mismo bucle
  en el .dproj y en el grupo (revision 26-sep-2026), sobre quince regex que
  pedian el atributo el primero y entre comillas dobles, y veian lo que hay
  en un comentario; ahora por EL analisis (TramosDeEtiqueta,
  AtributosDeTramo). Devuelve cuantas rutas cambio. ASoloMirar: las cuenta
  y no escribe nada (la nota informativa de V19; fix-references si escribe). }
function ReapuntaSitios(const AFichero, ABaseVieja: string;
  const ASitios: TArray<TSitioDeRutas>; const AMapa: TFunc<string, string>;
  ASoloMirar: Boolean = False): Integer;
var
  Enc, Texto: string;
  Cambios: TArray<TCambioTexto>;
  Cuenta: Integer;

  procedure Reapunta(AIni, AFin: Integer; const AExtension: string; AComilla: Char);
  begin
    var Escrito := Copy(Texto, AIni, AFin - AIni);
    // un valor con un CDATA o un comentario dentro no se sabe reescribir
    if Escrito.Contains('<') or
       ((AExtension <> '') and not SinMayusculas(Escrito.Trim).EndsWith(SinMayusculas(AExtension))) then
      Exit;
    var Nueva := ListaReapuntada(Escrito, ABaseVieja, AFichero, AMapa, AComilla, Cuenta);
    if Nueva = '' then
      Exit;
    var C: TCambioTexto;
    C.Inicio := AIni;
    C.Largo := AFin - AIni;
    C.Texto := Nueva;
    Cambios := Cambios + [C];
  end;

begin
  Cuenta := 0;
  Texto := PatchLoadText(AFichero, Enc);
  Cambios := [];
  // el texto de busqueda UNA vez para todos los sitios: veinte veces era un
  // 20% mas lenta que las regex de antes con una raiz grande (17-oct-2026)
  var Low := TextoDeBusqueda(Texto);
  for var S in ASitios do
    for var T in TramosEnTexto(Texto, Low, S.Etiqueta, S.Atributo <> '') do
      if S.Atributo = '' then
        Reapunta(T.Ini, T.Fin, S.Extension, #0)
      else
        for var At in AtributosDeTramo(Texto, T) do
          if SameText(At.Nombre, S.Atributo) then
            if not S.EnExists then
              Reapunta(At.Ini, At.Fin, S.Extension, Texto[At.Ini - 1])
            else
              for var E in RutasDeExists(Copy(Texto, At.Ini, At.Fin - At.Ini)) do
                Reapunta(At.Ini + E.Ini - 1, At.Ini + E.Fin - 1, S.Extension, #0);
  Result := Cuenta;
  if (Result > 0) and not ASoloMirar then
    PatchSaveText(AFichero, AplicaCambios(Texto, Cambios), Enc);
end;

{ Los sitios de un .dproj que son RUTAS: las listas de busqueda y las de
  salida (BUILD_OUTPUT_TAGS: la misma lista que la puerta del build), el
  icono, el manifiesto, los .rc que compila, los ficheros que despliega y
  los .optset que importa (David, 26-sep-2026: que "sigue compilando" sea
  verdad tambien con recursos e iconos). }
function SitiosDeDproj: TArray<TSitioDeRutas>;
begin
  Result := [];
  // (con las rutas que escribe NUESTRO scaffold, Lsp.Scaffold: el icono de
  // macOS, los logos UWP y el keystore de Android no se re-apuntaban y la
  // respuesta decia que si; J20 de la 1.28. La lista sigue siendo propia: la
  // forma sin lista, re-apuntar todo valor que resuelto cae en lo movido como
  // juzga la puerta del build, queda en la lista de forma)
  for var E in TArray<string>.Create('DCC_UnitSearchPath', 'DCC_IncludePath',
    'DCC_ResourcePath', 'DCC_ObjPath', 'Icon_MainIcon', 'Manifest_File',
    'CfgDependentOn', 'Icns_MainIcns', 'UWP_DelphiLogo44', 'UWP_DelphiLogo150', 'PF_KeyStore') do
    Result := Result + [Sitio(E)];
  for var E in BUILD_OUTPUT_TAGS do
    Result := Result + [Sitio(E)];
  Result := Result + [Sitio('RcCompile', 'Include'), Sitio('RcItem', 'Include'),
    Sitio('DeployFile', 'LocalName'), Sitio('Import', 'Project', '.optset'),
    Sitio('Import', 'Condition', '.optset', True)];
end;

{ Las directivas $I/$R/$L de AFichero cuya ruta cruza el borde (AMapa) y que
  el compilador lee donde dicen (el fichero estaba alli): las CUENTA, no
  escribe (V19: era ReapuntaDirectivas, que las reescribia). }
function DirectivasQueCruzan(const AFichero, ABaseVieja: string;
  const AMapa: TFunc<string, string>): Integer;
var
  Enc: string;
begin
  Result := 0;
  for var D in DirectivasDeFichero(PatchLoadText(AFichero, Enc)) do
    if RutaReapuntada(D.Ruta, ABaseVieja, AFichero, AMapa, True) <> '' then
      Inc(Result);
end;

{ Los proyectos de un grupo viven en TRES sitios del fichero: el Include de
  su <Projects>, el Projects= del MSBuild de sus targets y las
  <Dependencies> de los que dependen de el (esas no se re-apuntaban). }
function ReapuntaGrupo(const AGroup, ABaseVieja: string;
  const AMapa: TFunc<string, string>; ASoloMirar: Boolean = False): Integer;
begin
  Result := ReapuntaSitios(AGroup, ABaseVieja, [Sitio('Projects', 'Include'),
    Sitio('MSBuild', 'Projects'), Sitio('Dependencies')], AMapa, ASoloMirar);
end;

{ Si RenameProjectUnit dice que LO HIZO (su respuesta empieza como
  SN_UNIT_RENAMED_FMT). Lo pregunta fix-references: contaba el intento como
  hecho (revision 26-sep-2026). }
function Reapuntada(const AResp: string): Boolean;
begin
  Result := EsMsg(AResp, SN_UNIT_RENAMED_FMT);
end;

{ Las units que lista un proyecto (su in '...') cuya ruta cruza el borde
  (AMapa) y llevan a un fichero que existe: las CUENTA, no re-apunta (V19:
  era ReapuntaUnits, por RenameProjectUnit). Lo que cae fuera de lo que esta
  sesion lee no se mira: ni se cuenta ni se pregunta si existe (la lectura
  escondida de la mudanza, medida M1). }
function UnitsQueCruzan(const AProyecto, ABaseVieja: string;
  const AMapa: TFunc<string, string>): Integer;
begin
  Result := 0;
  for var PU in ProjectUnits(AProyecto, False) do
    if PU.Include <> '' then
    begin
      var R := RutaReapuntada(PU.Include, ABaseVieja, AProyecto, AMapa);
      if R = '' then
        Continue;
      var Nuevo := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(AProyecto), R));
      if ExisteYSeLee(Nuevo) then
        Inc(Result);
    end;
end;

{ Los fuentes, proyectos y grupos de un arbol, SIN cruzar un enlace (un
  junction dentro de lo movido no hace de lo de detras parte de la mudanza)
  y sin artefactos, papelera ni temporales. Un fichero suelto es el mismo. }
{ LOS ficheros bajo ARaiz que AAcepta admite, sin cruzar enlaces -tampoco si
  ARaiz lo es: lo de detras de un junction no se recorre ni se reescribe- ni
  entrar en artefactos del IDE, papelera, temporales o .git
  (SkipIdeArtifacts). Para en ATope (0 = sin tope). Una carpeta que se salta
  por su NOMBRE de artefacto (Win32, Debug...) y tiene fuentes dentro va a
  ASaltadas, para decirlo: se saltaba en silencio. El recorredor de la
  mudanza y de fix-references (eran dos casi iguales, revision 26-sep). }
function FicherosBajo(const ARaiz: string; const AAcepta: TFunc<string, Boolean>;
  ATope: Integer; var ASaltadas: TArray<string>): TArray<string>;
var
  Acc, Saltadas: TArray<string>;

  procedure Recorre(const D: string);
  begin
    if (ATope > 0) and (Length(Acc) >= ATope) then
      Exit;
    try
      for var F in TDirectory.GetFiles(D) do
        if not EsEnlace(F) and AAcepta(F) and ((ATope = 0) or (Length(Acc) < ATope)) then
          Acc := Acc + [F];
      for var Sub in TDirectory.GetDirectories(D) do
        if EsEnlace(Sub) then
          Continue
        else if SkipIdeArtifacts('\' + TPath.GetFileName(Sub) + '\') then
        begin
          if (SkipReason('\' + TPath.GetFileName(Sub) + '\', False) = SKIP_ARTIFACTS) and
             (Length(TDirectory.GetFiles(Sub, '*.pas')) > 0) then
            Saltadas := Saltadas + [Sub];
        end
        else
          Recorre(Sub);
    except
      // una carpeta que no se deja listar: se sigue con lo demas
    end;
  end;

begin
  Acc := [];
  Saltadas := [];
  if not EsEnlace(ARaiz) then
    if TFile.Exists(ARaiz) then
    begin
      if AAcepta(ARaiz) then
        Acc := [ARaiz];
    end
    else if TDirectory.Exists(ARaiz) then
      Recorre(ARaiz);
  Result := Acc;
  ASaltadas := ASaltadas + Saltadas;
end;

{ Desde donde se busca FUERA lo que apuntaba a lo movido. Con jaula: se sube
  mientras la carpeta de encima se pueda ESCRIBIR (lo que no se puede escribir
  tampoco se puede re-apuntar, y no se recorre). Sin jaula, la carpeta de
  encima y nada mas: se subia por el disco entero (revision 26-sep-2026). }
function BordeDeMudanza(const ADir: string): string;
var
  Padre: string;
begin
  Result := ADir;
  if not HayJaula then
  begin
    Padre := TPath.GetDirectoryName(ADir);
    if Padre <> '' then
      Result := Padre;
    Exit;
  end;
  // las de encima de ADir (la primera de Ancestros es ella), con el tope de la
  // casa: subia doce por encima de ella, y el motor ocho
  for var D in Copy(Ancestros(ADir, NIVELES_DE_SUBIDA), 1, MaxInt) do
  begin
    if EscrituraDenegada(D) <> '' then
      Break;
    Result := D;
  end;
end;

function BordeDesde(const ADir: string): string; forward;

{ Lo que el build de AFichero, un .dproj, sigue leyendo donde ESTABA lo movido
  (AViejo, que ahora es ANuevo) y la nota de MOVE-023 no cuenta: un trozo de un
  sitio de ruta que RutaReapuntada se salta - el que llega por una propiedad
  del documento ($(My-Path): una propiedad puede ser cualquier cosa) o el
  escrito absoluto -. Lo ESCRITO relativo no: ese lo cuenta ya MOVE-023
  (ReapuntaSitios, que desde V19 no reescribe), una ruta en una nota. Cada
  valor, expandido como lo tiene msbuild donde lo lee (ValoresQueLeeElBuild,
  EL expansor de la puerta del build) en cada build que el proyecto declara,
  antes (AXmlAntes, desde ABaseVieja) y despues (desde su carpeta de ahora):
  lo que llevaba a un sitio que existe (y esta sesion lee: ExisteYSeLee) y ya
  no lleva a donde ese sitio esta
  ahora. Se NOMBRA, uno por valor (Opus en Hermes, 22-oct-2026: tras mover
  lib, un $(My-Path)=lib daba F2613 sin pista). }
function RutasQueYaNoLlegan(const AFichero, AXmlAntes, ABaseVieja, AViejo,
  ANuevo: string): TArray<string>;
var
  Enc, XmlAhora, BaseNueva, Mal: string;
  Propiedades, Items, Plataformas, Configs, Definidas: TArray<string>;
  Info: TDprojInfo;

  // la propiedad por la que empieza un trozo ($(X)...), '' si no empieza asi:
  // el primer nombre de EL recorrido (Lsp.Dproj.RecorreMacros; aqui se buscaba
  // el ')' a mano, revisor del paisaje del cierre de la 1.26)
  function PropiedadDelTrozo(const T: string): string;
  var
    Parado: Boolean;
  begin
    Result := '';
    if not T.StartsWith('$(') then
      Exit;
    var Primero := '';
    RecorreMacros(T,
      function(const ANombre: string; out AV: string): TAccionDeMacro
      begin
        Primero := ANombre;
        Result := amPara;
      end, Parado);
    Result := Primero;
  end;

  // un trozo ya expandido, resuelto desde ABase; '' si no se sabe a donde
  // lleva (lo que el documento no sabe queda escrito como $(X))
  function Resuelto(const ATrozo, ABase: string): string;
  begin
    Result := '';
    if ATrozo.Contains('$(') or ATrozo.Contains('@(') or ATrozo.Contains('%(') then
      Exit;
    // como lo lee msbuild desde esa carpeta (EL resolutor)
    Result := SinBarraFinal(RutaDesde(ABase, ATrozo));
  end;

  // si algun sitio de ruta lleva un trozo que RutaReapuntada se salta: uno
  // absoluto o uno que empieza por una propiedad que el documento define (no
  // la del propio elemento: $(DCC_UnitSearchPath), la herencia que escribe el
  // IDE). Lo demas lo cuenta MOVE-023; sin esto no se evalua nada
  function HayQueMirar: Boolean;
  var
    Els: TArray<TElementoXml>;
    Valores: TArray<string>;
  begin
    Result := False;
    Els := ElementosDe(AXmlAntes, Mal);
    Definidas := PropiedadesDefinidas(Els);
    for var E in Els do
    begin
      if Length(E.Ruta) = 0 then
        Continue;
      Valores := [];
      if (E.Ruta[High(E.Ruta)] = 'propertygroup') and MatchText(E.Escrito, Propiedades) then
        Valores := [ValorDeTramo(AXmlAntes, E.Tramo)]
      else if (E.Ruta[High(E.Ruta)] = 'itemgroup') and MatchText(E.Escrito, Items) then
        for var At in AtributosDeTramo(AXmlAntes, E.Tramo) do
          if SameText(At.Nombre, 'Include') then
            Valores := Valores + [ValorDeAtributo(AXmlAntes, At)];
      for var V in Valores do
        for var T in TrozosDeLista(V) do
        begin
          if TPath.IsPathRooted(T) then
            Exit(True);
          var Nombre := PropiedadDelTrozo(T);
          if (Nombre <> '') and not SameText(Nombre, E.Escrito) and MatchText(Nombre, Definidas) then
            Exit(True);
        end;
    end;
  end;

begin
  Result := [];
  // los sitios de ruta que se leen como valor: las propiedades y el Include
  // de los items (los de SitiosDeDproj; el atributo de un DeployFile y el
  // Import no los da ValoresQueLeeElBuild)
  Propiedades := [];
  Items := [];
  for var S in SitiosDeDproj do
    if S.Atributo = '' then
      Propiedades := Propiedades + [S.Etiqueta]
    else if SameText(S.Atributo, 'Include') then
      Items := Items + [S.Etiqueta];
  if not HayQueMirar then
    Exit;
  XmlAhora := PatchLoadText(AFichero, Enc);
  BaseNueva := TPath.GetDirectoryName(AFichero);
  Info := InfoDeDproj(XmlAhora);
  Info.SusBuilds(Plataformas, Configs);
  for var Plat in Plataformas do
    for var Cfg in Configs do
    begin
      var Antes := ValoresQueLeeElBuild(AXmlAntes, Plat, Cfg, [], []);
      var Ahora := ValoresQueLeeElBuild(XmlAhora, Plat, Cfg, [], []);
      // la reescritura no quita ni pone valores: si no casan, no se compara
      if Length(Antes) <> Length(Ahora) then
        Continue;
      // los trozos ESCRITOS relativos de los sitios de ruta de este build: los
      // cuenta MOVE-023, aqui no (con una propiedad o una absoluta en el
      // documento salian en las dos notas); de TODOS sus valores, porque la
      // herencia del IDE ($(DCC_UnitSearchPath)) los repite expandidos en otros
      var Escritos: TArray<string> := [];
      for var V in Antes do
        if MatchText(V.Elemento, Propiedades + Items) then
          for var W in TrozosDeLista(DesescapaDeMsbuild(V.Escrito)) do
            if (W.Trim <> '') and not W.Trim.StartsWith('$(') and not TPath.IsPathRooted(W.Trim) then
              Escritos := Escritos + [W.Trim];
      for var I := 0 to High(Antes) do
      begin
        if not SameText(Antes[I].Elemento, Ahora[I].Elemento) or
           not MatchText(Antes[I].Elemento, Propiedades + Items) or
           (Antes[I].Dudoso <> '') or (Ahora[I].Dudoso <> '') then
          Continue;
        var Leidas: TArray<string> := [];
        for var T in TrozosDeLista(DesescapaDeMsbuild(Ahora[I].Expandido)) do
        begin
          var R := Resuelto(T, BaseNueva);
          if R <> '' then
            Leidas := Leidas + [R];
        end;
        for var T in TrozosDeLista(DesescapaDeMsbuild(Antes[I].Expandido)) do
        begin
          if RutaEnLista(T.Trim, Escritos) then
            Continue;
          var R := Resuelto(T, ABaseVieja);
          if R = '' then
            Continue;
          // donde esta AHORA lo que leia: movido si estaba dentro
          var Destino := Trasladada(R, AViejo, ANuevo);
          if Destino = '' then
            Destino := R;
          if RutaEnLista(Destino, Leidas) or not ExisteYSeLee(Destino, True) then
            Continue;
          // si lo que leia no se movio, el que se movio es este .dproj y su
          // propiedad relativa lleva ahora a otro sitio: no es "which is now"
          var Item: string;
          if SameFileName(Destino, R) then
            Item := MsgFmt(SF_REUBICA_NO_LLEGA_QUIETO_FMT, [AFichero, Antes[I].Elemento,
              Antes[I].Escrito, R])
          else
            Item := MsgFmt(SF_REUBICA_NO_LLEGA_ITEM_FMT, [AFichero,
              Antes[I].Elemento, Antes[I].Escrito, R, Destino]);
          // la PROPIEDAD por la que llega, si la define el documento: la que
          // hay que cambiar (Opus sobre la 1.22.2: MOVE-021 no la decia)
          for var Escrito in TrozosDeLista(Antes[I].Escrito) do
          begin
            var Nombre := PropiedadDelTrozo(Escrito.Trim);
            if (Nombre <> '') and not SameText(Nombre, Antes[I].Elemento) and
               MatchText(Nombre, Definidas) then
            begin
              Item := Item + MsgFmt(SF_REUBICA_NO_LLEGA_PROPIEDAD_FMT, [Nombre]);
              Break;
            end;
          end;
          if not MatchText(Item, Result) then
            Result := Result + [Item];
        end;
      end;
    end;
end;

{ Lo que cruza el borde, para NotaDeMudanza: DENTRO de lo movido o copiado,
  las rutas RELATIVAS que cruzan su borde y ahora llevan a otro sitio (una
  copia a la misma altura no avisa de nada); FUERA, en un move o un borrado,
  lo que apuntaba dentro: las units que lista un proyecto (.dpr/.dpk y
  DCCReference), las rutas del .dproj, las directivas $I/$R/$L y los
  proyectos de un grupo, cada fichero con su ruta entera; y lo que el build
  lee por una propiedad ($(X)) o escrito absoluto, con la propiedad que hay
  que cambiar (MOVE-021). '' si todo queda dentro. }
function ReferenciasQueCruzan(const AViejos, ANuevos: TArray<string>;
  AMudanza: TMudanza): string;
const
  TOPE = 10;
var
  Viejos, Nuevos, Lineas, Saltadas, NoLlegan, Bordes, Ilegibles: TArray<string>;
  EsDeMudanza: TFunc<string, Boolean>;

  // lo de DENTRO de AViejo que apunta FUERA: su destino no se movio y es el
  // relativo el que ya no llega (un parametro de valor: la funcion anonima no
  // puede capturar las variables de la rutina de fuera, y la del bucle la
  // capturaria por referencia)
  function FueraDe(AViejo: string): TFunc<string, string>;
  begin
    Result :=
      function(A: string): string
      begin
        if DentroDe(A, AViejo) then
          Result := ''
        else
          Result := A;
      end;
  end;

  { Lo que cruza en UN fichero, contado por formato, a su linea de la nota
    ("<ruta> (2 units, 1 path)"); y lo que su build lee por una propiedad o
    absoluto, del par AIndice (-1: de todos). Una nota, no una operacion: lo
    que no se deja leer no se cuenta: se NOMBRA con su motivo (un .dpr que
    otro proceso tiene abierto no es "ninguno lo lista", E131). }
  procedure Mira(const AFichero, ABase: string; const AMapa: TFunc<string, string>;
    AIndice: Integer);
  var
    NUnits, NRutas, NDirect, NGrupos: Integer;
    Partes: TArray<string>;
    Enc, Ext: string;
  begin
    NUnits := 0; NRutas := 0; NDirect := 0; NGrupos := 0;
    Ext := LowerCase(TPath.GetExtension(AFichero));
    try
      if EsFuentePrincipal(AFichero) then // EL predicado (octava pasada de Fable)
        NUnits := UnitsQueCruzan(AFichero, ABase, AMapa);
      if Ext = '.dproj' then
      begin
        NRutas := ReapuntaSitios(AFichero, ABase, SitiosDeDproj, AMapa, True);
        if AMudanza = mzMueve then
          for var I := 0 to High(Viejos) do
            if (AIndice < 0) or (AIndice = I) then
              for var N in RutasQueYaNoLlegan(AFichero, PatchLoadText(AFichero, Enc), ABase,
                Viejos[I], Nuevos[I]) do
                if not RutaEnLista(N, NoLlegan) then
                  NoLlegan := NoLlegan + [N];
      end;
      if EsManifiesto(AFichero) then
        Inc(NRutas, ReapuntaSitios(AFichero, ABase, [Sitio('DeployFile', 'Include')], AMapa, True));
      if EsRutaDeFuente(AFichero) then // EL predicado (era SOURCE_EXTS a mano)
        NDirect := DirectivasQueCruzan(AFichero, ABase, AMapa);
      if Ext = '.groupproj' then
        NGrupos := ReapuntaGrupo(AFichero, ABase, AMapa, True);
    except
      on E: Exception do
        Ilegibles := Ilegibles + [MsgFmt(SF_CRUZA_FICHERO_FMT, [AFichero, PrimerTrozo(E.Message, [#10])])];
    end;
    Partes := [];
    if NUnits > 0 then
      Partes := Partes + [MsgFmt(SF_CRUZA_CUENTA_FMT, [NUnits, MsgText(SF_CRUZA_UNITS)])];
    if NRutas > 0 then
      Partes := Partes + [MsgFmt(SF_CRUZA_CUENTA_FMT, [NRutas, MsgText(SF_CRUZA_RUTAS)])];
    if NDirect > 0 then
      Partes := Partes + [MsgFmt(SF_CRUZA_CUENTA_FMT, [NDirect, MsgText(SF_CRUZA_DIRECTIVAS)])];
    if NGrupos > 0 then
      Partes := Partes + [MsgFmt(SF_CRUZA_CUENTA_FMT, [NGrupos, MsgText(SF_CRUZA_GRUPOS)])];
    // por la ruta entera: dos App.dproj de carpetas distintas son dos
    if Length(Partes) > 0 then
      Lineas := Lineas + [MsgFmt(SF_CRUZA_FICHERO_FMT, [AFichero, string.Join(', ', Partes)])];
  end;

  function DentroDeAlguno(const F: string; const ALista: TArray<string>): Boolean;
  begin
    Result := False;
    for var L in ALista do
      if DentroDe(F, L) then
        Exit(True);
  end;

begin
  Result := '';
  Viejos := [];
  Nuevos := [];
  for var I := 0 to High(AViejos) do
  begin
    Viejos := Viejos + [PrefijoSinBarra(TPath.GetFullPath(AViejos[I]))];
    Nuevos := Nuevos + [PrefijoSinBarra(TPath.GetFullPath(ANuevos[I]))];
  end;
  Lineas := [];
  Saltadas := [];
  NoLlegan := [];
  Ilegibles := [];
  // Lo de FUERA que apuntaba DENTRO: su destino SI se ha movido (o se borro).
  var Traslada: TFunc<string, string> :=
    function(A: string): string
    begin
      Result := '';
      for var K := 0 to High(Viejos) do
      begin
        Result := Trasladada(A, Viejos[K], Nuevos[K]);
        if Result <> '' then
          Exit;
      end;
    end;
  EsDeMudanza :=
    function(F: string): Boolean
    begin
      // los fuentes, los proyectos y el manifiesto, por SUS predicados
      Result := EsRutaDeFuente(F) or EsRutaDeProyecto(F) or EsManifiesto(F);
    end;
  // DENTRO de lo movido o copiado: lo que sale de su borde
  if AMudanza in [mzMueve, mzCopia] then
    for var I := 0 to High(Nuevos) do
      for var F in FicherosBajo(Nuevos[I], EsDeMudanza, 0, Saltadas) do
        Mira(F, TPath.GetDirectoryName(RutaTrasladada(F, Nuevos[I], Viejos[I])), FueraDe(Viejos[I]), I);
  // ...y FUERA, en un move o un borrado, lo que apuntaba dentro: desde el
  // borde escribible (BordeDeMudanza), una vez por borde
  if AMudanza in [mzMueve, mzBorra] then
  begin
    Bordes := [];
    for var V in Viejos do
    begin
      var B := BordeDeMudanza(TPath.GetDirectoryName(V));
      if not RutaEnLista(B, Bordes) then
        Bordes := Bordes + [B];
    end;
    for var B in Bordes do
      for var F in FicherosBajo(B, EsDeMudanza, 0, Saltadas) do
        if not DentroDeAlguno(F, Nuevos) then
          Mira(F, TPath.GetDirectoryName(F), Traslada, -1);
  end;
  if Length(Lineas) > 0 then
  begin
    var Texto := string.Join('; ', Copy(Lineas, 0, TOPE));
    if Length(Lineas) > TOPE then
      Texto := Texto + MsgFmt(SF_FILE_Y_MAS_FMT, [Length(Lineas) - TOPE]);
    if AMudanza = mzBorra then
      Result := MsgFmt(SN_REFERENCIAS_A_LO_BORRADO_FMT, [Texto])
    else
      Result := MsgFmt(SN_REFERENCIAS_CRUZAN_FMT, [Texto]);
  end;
  if Length(Saltadas) > 0 then
    AnadeLinea(Result, MsgFmt(SN_REUBICA_SALTADAS_FMT, [string.Join('; ', Saltadas)]));
  if Length(NoLlegan) > 0 then
    AnadeLinea(Result, MsgFmt(SN_REUBICA_NO_LLEGA_FMT, [string.Join('; ', NoLlegan)]));
  if Length(Ilegibles) > 0 then
  begin
    var Texto := string.Join('; ', Copy(Ilegibles, 0, TOPE));
    if Length(Ilegibles) > TOPE then
      Texto := Texto + MsgFmt(SF_FILE_Y_MAS_FMT, [Length(Ilegibles) - TOPE]);
    AnadeLinea(Result, MsgFmt(SN_REFERENCIAS_ILEGIBLES_FMT, [Texto]));
  end;
end;

{ El AVISO del par (V19; David, 25-oct-2026: "hablamos de avisar como mucho y
  de permitir form.*"): una unit que se fue sin su .dfm/.fmx, o un designer sin
  su unit (el IDE los lee lado a lado: la directiva R de la unit), con la
  salida: el comodin. AHechos: lo que se movio, se copio o se borro; ADestinos,
  adonde llego cada uno (vacio en un borrado); AVerbo, que se le hizo. El par no
  se parte si el que se queda es el MISMO que lo que llego lee a su lado: un
  renombrado de solo mayusculas (medido en vivo con r1222cf el 26-oct-2026:
  UFicha.pas -> UFICHA.pas decia que se iba sin su UFicha.dfm). AFuentes: donde
  se lee AHORA el texto de cada uno (su copia al copiar, adonde llego al mover,
  la papelera al borrar): de el salen las vistas FMX que declara una unit, y
  una que se iba sin la suya no avisaba (V122 de la 1.23.1). }
function AvisosDelPar(const AHechos, ADestinos, AFuentes: TArray<string>; const AVerbo: string): string;
begin
  Result := '';
  for var I := 0 to High(AHechos) do
  begin
    var F := AHechos[I];
    // el otro del par donde estaba y el que leera a su lado lo que llego (EL
    // nombrador del par: DesignersDeUnidad / UnidadDeDesigner, en su orden)
    var Otros: TArray<string> := [];
    var Alli: TArray<string> := [];
    if SameText(TPath.GetExtension(F), '.pas') then
    begin
      var Fuente := '';
      if I < Length(AFuentes) then
        Fuente := AFuentes[I];
      Otros := DesignersDeUnidad(F, Fuente);
      if I < Length(ADestinos) then
        Alli := DesignersDeUnidad(ADestinos[I]);
    end
    else if EsRutaDeDesigner(F) then
    begin
      Otros := [UnidadDeDesigner(F)];
      if I < Length(ADestinos) then
        Alli := [UnidadDeDesigner(ADestinos[I])];
    end;
    for var K := 0 to High(Otros) do
      if TFile.Exists(Otros[K]) and not RutaEnLista(Otros[K], AHechos) and
         not ((K < Length(Alli)) and MismaEntrada(Otros[K], Alli[K])) then
        Result := Result + #10 + MsgFmt(SN_FILE_PAR_PARTIDO_FMT, [TPath.GetFileName(F), AVerbo,
          TPath.GetFileName(ComoEnDisco(Otros[K])), TPath.GetDirectoryName(Otros[K]),
          TPath.Combine(TPath.GetDirectoryName(F), TPath.GetFileNameWithoutExtension(F) + '.*')]);
  end;
end;

function NotaDeMudanza(const AViejos, ANuevos: TArray<string>;
  AMudanza: TMudanza): string;
var
  Verbo, Nota: string;
  Viejos, Nuevos: TArray<string>;
begin
  case AMudanza of
    mzMueve: Verbo := MsgText(SF_PAR_MOVIDO);
    mzCopia: Verbo := MsgText(SF_PAR_COPIADO);
  else
    Verbo := MsgText(SF_PAR_BORRADO);
  end;
  if AMudanza = mzBorra then
    Result := AvisosDelPar(AViejos, [], ANuevos, Verbo)
  else
    Result := AvisosDelPar(AViejos, ANuevos, ANuevos, Verbo);
  // lo que sale de la papelera era una copia: no hay proyecto que la liste
  Viejos := [];
  Nuevos := [];
  for var I := 0 to High(AViejos) do
    if not EnPapelera(AViejos[I]) then
    begin
      Viejos := Viejos + [AViejos[I]];
      Nuevos := Nuevos + [ANuevos[I]];
    end;
  if Length(Viejos) = 0 then
    Exit;
  Nota := ReferenciasQueCruzan(Viejos, Nuevos, AMudanza);
  if Nota <> '' then
    Result := Result + #10 + Nota;
end;

{ ======================================================= grupos de proyectos }

function ProyectosDeGrupo(const AGroup: string): TArray<string>;
var
  Enc: string;
begin
  // el lector de atributos de la casa (comillas simples o dobles, sin
  // distinguir mayusculas, el valor desescapado), no una regex propia
  Result := AllTagAttr(PatchLoadText(AGroup, Enc), 'Projects', 'Include');
end;

function MismoProyecto(const AGroup, AInclude, AAbs: string): Boolean;
begin
  try
    Result := MismoInclude(AGroup, AInclude, AAbs); // EL resolutor (V204)
  except
    Result := False;
  end;
end;

function AnadeProyectoAGrupo(const AGroup, AProject: string): string;
var
  Enc, Texto, NL, Proj, Incl, Nombre: string;
  P, Desde, Hasta: Integer;
  T: TTramoXml;

  { El <Target> que se llama ANombre: msbuild no distingue mayusculas en el
    nombre de un target. Por EL analisis, como todo el grupo (eran diez regex,
    con el Name el primero y entre comillas dobles). }
  function TargetLlamado(const ANombre: string; out ATarget: TTramoXml): Boolean;
  begin
    for var X in TramosDeEtiqueta(Texto, 'Target', True) do
      if SameText(AtributoDeTramo(Texto, X, 'Target', 'Name'), ANombre) then
      begin
        ATarget := X;
        Exit(True);
      end;
    Result := False;
  end;

  { El Targets= del <CallTarget> de un agregado en la forma del IDE: el
    CallTarget es lo primero que lleva. False si no la tiene. }
  function ListaDeAgregado(const ATarget: TTramoXml; out AAtributo: TAtributoXml): Boolean;
  begin
    Result := False;
    var Llamadas := TramosDentro(Texto, 'CallTarget', ATarget, True);
    if (Length(Llamadas) = 0) or
       (Copy(Texto, ATarget.Ini, Llamadas[0].Abre - ATarget.Ini).Trim <> '') then
      Exit;
    for var At in AtributosDeTramo(Texto, Llamadas[0]) do
      if SameText(At.Nombre, 'Targets') then
      begin
        AAtributo := At;
        Result := True;
      end;
  end;

  { Donde entra lo que el grupo no tiene: delante de su Import, o de su
    cierre, como lo pone el IDE. 0 si el fichero no tiene forma de grupo.
    Estaba escrito dos veces. }
  function AlFinal: Integer;
  var
    D, H: Integer;
  begin
    var Imports := TramosDeEtiqueta(Texto, 'Import', True);
    if Length(Imports) > 0 then
    begin
      ConSuLinea(Texto, Imports[0].Abre, Imports[0].Cierra, D, H);
      Result := D;
    end
    else
      Result := CierreDelProyecto(Texto);
  end;

begin
  Proj := TPath.GetFullPath(DprojDe(AProject));
  if not TFile.Exists(Proj) then
    Exit(MsgFmt(SR_GRUPO_SIN_DPROJ_FMT, [TPath.GetFileName(Proj)]));
  for var I in ProyectosDeGrupo(AGroup) do
    if MismoProyecto(AGroup, I, Proj) then
      Exit(MsgFmt(SN_GRUPO_YA_ESTABA_FMT, [TPath.GetFileName(Proj), TPath.GetFileName(AGroup)]));
  Texto := PatchLoadText(AGroup, Enc);
  NL := SaltoDominante(Texto);
  // El IDE nombra los targets por el proyecto, con el punto cambiado por '_':
  // msbuild no admite un '.' en el nombre de un target ($@()%*?. ) y el grupo
  // dejaba de cargar con MakerAi.UI.dproj; el IDE escribe MakerAi_UI (medido
  // por el revisor del paisaje de la 1.29, B2, en dos .groupproj del IDE).
  // Dos con el mismo nombre en un grupo no caben: se dice, no se inventa un
  // sufijo.
  Nombre := TPath.GetFileNameWithoutExtension(Proj).Replace('.', '_');
  if TargetLlamado(Nombre, T) then
    Exit(MsgFmt(SR_GRUPO_TARGET_DUP_FMT, [Nombre, TPath.GetFileName(AGroup)]));
  Incl := IncludeFor(AGroup, Proj);
  // 1. el item, detras del ultimo <Projects> (o en un ItemGroup nuevo)
  var Item := '        <Projects ' + XmlAtributo('Include', Incl) + '>' + NL +
    '            <Dependencies/>' + NL + '        </Projects>' + NL;
  var Items := TramosDeEtiqueta(Texto, 'Projects', True);
  if Length(Items) > 0 then
  begin
    ConSuLinea(Texto, Items[High(Items)].Abre, Items[High(Items)].Cierra, Desde, Hasta);
    Insert(Item, Texto, Hasta);
  end
  else
  begin
    var Grupos := TramosDeEtiqueta(Texto, 'PropertyGroup');
    if Length(Grupos) = 0 then
      Exit(MsgFmt(SR_GRUPO_FORMA_FMT, [TPath.GetFileName(AGroup), MsgText(SF_GRUPO_SIN_SITIO_PROYECTO)]));
    Insert(NL + '    <ItemGroup>' + NL + Item + '    </ItemGroup>', Texto, Grupos[0].Cierra);
  end;
  // 2. sus tres targets, delante de Build (o de lo que cierra el grupo)
  var Targets := '';
  for var Suf in TArray<string>.Create('', ':Clean', ':Make') do
  begin
    Targets := Targets + '    <Target ' + XmlAtributo('Name', Nombre + Suf) + '>' + NL +
      '        <MSBuild ' + XmlAtributo('Projects', Incl);
    if Suf <> '' then
      Targets := Targets + ' ' + XmlAtributo('Targets', Suf.Substring(1));
    Targets := Targets + '/>' + NL + '    </Target>' + NL;
  end;
  if TargetLlamado('Build', T) then
  begin
    ConSuLinea(Texto, T.Abre, T.Cierra, Desde, Hasta);
    P := Desde;
  end
  else
    P := AlFinal;
  if P = 0 then
    Exit(MsgFmt(SR_GRUPO_FORMA_FMT, [TPath.GetFileName(AGroup), MsgText(SF_GRUPO_SIN_FINAL)]));
  Insert(Targets, Texto, P);
  // 3. su nombre en los agregados Build, Clean y Make, por UN camino (eran
  //    dos: crearlos todos si no habia ninguno, o anadir a sus listas): en la
  //    lista del que existe; el que falta se crea con este proyecto; el que
  //    existe sin la forma del IDE se DICE (se prometia sin mirar).
  var SinAgregado: TArray<string> := [];
  for var Agregado in TArray<string>.Create('Build', 'Clean', 'Make') do
  begin
    var Suf := IfThen(Agregado = 'Build', '', ':' + Agregado);
    var Lista: TAtributoXml;
    if TargetLlamado(Agregado, T) then
    begin
      if ListaDeAgregado(T, Lista) then
      begin
        var Escrita := Copy(Texto, Lista.Ini, Lista.Fin - Lista.Ini);
        if Escrita <> '' then
          Escrita := Escrita + ';';
        Texto := Copy(Texto, 1, Lista.Ini - 1) + Escrita +
          XmlEscapeEn(Nombre + Suf, Texto[Lista.Ini - 1]) + Copy(Texto, Lista.Fin, MaxInt);
      end
      else
        SinAgregado := SinAgregado + [Agregado];
    end
    else
    begin
      P := AlFinal;
      if P = 0 then
        Exit(MsgFmt(SR_GRUPO_FORMA_FMT, [TPath.GetFileName(AGroup), MsgText(SF_GRUPO_SIN_FINAL)]));
      Insert('    <Target ' + XmlAtributo('Name', Agregado) + '>' + NL + '        <CallTarget ' +
        XmlAtributo('Targets', Nombre + Suf) + '/>' + NL + '    </Target>' + NL, Texto, P);
    end;
  end;
  PatchSaveText(AGroup, Texto, Enc);
  Result := MsgFmt(SN_GRUPO_ANADIDO_FMT, [TPath.GetFileName(Proj), TPath.GetFileName(AGroup), Incl, Nombre]);
  if Length(SinAgregado) > 0 then
    Result := Result + #10 + MsgFmt(SN_GRUPO_SIN_AGREGADO_FMT, [string.Join(', ', SinAgregado)]);
end;

function QuitaProyectoDeGrupo(const AGroup, AProject: string): string;
var
  Enc, Texto, Proj: string;
  Nombres: TArray<string>;
  Cambios: TArray<TCambioTexto>;
  NDeps, Desde, Hasta: Integer;

  { Lo que ya se borra entero (el item y los targets del proyecto) no se toca
    otra vez: dos cambios sobre el mismo trozo lo corromperian. }
  function Borrado(AIndice: Integer): Boolean;
  begin
    Result := False;
    for var B in Cambios do
      if (B.Texto = '') and (AIndice >= B.Inicio) and (AIndice < B.Inicio + B.Largo) then
        Exit(True);
  end;

  procedure Cambia(AInicio, ALargo: Integer; const ATexto: string);
  var
    C: TCambioTexto;
  begin
    C.Inicio := AInicio;
    C.Largo := ALargo;
    C.Texto := ATexto;
    Cambios := Cambios + [C];
  end;

  { Los nombres de Nombres fuera de una lista de targets escrita (el
    Targets= de un CallTarget, el DependsOnTargets de un Target); la de
    dependencias que se queda vacia se va con su atributo. }
  procedure QuitaNombres(const AAtributo: TAtributoXml; AEsDependencia: Boolean);
  begin
    var Quedan: TArray<string> := [];
    var Quitados := 0;
    for var N in TrozosEscritos(Copy(Texto, AAtributo.Ini, AAtributo.Fin - AAtributo.Ini)) do
      if N.Trim = '' then
        Continue
      else if MatchText(XmlUnescape(N.Trim), Nombres) then
        Inc(Quitados)
      else
        Quedan := Quedan + [N.Trim];
    if Quitados = 0 then
      Exit;
    if (Length(Quedan) = 0) and AEsDependencia then
    begin
      // sin dependencias: fuera el atributo entero, con el blanco de delante
      var Ini := AAtributo.Abre;
      while (Ini > 1) and CharInSet(Texto[Ini - 1], [' ', #9, #13, #10]) do
        Dec(Ini);
      Cambia(Ini, AAtributo.Fin + 1 - Ini, '');
    end
    else
      Cambia(AAtributo.Ini, AAtributo.Fin - AAtributo.Ini, string.Join(';', Quedan));
  end;

begin
  // por EL analisis del grupo (TramosDeEtiqueta, AtributosDeTramo): eran
  // cuatro regex con el atributo el primero y entre comillas dobles
  Proj := TPath.GetFullPath(DprojDe(AProject));
  Texto := PatchLoadText(AGroup, Enc);
  Cambios := [];
  // 1. el item <Projects> (con su linea)
  for var T in TramosDeEtiqueta(Texto, 'Projects', True) do
    if MismoProyecto(AGroup, AtributoDeTramo(Texto, T, 'Projects', 'Include'), Proj) then
    begin
      ConSuLinea(Texto, T.Abre, T.Cierra, Desde, Hasta);
      Cambia(Desde, Hasta - Desde, '');
    end;
  if Length(Cambios) = 0 then
    Exit(MsgFmt(SN_GRUPO_NO_ESTABA_FMT, [TPath.GetFileName(Proj), TPath.GetFileName(AGroup)]));
  // 2. sus targets -los que construyen ESE proyecto: un <MSBuild> y nada
  //    mas, con o sin DependsOnTargets (el IDE lo escribe en los que dependen
  //    de otro, y la regex lo exigia sin nada)-, y se apuntan sus nombres
  Nombres := [];
  for var T in TramosDeEtiqueta(Texto, 'Target', True) do
  begin
    var Llamadas := TramosDentro(Texto, 'MSBuild', T, True);
    if (Length(Llamadas) <> 1) or
       (Copy(Texto, T.Ini, Llamadas[0].Abre - T.Ini).Trim <> '') or
       (Copy(Texto, Llamadas[0].Cierra, T.Fin - Llamadas[0].Cierra).Trim <> '') then
      Continue;
    if MismoProyecto(AGroup, AtributoDeTramo(Texto, Llamadas[0], 'MSBuild', 'Projects'), Proj) then
    begin
      ConSuLinea(Texto, T.Abre, T.Cierra, Desde, Hasta);
      Cambia(Desde, Hasta - Desde, '');
      Nombres := Nombres + [AtributoDeTramo(Texto, T, 'Target', 'Name')];
    end;
  end;
  // 3. esos nombres fuera de las listas de targets: los CallTarget de los
  //    agregados y el DependsOnTargets de los que dependian de el (si se
  //    queda, msbuild falla: el target no existe)
  for var T in TramosDeEtiqueta(Texto, 'Target', True) do
    if not Borrado(T.Abre) then
      for var At in AtributosDeTramo(Texto, T) do
        if SameText(At.Nombre, 'DependsOnTargets') then
          QuitaNombres(At, True);
  for var T in TramosDeEtiqueta(Texto, 'CallTarget', True) do
    if not Borrado(T.Abre) then
      for var At in AtributosDeTramo(Texto, T) do
        if SameText(At.Nombre, 'Targets') then
          QuitaNombres(At, False);
  // 4. y su ruta fuera de las <Dependencies> de los demas proyectos
  NDeps := 0;
  for var T in TramosDeEtiqueta(Texto, 'Dependencies') do
  begin
    var Escrito := Copy(Texto, T.Ini, T.Fin - T.Ini);
    if Borrado(T.Abre) or Escrito.Contains('<') then
      Continue;
    var Quedan: TArray<string> := [];
    var Quitados := 0;
    for var D in TrozosEscritos(Escrito) do
      if D.Trim = '' then
        Continue
      else if MismoProyecto(AGroup, XmlUnescape(D.Trim), Proj) then
        Inc(Quitados)
      else
        Quedan := Quedan + [D.Trim];
    if Quitados = 0 then
      Continue;
    Inc(NDeps, Quitados);
    if Length(Quedan) = 0 then
      Cambia(T.Abre, T.Cierra - T.Abre, '<Dependencies/>')
    else
      Cambia(T.Ini, T.Fin - T.Ini, string.Join(';', Quedan));
  end;
  PatchSaveText(AGroup, AplicaCambios(Texto, Cambios), Enc);
  Result := MsgFmt(SN_GRUPO_QUITADO_FMT, [TPath.GetFileName(Proj), TPath.GetFileName(AGroup),
    Length(Nombres), NDeps]);
end;

{ ================================================================ fix-references }

{ Para FicherosBajo: los ficheros que se llaman ANombre. }
function EsDeNombre(const ANombre: string): TFunc<string, Boolean>;
begin
  Result :=
    function(F: string): Boolean
    begin
      Result := SameFileName(TPath.GetFileName(F), ANombre);
    end;
end;

{ El borde del workspace visto desde ADir: la carpeta mas alta que esta sesion
  puede leer subiendo (el mismo freno que SubeCarpetas). }
function BordeDesde(const ADir: string): string;
var
  Dirs: TArray<string>;
begin
  Dirs := [];
  SubeCarpetas(ADir, Dirs);
  if Length(Dirs) = 0 then
    Result := ADir
  else
    Result := Dirs[High(Dirs)];
end;

function ArreglaReferenciasNucleo(const AProject: string): string;
var
  Base, Borde, Abs, Dpr, Dproj, Motivo: string;
  Hechos, Sin, Varios, RutasFaltan, Fallidas, Saltadas: TArray<string>;
begin
  Hechos := [];
  Fallidas := [];
  Saltadas := [];
  Sin := [];
  Varios := [];
  RutasFaltan := [];
  if SameText(TPath.GetExtension(AProject), '.groupproj') then
  begin
    Base := TPath.GetDirectoryName(TPath.GetFullPath(AProject));
    Borde := BordeDesde(Base);
    var Mapa := TDictionary<string, string>.Create;
    try
      for var I in ProyectosDeGrupo(AProject) do
      begin
        Abs := RutaDeInclude(AProject, I);
        // lo de fuera de lo que esta sesion puede leer ni se mira ni se
        // dice (ni si existe), como en el view de un grupo; ni lo que no se
        // resuelve
        if (Abs = '') or (ReadPathDenied(Abs) <> '') or TFile.Exists(Abs) then
          Continue;
        var Cands := FicherosBajo(Borde, EsDeNombre(TPath.GetFileName(I)), 5, Saltadas);
        if Length(Cands) = 1 then
        begin
          Mapa.AddOrSetValue(NormPath(Abs), Cands[0]);
          Hechos := Hechos + [I + ' -> ' + IncludeFor(AProject, Cands[0])];
        end
        else if Length(Cands) = 0 then
          Sin := Sin + [I]
        else
          Varios := Varios + [I];
      end;
      if Mapa.Count > 0 then
        ReapuntaGrupo(AProject, Base,
          function(A: string): string
          begin
            if not Mapa.TryGetValue(NormPath(A), Result) then
              Result := '';
          end);
    finally
      Mapa.Free;
    end;
  end
  else
  begin
    Motivo := ResolveProjectPair(AProject, Dpr, Dproj);
    if Motivo <> '' then
      Exit(Motivo);
    Base := TPath.GetDirectoryName(Dpr);
    Borde := BordeDesde(Base);
    for var PU in ProjectUnits(Dpr, False) do
    begin
      if PU.Include = '' then
        Continue;
      Abs := RutaDeInclude(Dpr, PU.Include);
      if (Abs = '') or (ReadPathDenied(Abs) <> '') or TFile.Exists(Abs) then
        Continue;
      var Cands := FicherosBajo(Borde, EsDeNombre(TPath.GetFileName(PU.Include)), 5, Saltadas);
      if Length(Cands) = 1 then
      begin
        // solo cuenta si se hizo: se contaba el intento
        var Resp := RenameProjectUnit(Dpr, Abs, Cands[0]);
        if Reapuntada(Resp) then
          Hechos := Hechos + [PU.Include + ' -> ' + IncludeFor(Dpr, Cands[0])]
        else
          Fallidas := Fallidas + [PU.Include + ': ' + PrimerTrozo(Resp, [#10])];
      end
      else if Length(Cands) = 0 then
        Sin := Sin + [PU.Include]
      else
        Varios := Varios + [PU.Include];
    end;
    // Las rutas de busqueda que no existen: se dicen (no hay nombre que buscar)
    if TFile.Exists(Dproj) then
    begin
      var Enc: string;
      var Xml := PatchLoadText(Dproj, Enc);
      for var R in RutasDeBusqueda(Dproj, Xml) do
        if ((R.Carpeta = '') or ((ReadPathDenied(R.Carpeta) = '') and
            not TDirectory.Exists(R.Carpeta))) and
           not RutaEnLista(R.Escrita, RutasFaltan) then
          RutasFaltan := RutasFaltan + [R.Escrita];
    end;
  end;
  Result := MsgFmt(SN_ARREGLA_FMT, [TPath.GetFileName(AProject), Length(Hechos),
    Length(Sin), Length(Varios)]);
  if Length(Hechos) > 0 then
    Result := Result + #10 + MsgFmt(SF_USES_REAPUNTADAS_FMT, [string.Join('; ', Hechos)]);
  if Length(Sin) > 0 then
    Result := Result + #10 + MsgFmt(SF_USES_NO_ENCONTRADAS_WORKSPACE_FMT, [string.Join('; ', Sin)]);
  if Length(Varios) > 0 then
    Result := Result + #10 + MsgFmt(SN_ARREGLA_VARIOS_FMT, [string.Join('; ', Varios)]);
  if Length(RutasFaltan) > 0 then
    Result := Result + #10 + MsgFmt(SN_ARREGLA_RUTAS_FMT, [string.Join('; ', RutasFaltan)]);
  if Length(Fallidas) > 0 then
    Result := Result + #10 + MsgFmt(SN_ARREGLA_FALLIDAS_FMT, [string.Join('; ', Fallidas)]);
end;

function ArreglaReferencias(const AProject: string): string;
begin
  // un proyecto: cada unidad la re-apunta RenameProjectUnit con SU cerrojo, y
  // con la raiz de su designer juzgada antes de cogerlo; con uno alrededor de
  // todo, el motor se juzgaba con todas las escrituras del servidor paradas
  // (V177 de la 1.23.1, medido)
  if not SameText(TPath.GetExtension(AProject), '.groupproj') then
    Exit(ArreglaReferenciasNucleo(AProject));
  // un grupo, con el cerrojo de las ediciones, como toda reescritura de
  // proyectos (corria sin el)
  EnterFileEdit;
  try
    Result := ArreglaReferenciasNucleo(AProject);
  finally
    LeaveFileEdit;
  end;
end;

end.
