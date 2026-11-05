unit Lsp.ProjectUnits;

{ The ONE place that registers a unit in a Delphi project - what the IDE does
  on "Add to project" / "Remove from project" / rename:

  - .dpr  : the "Name in 'path.pas' (Form)" entry in the program's uses
            clause, plus `Application.CreateForm(TForm, Form)` for forms and
            data modules (never for frames).
  - .dproj: the <DCCReference Include="path.pas"> item (with <Form>,
            <FormType>, <DesignClass> for designer units), the IDE's shape.

  delphi_create, delphi_config add-unit/remove-unit, delphi_delete and
  delphi_move all go through here, so the agent never edits the .dpr/.dproj
  by hand. Edits are curated (only the affected entry moves), encoding-
  preserving and backed up through Lsp.Patch. }

interface

uses
  System.SysUtils, System.Classes, System.JSON,
  Lsp.DesignerMeta; // TRaizDeDiseno: lo que es la raiz de un designer para el IDE

type
  { What a .pas is to the project: a plain unit or a designer unit. }
  TUnitInfo = record
    UnitName: string;    // from the `unit X;` header (dotted allowed)
    PasPath: string;     // absolute
    Designer: string;    // '' | absolute path of the .dfm/.fmx
    FormName: string;    // variable name (Form1), '' for plain units
    ClassName: string;   // TForm1
    Ancestor: string;    // TForm / TDataModule / TFrame / ...
    FormType: string;    // 'dfm' | 'fmx' | ''
    // lo que es la raiz para el IDE y lo que escribe en su <DesignClass> y en
    // el Form: X de la entrada del .dpr ('' en una form); los pone
    // JuzgaRaizDeDiseno, no InspectUnit: remove-unit no los necesita y su juez
    // puede esperar a la tabla y arrancar el motor. rdDesconocida, con el
    // porque en RaizSinJuez, si no se pudo juzgar
    Raiz: TRaizDeDiseno;
    DesignClass: string;
    RaizSinJuez: string;
    function IsDesigner: Boolean;
    function NeedsCreateForm: Boolean; // forms and data modules, not frames
  end;
  PUnitInfo = ^TUnitInfo;

  TProjectUnit = record
    UnitName: string;
    Include: string;     // as written in the .dpr ('Unit1.pas', 'src\X.pas')
    FormName: string;    // from the {Form} comment, '' for plain units
    InDproj: Boolean;    // has its <DCCReference>
  end;

{ EL escritor de la sentencia que crea un form al arrancar:
  Application.CreateForm(TForm1, Form1); su lector es CreateFormsDe. }
function LineaCreateForm(const AClase, AVariable: string): string;

{ Resolves a .dpr or .dproj to the pair (both absolute). Either may be given.
  Returns '' when OK, else a refusal text. }
function ResolveProjectPair(const AProject: string; out ADpr, ADproj: string): string;

{ Inspects a .pas (header, designer pair, class/ancestor/variable). Returns ''
  when OK, else a refusal text (no header, header/file mismatch...). }
function InspectUnit(const APasPath: string; out AInfo: TUnitInfo): string;

{ Lo que es para el IDE la raiz del designer de AInfo (ya inspeccionada):
  AInfo.Raiz y AInfo.DesignClass, por sus jueces en orden. Quien la CREO
  (delphi_create) lo sabe: ARaizDelCreador, y el nombre de su fuente. Si no,
  el registro del IDE (ARegistro, de RegistroDelIde), que es exacto - el
  IDE nombra a veces la base del usuario de un modulo (TdmlMainComp) -; y
  sin registro, la clase de la unidad por su cadena contra la tabla de su
  marco (Lsp.DesignerMeta.RaizDeDiseno), esperando AEsperaMs a una tabla
  que se esta generando. Lo que no se sepa, rdDesconocida con el porque en
  AInfo.RaizSinJuez. Era una lista de nombres y un sufijo (TBaseFrame =
  frame) que fallaba en todo modulo cuya cadena sale de la unidad: 39 de las
  654 unidades con designer de los Samples (medido el 18-oct-2026). Con el
  cerrojo de escritura cogido, AEsperaMs = 0: la tabla se espera FUERA, como
  la del disenador (delphi_config add-unit), que dentro se paraban todas las
  ediciones del servidor mientras se generaba. Nunca lanza. }
procedure JuzgaRaizDeDiseno(var AInfo: TUnitInfo; const ARegistro: string;
  AEsperaMs: Cardinal; ARaizDelCreador: TRaizDeDiseno = rdDesconocida; APrevia: PUnitInfo = nil);
{ La unidad APasPath inspeccionada y su raiz juzgada por su CADENA (el paso 3
  de JuzgaRaizDeDiseno), FUERA del cerrojo de escritura: la cadena puede
  arrancar el motor, y dentro paraba TODAS las escrituras del servidor (V177
  de la 1.23.1, medido: 1,91 s de los 2,33 de un add-unit). Solo cuando los
  pasos 1 y 2 no contestan - ni el creador ni el registro del IDE de
  ARegistroDe en AProject -: con ellos no hay motor, y juzgar antes lo
  arrancaba (medido: un fix-references de 0,13 s pasaba a 2,34, con el cerrojo
  cogido). Quien escribe la pasa como APrevia a JuzgaRaizDeDiseno, que la toma
  si es de la misma unidad. Vacia si no hace falta o no se pudo. Nunca lanza. }
function PrejuzgaRaiz(const AProject, APasPath, ARegistroDe: string;
  ARaizDelCreador: TRaizDeDiseno = rdDesconocida): TUnitInfo;
{ EL lector de lo que es la raiz de un designer (ARuta, un .dfm/.fmx): su
  unidad (UnidadDeDesigner) inspeccionada y, si su designer es ese fichero (un
  X.fmx al lado de un X.dfm: la unidad es del .dfm), JuzgaRaizDeDiseno - su
  cadena primero, sin esperar a la tabla, y si no llega, el registro del IDE
  en un .dproj que la lista. rdDesconocida si no se sabe (sin .pas, una unidad
  que no se deja leer). Lo preguntan preview (Lsp.FormRender.RaizParaElRender)
  y los StyleLookup de un frame, que toma el StyleBook de la form que lo aloja
  (Lsp.Styles.LookupsDeDesigner, V151 de la 1.23.1). Nunca lanza. }
function RaizDeDesigner(const ARuta: string): TRaizDeDiseno;
{ El <DCCReference> con el que el IDE registro APasPath como designer (con
  su <Form>), por la RUTA que resuelve su Include desde la carpeta de cada
  .dproj: primero en ADproj (el proyecto que se toca; '' ninguno), luego en
  los que la listan (ProjectsUsingUnit). '' si ninguno. Nunca lanza. }
function RegistroDelIde(const APasPath, ADproj: string): string;
{ EL escritor de una <DCCReference> del .dproj, como la escribe el IDE: a
  secas para una unit cualquiera, y con su <Form>, <FormType> y <DesignClass>
  para un designer (AInfo.IsDesigner con FormName). Lo usan add-unit, el
  rename y delphi_create (que la componia a mano, dos veces; revisor del
  21-oct-2026). Compone en CRLF. }
function DccRefXml(const AInfo: TUnitInfo; const AInclude: string): string;

{ Adds the unit to the .dpr uses (+ CreateForm) and the .dproj. Idempotent:
  an entry already present is left alone and reported. ARaizDelCreador: what
  its root is, when the caller wrote it (delphi_create); otherwise it is
  judged (JuzgaRaizDeDiseno) with the table as it is - who waits for it does
  so before taking the write lock. }
function AddProjectUnit(const AProject, APasPath: string;
  ARaizDelCreador: TRaizDeDiseno = rdDesconocida): string;

{ Takes the unit out of the .dpr (uses + CreateForm) and the .dproj. The
  file itself stays on disk. }
function RemoveProjectUnit(const AProject, APasPath: string;
  AFileGoesToo: Boolean = False): string;

{ Re-points an existing entry to where its file is now (fix-references: the
  file found by its name; the file's header decides the unit name). }
function RenameProjectUnit(const AProject, AOldPasPath, ANewPasPath: string): string;

{ Anade nombres de paquete a la clausula requires de un .dpk (la crea antes
  de contains / end. si no existe). Idempotente: los que ya estan no se
  repiten. Es lo que el IDE ofrece tras un build con W1033. }
function AddPackageRequires(const AProject, ANames: string): string;
{ La clausula requires de un paquete, leida sobre el texto con los
  comentarios en blanco (las posiciones son las del texto): True si la hay,
  con sus nombres y donde esta (AIni 1-based y ALargo). La leen quien la
  amplia (AddPackageRequires) y el scaffold (de que marco es un paquete). }
function ClausulaRequires(const ATexto: string; out ANombres: TArray<string>;
  out AIni, ALargo: Integer): Boolean;

{ The units a project lists (from the .dpr uses, cross-checked with the
  .dproj). Never raises; empty on unreadable input. }
function ProjectUnits(const AProject: string): TArray<TProjectUnit>; overload;
{ ANeedDproj=False skips the .dproj read (InDproj is then True): for callers
  that only need the .dpr's list. }
function ProjectUnits(const AProject: string; ANeedDproj: Boolean): TArray<TProjectUnit>; overload;

{ Adds a "units" array to AReturn (for delphi_config view). }
procedure AddUnitsView(const ADproj: string; AReturn: TJSONObject);

{ Los proyectos (.dpr/.dpk) que listan APasPath por su ruta, subiendo desde su
  carpeta hasta el borde de la jaula y en las carpetas de al lado de cada
  nivel (SitiosDeProyectos). Lo pregunta RegistroDelIde (el <DCCReference> de
  un designer); hasta V19 tambien delete y move, para re-apuntarlos. }
function ProjectsUsingUnit(const APasPath: string): TArray<string>;

type
  TFormDelProyecto = record
    Clase, Designer, Unidad: string; // su clase raiz, su .dfm o .fmx, y su unidad como la lista el proyecto
  end;

{ Los forms y frames que AProyecto (.dpr, .dpk) lista con raiz de una de AClases,
  con la extension AExt y que la sesion puede leer. De cada entrada se mira su
  comentario de form, T + nombre como la llama el IDE, y solo si casa se abre el
  form y manda su raiz: quien pregunta por una clase de un paquete que no esta no
  lee el proyecto entero. Lo que falte o no se lea no sale. Puede lanzar, como
  ProjectUnits, si el proyecto no se deja leer. Lo piden el render (un ancestro o
  un frame de otra carpeta), insert (un frame) y delphi_create (un ancestro). }
function FormsDeLasClases(const AProyecto: string; const AClases: TArray<string>;
  const AExt: string): TArray<TFormDelProyecto>;

{ True si el .dpr o el .dpk de AProyecto (un .dproj se mira por su fuente
  principal) nombra APasPath por su RUTA (in '...'): la unidad es de ese
  proyecto. EL juez de ProjectsUsingUnit y el de que proyecto sirve a una
  unidad (Lsp.Session.FindDproj): el nombre en el texto del .dproj casaba
  con la copia de al lado (medido el 18-oct-2026). Lanza, como
  UnitsParaBuscar, si el proyecto no se deja leer. AConSuFuente: su fuente
  principal cuenta tambien como suya - el proyecto de un .dpr es el suyo, y
  con varios .dproj en su carpeta se le daban los ajustes del primero
  (revision del 18-oct-2026). }
function ProyectoListaUnidad(const AProyecto, APasPath: string;
  AConSuFuente: Boolean = False): Boolean;

{ Paquetes (.dpk) del workspace cuya clausula contains lista la unit
  AUnitName, subiendo desde la carpeta de ADpkPath hasta el borde de la jaula
  (el MISMO buscador que ProjectsUsingUnit); el propio ADpkPath no cuenta.
  Es la pista de requires de delphi_build cuando la unit no esta en ningun
  BPL de la instalacion (punto 8 de Hermes; David, 24-sep-2026): solo pista,
  sin comprobar dcp ni instalacion - compilar el paquete es cosa del agente. }
function WorkspacePackagesWithUnit(const ADpkPath, AUnitName: string): TArray<string>;

{ La cabecera "unit X;" de un .pas: el nombre como lo lee dcc ('unit A . B;'
  es A.B), donde empieza (1-based) y cuanto mide lo escrito (lo que reescribe
  quien mueve), fuera de comentarios y con las directivas que admite detras
  (platform, deprecated, library, experimental). False si no la hay. UN
  lector: InspectUnit la leia con una regex que solo casaba "unit X;" y
  delphi_move la reescribia con otra igual - "unit X platform;" ni se
  registraba ni se reescribia, y MOVE-015 decia que si (decima revision). }
function CabeceraDeUnit(const ASrc: string; out ANombre: string;
  out AInicio, ALargo: Integer): Boolean;

type
  { EL juez de "es la misma unidad" en un uses, como lo resuelve dcc (V79 de
    la 1.23.1): un nombre TAL CUAL si esa unidad existe - del proyecto (la
    lista su fuente principal, o esta en su carpeta o en su search path: V107)
    o de la biblioteca (Lsp.Discovery.UnidadesDeLaBiblioteca) -; si no, con
    el primero de los ambitos del
    proyecto (su DCC_Namespace, ConfigFabricator.AmbitosDelProyecto) con el
    que exista: en un proyecto VCL StdCtrls es Vcl.StdCtrls. Medido con dcc:
    adduses=StdCtrls sobre un uses con Vcl.StdCtrls daba E2004 "Identifier
    redeclared" (26-oct), y un proyecto con SU unidad Messages compila "uses
    Winapi.Messages, Messages" (27-oct): el nombre tal cual va primero. Habia
    tres reglas: el nombre exacto (LocateEntry: adduses, add-unit, removeuses,
    el renombrado), un bucle propio en el .dpr y el ultimo trozo de CUALQUIER
    ambito (UnidadEnUses: insert y check-binding). }
  TResolutorDeUnidades = record
    Proyecto: string; // el .dproj de donde salen los ambitos ('' si no hay)
    Ambitos: TArray<string>;
    // las que dcc encuentra en el proyecto, por su clave (ClaveDeIdentificador):
    // las que lista su fuente principal y las de su carpeta y su search path
    Propias: TArray<string>;
    Biblioteca: TArray<string>; // las de la biblioteca (UnidadesDeLaBiblioteca)
    { El nombre con el que dcc la encuentra; tal cual si no la encuentra }
    function Resuelve(const ANombre: string): string;
    function MismaUnidad(const A, B: string): Boolean;
    { AUnidad ya esta en esa lista de un uses (o de nombres) }
    function EnUses(const AUses: TArray<string>; const AUnidad: string): Boolean;
  end;

{ El juez para el fuente AFuente (un .pas, o la fuente principal de un
  proyecto): los ambitos y las unidades de SU proyecto (FindDproj de la
  sesion; el .dproj de al lado para un .dpr o un .dpk); sin proyecto, los
  ambitos del compilador. ADeUnFichero: la unidad de un FICHERO que se nombra
  (remove-unit, el renombrado), que existe - es ese fichero - y no se resuelve
  por los ambitos. No lanza: lo que no se lee no cuenta. }
function ResolutorDeUnidades(const AFuente: string; const ADeUnFichero: string = ''): TResolutorDeUnidades;

{ adduses de delphi_edit: nombres de unit al uses de una seccion (interface o
  implementation) de un .pas; la clausula la escribe el motor. }
function AddUsesToUnit(const APasPath: string; const ANames: TArray<string>;
  const ASection: string): string;
{ El nucleo de adduses sobre un TEXTO: ANames (identificadores ya
  validados) entran en el uses de ASec (interface|implementation) y AText
  sale con la clausula reescrita. '' = hecho, o la negativa (sin esa
  seccion, una clausula en ramas IFDEF). AFaltan entran; AYaEstan ya
  estaban; AEnOtra estan en la otra seccion y no entran (E2004); ACreada,
  la clausula nacio. AFichero, solo para los mensajes. "Ya esta" lo dice
  AResolutor, el juez de dcc (V79): StdCtrls ya esta si esta Vcl.StdCtrls,
  y dos nombres de la misma unidad en ANames entran una vez. }
function UsesConUnidades(var AText: string; const ANames: TArray<string>;
  const ASec, AFichero: string; const AResolutor: TResolutorDeUnidades;
  out AFaltan, AYaEstan, AEnOtra: TArray<string>;
  out ACreada: Boolean): string;
{ removeuses de delphi_edit: la inversa; la clausula se va entera si queda vacia. }
function RemoveUsesFromUnit(const APasPath: string; const ANames: TArray<string>;
  const ASection: string): string;

{ La ruta de APas vista desde la carpeta de ADpr, en la forma que escribe el
  IDE (Sub\X.pas, ..\..\shared\X.pas; absoluta solo en otra unidad). EL
  nombrador de rutas relativas: las units de un proyecto, los proyectos de
  un grupo, los search paths y las directivas que re-apunta una mudanza. }
function IncludeFor(const ADpr, APas: string): string;
{ La inversa: la ruta COMPLETA de lo que un .dpr lista como AInclude (Sub\X.pas,
  ..\shared\X.pas, o absoluta), vista desde su carpeta. EL lector de lo que
  escribe IncludeFor. '' si no se resuelve (Lsp.Rutas.RutaDesde: "X:y" de
  otra unidad, lo que no es una ruta); "\x" es de la unidad del .dpr, la de
  la carpeta en la que corre el compilador. }
function RutaDeInclude(const ADpr, AInclude: string): string;
{ LA forma en que aqui se comparan dos rutas (la larga, salvo un UNC ajeno o
  un prefijo de dispositivo) y su clave del disco: con ellas se juzga
  "dentro de" y "el mismo fichero". Si el Include AInclude de AFichero (un
  .dpr, .dproj o .groupproj) es APath. Y la subida por carpetas desde ADesde
  hasta el borde de la jaula, acumulando en ADirs sin repetir. Publicas para
  Lsp.Mudanzas, que vivia aqui (B6 de la 1.28). }
function FormaDeComparar(const P: string): string;
function NormPath(const P: string): string;
function MismoInclude(const AFichero, AInclude, APath: string): Boolean;
procedure SubeCarpetas(const ADesde: string; var ADirs: TArray<string>);
{ Lo que el compilador LEE por el in '...' de la fuente principal de un
  proyecto (el uses de un .dpr, el contains de un .dpk), en TODAS sus ramas:
  por cada unidad, su nombre (AUnidades), la ruta como va escrita (AEscritas)
  y como la abre dcc (ARutas, RutaDeInclude; '' si no se resuelve: una "X:y"
  de otra unidad). '' o la negativa de una clausula con una entrada que no se
  lee (USES-026: su ';' no es el suyo, y lo que dcc lea no se sabe). EL
  lector de las entradas (LeeEntradaDeUses), el de los que las escriben; la
  pregunta de la puerta del build (V14 de la 1.23: un uses X in 'fuera.pas'
  compilaba). Lanza si el fichero no se lee. }
function LecturasDelIn(const AFuente: string; out AUnidades, AEscritas, ARutas: TArray<string>): string;

type
  { Una directiva que mete un FICHERO en el build, con la posicion (1-based)
    y el largo de su ruta en el texto, para poder reescribirla en su sitio. }
  TDirectivaFichero = record
    Texto: string;          // la directiva entera: {$I ..\x.inc}
    Ruta: string;           // la ruta, sin comillas
    Comilla: Char;          // con la que va escrita, o #0 si va sin
    Inicio, Largo: Integer; // donde esta la ruta en el texto
  end;

{ Las directivas $I/$INCLUDE, $R/$RESOURCE y $L/$LINK de un fuente, sin
  comodines (R *.res) ni interruptores; de R a.res a.rc las dos (el .rc es la
  segunda). EL
  lector: la jaula del build (Lsp.BuildRunner) y la mudanza lo comparten. }
function DirectivasDeFichero(const ATexto: string): TArray<TDirectivaFichero>;

implementation

uses
  System.IOUtils,
  System.StrUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  System.Character,
  Lsp.JuicioDeForms,
  Lsp.Texts,
  Lsp.Guard,
  System.Generics.Defaults,
  Lsp.DesignerBin, // ReadPathDenied: hasta donde se puede subir buscando un .dpr
  Lsp.DesignerForma, // LineaDeObjeto: la raiz del designer
  Lsp.Dproj,       // XmlUnescape: el lector de la casa
  Lsp.References,
  Lsp.NetDrives,  // SkipIdeArtifacts: una mudanza no entra en artefactos
  Lsp.Pascal,
  Lsp.PascalDecl, // EL lector de clases y LA cadena de ancestros
  Lsp.Rutas,
  Lsp.TodoONada,
  Lsp.ConfigFabricator, // AmbitosDelProyecto y los del compilador: el juez de un uses
  Lsp.Discovery,        // UnidadesDeLaBiblioteca: la que existe tal cual
  Lsp.Session,          // FindDproj: el proyecto de un fuente
  Lsp.Lineas,
  Lsp.Puertas,
  // la ultima: lo suyo pesaba mas que lo de cualquier otra unidad cuando
  // vivia aqui, y asi sigue
  Lsp.ClausulaUses;

{ TUnitInfo }

function TUnitInfo.IsDesigner: Boolean;
begin
  Result := Designer <> '';
end;

function TUnitInfo.NeedsCreateForm: Boolean;
begin
  Result := IsDesigner and (FormName <> '') and (Raiz <> rdFrame);
end;

{ ---- paths ---- }

{ LA forma en que aqui se comparan dos rutas, la de NormPath sin su clave:
  con ella se juzga "dentro de" Y se corta (Trasladada). }
function FormaDeComparar(const P: string): string;
begin
  // la forma LARGA (Lsp.Rutas.LongCanonical): UPROVE~1.PAS y
  // UProveedorModelo.pas son el mismo fichero (sexta revision). Salvo un
  // UNC que no es de ningun sitio declarado: estas rutas salen de lo que
  // dice un .dpr, y alargarla abria SMB hacia ese host (octava revision)
  // ...ni uno con prefijo de dispositivo (\\?\UNC\host\...): la pregunta de
  // todos (Lsp.Guard.RutaSinTocarElDisco; novena revision)
  if RutaSinTocarElDisco(P) then
    Exit(P);
  Result := LongCanonical(P);
end;

function NormPath(const P: string): string;
begin
  // ...y por la clave del disco (ClaveDeRuta): .ToLower junta lo que NTFS
  // separa (V105 de la 1.23.1)
  Result := ClaveDeRuta(FormaDeComparar(P));
end;

function ResolveProjectPair(const AProject: string; out ADpr, ADproj: string): string;
begin
  Result := '';
  ADpr := '';
  ADproj := '';
  if AProject.Trim = '' then
    Exit(MsgText(SR_UNIT_NEED_PROJECT));
  if not EsProyectoOSuFuente(AProject) then
    Exit(MsgFmt(SR_UNIT_PROJECT_EXT_FMT, [TPath.GetFileName(AProject)]));
  // Un paquete es un proyecto: su fuente principal es el .dpk (con clausula
  // contains en vez de uses) y el .dproj es el mismo. Desde un .dproj se
  // decide por lo que hay en disco: el .dpr si existe, si no el .dpk - la
  // regla de DprDe, que es quien la sabe (P9 de la segunda revision de la
  // 1.17.0). (Hermes, bateria 1.2 caso 1: sin esto un paquete propio no se
  // podia trabajar por tools.)
  ADpr := DprDe(TPath.GetFullPath(AProject));
  ADproj := DprojDe(TPath.GetFullPath(AProject)); // el nombrador de la casa (Lsp.Dproj)
  if not TFile.Exists(ADpr) then
    Exit(NoEsFichero(ADpr, MsgFmt(SR_UNIT_NO_DPR_FMT, [ADpr])));
  // a missing .dproj is tolerated: the .dpr alone still builds with dcc, and
  // the IDE regenerates a .dproj on open. The dproj edits are then skipped.
end;

{ Relative path from the .dpr folder to APas, with backslashes - the form the
  IDE writes in both files. Outside the tree: absolute (the IDE does the same
  for ..\ up to a point; absolute is unambiguous). }
function IncludeFor(const ADpr, APas: string): string;
var
  Base, Full: string;
begin
  Base := IncludeTrailingPathDelimiter(TPath.GetDirectoryName(TPath.GetFullPath(ADpr)));
  Full := TPath.GetFullPath(APas);
  // "dentro de" por EL juez de rutas (Lsp.Rutas, el del disco): con
  // .ToLower.StartsWith la unidad de Pk se escribia 'U.pas' junto a un .dpr de
  // P<Kelvin>, que es otra carpeta (V81 de la 1.23.1, medido)
  if TrozoBajo(Base, Full, Result) then
    Exit; // y lo de dentro, por SU corte
  if SameFileName(TPath.GetPathRoot(Full), TPath.GetPathRoot(Base)) then
    Result := ExtractRelativePath(Base, Full) // ..\..\shared\X.pas, the IDE's form
  else
    Result := Full; // another drive: no relative form exists
end;

function RutaDeInclude(const ADpr, AInclude: string): string;
begin
  Result := '';
  try
    Result := RutaDesde(TPath.GetDirectoryName(TPath.GetFullPath(ADpr)), AInclude);
  except
    // un .dpr sin ruta valida no tiene carpeta desde la que leer
  end;
end;

{ El Include de un .dpr, .dproj o .groupproj nombra APath: por EL resolutor
  (RutaDeInclude). Tres sitios lo resolvian con TPath.Combine, que deja
  '\Comun\U.pas' o 'D:Comun\U.pas' al directorio del PROCESO: el motor, move,
  delete y el registro del IDE no veian que el proyecto lista la unidad, y
  fix-references si (V204 de la 1.23.1). }
function MismoInclude(const AFichero, AInclude, APath: string): Boolean;
begin
  var Full := RutaDeInclude(AFichero, AInclude);
  Result := (Full <> '') and (NormPath(Full) = NormPath(APath));
end;

{ ---- unit inspection ---- }

function DesignerHeaderName(const ADesigner: string; out AName, AClass: string): Boolean;
var
  B: TBytes;
  Enc, Clave, Nombre, Clase: string;
  Lines: TArray<string>;
begin
  Result := False;
  AName := '';
  AClass := '';
  // por LA puerta de leer, como el texto de abajo (PatchLoadText): el designer
  // es de la jaula
  B := LeeBytes(ADesigner, [ltJaula]);
  if Length(B) < 4 then
    Exit;
  // Un designer BINARIO tambien tiene nombre y clase: se lee al vuelo como
  // texto (Lsp.DesignerBin); si esta danado, no hay cabecera que leer.
  if IsBinaryDesignerBytes(B) then
  begin
    if DesignerBinaryToText(B, Enc) <> '' then
      Exit;
    Lines := SplitToLines(Enc); // el troceador de todos: un CR suelto es salto
  end
  else
    Lines := SplitToLines(PatchLoadText(ADesigner, Enc));
  // EL lector de la raiz (Lsp.DesignerForma), el del renderizador tambien;
  // aqui, la raiz nunca es un frame inline y siempre tiene nombre
  Result := LineaRaizDeDesigner(Lines, Clave, Nombre, Clase) and
    (Clave <> 'inline') and (Nombre <> '');
  if Result then
  begin
    AName := Nombre;
    AClass := Clase;
  end;
end;

{ ---- lo que es la raiz de un designer para el IDE ---- }

function RegistroDelIde(const APasPath, ADproj: string): string;

  function EnUno(const ADprojDe: string): string;
  var
    Xml, Enc: string;
  begin
    Result := '';
    if (ADprojDe = '') or not TFile.Exists(ADprojDe) then
      Exit;
    Xml := PatchLoadText(ADprojDe, Enc);
    // por EL analisis del .dproj, y por la ruta que resuelve el Include (como
    // ProyectoListaUnidad), no por como va escrito
    // EL resolutor del Include (RutaDeInclude): un TPath.Combine resolvia
    // '\Comun\U.pas' o 'D:Comun\U.pas' contra el PROCESO del servidor (V204)
    for var T in TramosDeEtiqueta(Xml, 'DCCReference', True) do
      if MismoInclude(ADprojDe, AtributoDeTramo(Xml, T, 'DCCReference', 'Include'), APasPath) then
      begin
        Result := Copy(Xml, T.Abre, T.Cierra - T.Abre);
        if Length(AllTagValues(Result, 'Form')) = 0 then
          Result := ''; // la registro como unit sin designer
        Exit;
      end;
  end;

begin
  Result := '';
  try
    Result := EnUno(ADproj);
    if Result <> '' then
      Exit;
    for var P in ProjectsUsingUnit(APasPath) do
    begin
      Result := EnUno(DprojDe(P));
      if Result <> '' then
        Exit;
    end;
  except
    Result := ''; // un proyecto que no se deja leer: sin registro
  end;
end;

procedure JuzgaRaizDeDiseno(var AInfo: TUnitInfo; const ARegistro: string;
  AEsperaMs: Cardinal; ARaizDelCreador: TRaizDeDiseno; APrevia: PUnitInfo);
var
  M: TMetaTable;
  Falta: TFaltaTabla;
  Clase, Corte: string;
  Fmx: Boolean;
begin
  AInfo.Raiz := rdDesconocida;
  AInfo.DesignClass := '';
  AInfo.RaizSinJuez := '';
  if not AInfo.IsDesigner or (AInfo.FormName = '') then
    Exit; // nada de designer que escribir
  Fmx := EsDesignerFmx(AInfo.Designer);
  // 1) quien la creo sabe lo que escribio; el nombre, el de su fuente
  if ARaizDelCreador <> rdDesconocida then
  begin
    AInfo.Raiz := ARaizDelCreador;
    if ARaizDelCreador = rdFrame then
      AInfo.DesignClass := DesignClassDeFrame(Fmx)
    else if ARaizDelCreador = rdModulo then
      AInfo.DesignClass := UltimoTrozo(AInfo.Ancestor);
    Exit;
  end;
  // 2) lo que el IDE ya escribio: exacto
  if ARegistro <> '' then
  begin
    for var V in AllTagValues(ARegistro, 'DesignClass') do
    begin
      AInfo.DesignClass := V.Trim;
      Break;
    end;
    AInfo.Raiz := RaizDeDesignClass(AInfo.DesignClass);
    Exit;
  end;
  // 3) la clase de la unidad por su cadena, contra la tabla de su marco: la
  // que se juzgo FUERA del cerrojo (PrejuzgaRaiz), si es de esta misma unidad
  // - la misma ruta, clase, ancestro y designer -; si cambio entre medias, aqui
  // (V177 de la 1.23.1)
  if (APrevia <> nil) and (APrevia.Raiz <> rdDesconocida) and
     SameFileName(APrevia.PasPath, AInfo.PasPath) and SameFileName(APrevia.Designer, AInfo.Designer) and
     SameText(APrevia.ClassName, AInfo.ClassName) and SameText(APrevia.Ancestor, AInfo.Ancestor) then
  begin
    AInfo.Raiz := APrevia.Raiz;
    AInfo.DesignClass := APrevia.DesignClass;
    Exit;
  end;
  try
    M := MetaTable(Fmx, Falta, AEsperaMs);
    if M = nil then
      AInfo.RaizSinJuez := Falta.Razon
    else
    begin
      AInfo.Raiz := RaizDeDiseno(M, AInfo.PasPath, '', AInfo.ClassName, Clase, Corte);
      if AInfo.Raiz = rdDesconocida then
        AInfo.RaizSinJuez := MsgFmt(SF_UNIT_RAIZ_CORTE_FMT, [Corte])
      else
        AInfo.DesignClass := Clase;
    end;
  except
    on E: Exception do
    begin
      AInfo.Raiz := rdDesconocida;
      AInfo.DesignClass := '';
      AInfo.RaizSinJuez := E.Message;
    end;
  end;
end;

function PrejuzgaRaiz(const AProject, APasPath, ARegistroDe: string;
  ARaizDelCreador: TRaizDeDiseno): TUnitInfo;
var
  Dpr, Dproj: string;
begin
  Result := Default(TUnitInfo);
  // los pasos 1 y 2 contestan sin la cadena: nada que juzgar antes
  if ARaizDelCreador <> rdDesconocida then
    Exit;
  try
    if (ResolveProjectPair(AProject, Dpr, Dproj) <> '') or (RegistroDelIde(ARegistroDe, Dproj) <> '') or
       (InspectUnit(APasPath, Result) <> '') then
      Exit(Default(TUnitInfo));
    JuzgaRaizDeDiseno(Result, '', 0);
  except
    Result := Default(TUnitInfo); // una unidad que no se deja leer: se juzga dentro, como antes
  end;
end;

function RaizDeDesigner(const ARuta: string): TRaizDeDiseno;
var
  Unidad: TUnitInfo;
begin
  Result := rdDesconocida;
  try
    if (InspectUnit(UnidadDeDesigner(ARuta), Unidad) <> '') or (Unidad.ClassName = '') or
       not SameFileName(Unidad.Designer, TPath.GetFullPath(ARuta)) then
      Exit;
    // la cadena primero (el lint pregunta lo mismo para la raiz: el motor, si
    // hace falta, ya esta): aqui solo cuenta la categoria, y el registro del
    // IDE sube por las carpetas leyendo cada .dpr. Solo si la cadena no llega
    JuzgaRaizDeDiseno(Unidad, '', 0);
    if Unidad.Raiz = rdDesconocida then
    begin
      var Registro := RegistroDelIde(Unidad.PasPath, '');
      if Registro <> '' then
        JuzgaRaizDeDiseno(Unidad, Registro, 0);
    end;
    Result := Unidad.Raiz;
  except
    Result := rdDesconocida; // una unidad que no se deja leer
  end;
end;

{ Lo que se dice cuando la raiz de un designer que se registra no se pudo
  juzgar (JuzgaRaizDeDiseno): se escribe como una form, y por que. '' si se
  juzgo o no hay designer que escribir. }
function NotaDeRaiz(const AInfo: TUnitInfo): string;
begin
  Result := '';
  if AInfo.IsDesigner and (AInfo.FormName <> '') and (AInfo.Raiz = rdDesconocida) then
    Result := MsgFmt(SN_UNIT_RAIZ_SIN_JUEZ_FMT, [AInfo.ClassName, AInfo.RaizSinJuez]);
end;

function InspectUnit(const APasPath: string; out AInfo: TUnitInfo): string;
var
  Enc, Src, Stem, DName, DClass, Cab, DC, Corte: string;
  Ini, Largo: Integer;
  U: TUnidadPas;
  M: TMetaTable;
  Falta: TFaltaTabla;
begin
  Result := '';
  AInfo := Default(TUnitInfo);
  if not TFile.Exists(APasPath) then
    Exit(NoEsFichero(APasPath, MsgFmt(SR_UNIT_PAS_MISSING_FMT, [APasPath])));
  if SinMayusculas(TPath.GetExtension(APasPath)) <> '.pas' then
    Exit(MsgFmt(SR_UNIT_NOT_PAS_FMT, [TPath.GetFileName(APasPath)]));
  AInfo.PasPath := TPath.GetFullPath(APasPath);
  Src := PatchLoadText(AInfo.PasPath, Enc);
  if not CabeceraDeUnit(Src, Cab, Ini, Largo) then
    Exit(MsgFmt(SR_UNIT_NO_HEADER_FMT, [TPath.GetFileName(APasPath)]));
  // Hay cabecera, pero su nombre no es un nombre de unit. Decir "no tiene
  // cabecera" era falso y mandaba al agente a buscar un fallo que no existia
  // (Hermes, bateria 1.2). Uno con acentos SI lo es (dcc lo compila, medido
  // el 23-sep) y se negaba aqui porque el servidor no lo sabia leer: EL
  // identificador (Lsp.Pascal) lo lee desde el censo del 4-oct-2026.
  if not EsIdentificador(Cab, True) then
    Exit(MsgFmt(SR_UNIT_HEADER_NONASCII_FMT, [TPath.GetFileName(APasPath), Cab]));
  AInfo.UnitName := Cab;
  Stem := TPath.GetFileNameWithoutExtension(AInfo.PasPath);
  if not MismoIdentificador(Stem, AInfo.UnitName) then
    Exit(MsgFmt(SR_UNIT_HEADER_MISMATCH_FMT, [AInfo.UnitName, TPath.GetFileName(APasPath)]));

  // designer pair? el primero que exista, en el orden de DESIGNER_EXTS (.dfm
  // antes que .fmx), por su nombrador
  for var Form in DesignersDeUnidad(AInfo.PasPath) do
    if TFile.Exists(Form) then
    begin
      AInfo.Designer := Form;
      AInfo.FormType := SinMayusculas(TPath.GetExtension(Form).Substring(1));
      Break;
    end;
  if AInfo.Designer = '' then
    Exit;

  // the designer's root object names the form; the .pas gives the ancestor,
  // read by THE class reader (Lsp.PascalDecl) on its CODE: a commented class
  // ('TViejo = class(TForm)' between braces) is not the form's (censo del
  // lexico, 2-oct-2026)
  U := LeeFuentePascal(Src);
  try
    if DesignerHeaderName(AInfo.Designer, DName, DClass) then
    begin
      AInfo.FormName := DName;
      AInfo.ClassName := DClass;
      var T := U.Clase(DClass);
      if T <> nil then
        AInfo.Ancestor := T.Ancestro;
    end
    else
    begin
      // un designer cuya cabecera no se deja leer (danado): la primera clase
      // de la unidad que SU juez dice que es una raiz del IDE (una form, un
      // frame o un modulo: Lsp.DesignerMeta.RaizDeDiseno, la tabla sin
      // esperar), y su variable. Era una regex del nombre del ancestro
      // (TForm*, TDataModule*, TFrame*): un TFormatter = class(TFormatBase)
      // era la form
      M := MetaTable(EsDesignerFmx(AInfo.Designer), Falta, 0);
      if M <> nil then
        for var T in U.Tipos do
          if (T.Clase = ctClase) and (T.Contenedor = '') and
             (RaizDeDiseno(M, AInfo.PasPath, Src, T.Nombre, DC, Corte) <> rdDesconocida) then
          begin
            AInfo.ClassName := T.Nombre;
            AInfo.Ancestor := T.Ancestro;
            Break;
          end;
      if AInfo.ClassName <> '' then
      begin
        var V := TRegEx.Match(CodigoPascal(Src), '^\s*(' + PATRON_IDENT + ')\s*:\s*' +
          TRegEx.Escape(AInfo.ClassName) + '\s*;', [roIgnoreCase, roMultiline]);
        if V.Success then
          AInfo.FormName := V.Groups[1].Value;
      end;
    end;
  finally
    U.Free;
  end;
end;

{ ---- .dpr uses clause ---- }

function CabeceraDeUnit(const ASrc: string; out ANombre: string;
  out AInicio, ALargo: Integer): Boolean;
var
  Cab: TCabeceraFuente;
begin
  ANombre := '';
  AInicio := 0;
  ALargo := 0;
  // EL lector de la cabecera (Lsp.Pascal): aqui habia una regex que no
  // leia 'unit A . B;' (inventario del 10-oct-2026)
  Result := CabeceraDeFuente(CodigoPascal(ASrc), Cab) and (Cab.Palabra = 'unit') and
    (Cab.NombreLen > 0);
  if Result then
  begin
    AInicio := Cab.NombreIni;
    ALargo := Cab.NombreLen;
    ANombre := Cab.Nombre;
  end;
end;

function BuildEntry(const AInfo: TUnitInfo; const AInclude: string): string;
begin
  if AInfo.IsDesigner then
    Result := EntradaDelUses(AInfo.UnitName, AInclude, AInfo.FormName, AInfo.DesignClass)
  else
    Result := EntradaDelUses(AInfo.UnitName, AInclude, '', '');
end;

function LecturasDelIn(const AFuente: string; out AUnidades, AEscritas, ARutas: TArray<string>): string;
var
  Enc: string;
  U: TUsesClause;
  L: TEntradaDeUses;
begin
  Result := '';
  AUnidades := nil;
  AEscritas := nil;
  ARutas := nil;
  U := FindUses(PatchLoadText(AFuente, Enc));
  if not U.Found then
    Exit;
  // las de todas las ramas: dcc lee la que este activa, y la puerta no sabe
  // cual sera (una rama partida no se reescribe, pero se compila)
  for var E in U.Entries + U.OtrasRamas do
  begin
    Result := NegativaDeEntradaIlegible(U.Keyword, TPath.GetFileName(AFuente), E);
    if Result <> '' then
      Exit;
    L := LeeEntradaDeUses(E);
    if L.Include = '' then
      Continue; // una de la biblioteca: la busca dcc en sus rutas, juzgadas aparte
    AUnidades := AUnidades + [L.Nombre];
    AEscritas := AEscritas + [L.Include];
    ARutas := ARutas + [RutaDeInclude(AFuente, L.Include)];
  end;
end;

function LineaCreateForm(const AClase, AVariable: string): string;
begin
  Result := 'Application.CreateForm(' + AClase + ', ' + AVariable + ');';
end;

function CreateFormLine(const AInfo: TUnitInfo): string;
begin
  Result := LineaCreateForm(AInfo.ClassName, AInfo.FormName);
end;

type
  TCreateFormLeido = record
    Ini, Lon: Integer;    // la sentencia en el texto (1-based), con su ';'
    Clase, Variable: string;
  end;

{ Los CreateForm(Clase, Variable) del CODIGO de ATexto, en orden, aunque
  vayan partidos en varias lineas: EL lector de lo que escribe
  LineaCreateForm. Eran cuatro regex linea a linea en InsertCreateForm y
  RemoveCreateForm, y uno partido no se quitaba: remove-unit lo dejaba y el
  .dpr no compilaba (medido el 25-oct-2026). Lo de detras del ')' solo en
  su linea: con un \s* que cruzaba el salto, quitar la sentencia pegaba la
  linea siguiente. }
function CreateFormsDe(const ATexto: string): TArray<TCreateFormLeido>;
var
  C: TCreateFormLeido;
begin
  Result := [];
  for var M in TRegEx.Matches(CodigoPascal(ATexto), '(?:' + PATRON_NO_IDENT_ANTES + 'Application\s*\.\s*)?' +
    PATRON_NO_IDENT_ANTES + 'CreateForm\s*\(\s*(' + PATRON_IDENT_PUNTOS + ')\s*,\s*(' + PATRON_IDENT +
    ')\s*\)[ \t]*;?', [roIgnoreCase]) do
  begin
    C.Ini := M.Index;
    C.Lon := M.Length;
    C.Clase := M.Groups[1].Value;
    C.Variable := M.Groups[2].Value;
    Result := Result + [C];
  end;
end;

{ Inserts the CreateForm after the last existing CreateForm, else right
  before Application.Run. Returns False when neither anchor exists. Lo que
  busca, en el CODIGO: un Application.Run comentado encima del de verdad
  se llevaba el CreateForm DENTRO del comentario, y uno comentado de la
  misma clase pasaba por "ya esta" (revision de la 1.10.0, medido con
  delphi_create form-vcl). }
function InsertCreateForm(var Dpr: string; const AInfo: TUnitInfo): Boolean;
var
  Lines, Vista: TArray<string>;
  Leidos: TArray<TCreateFormLeido>;
  I, Last, RunAt: Integer;
  NL, Indent: string;
begin
  Result := False;
  Leidos := CreateFormsDe(Dpr);
  for var C in Leidos do
    if MismoIdentificador(C.Clase, AInfo.ClassName) then
      Exit(True); // already there
  NL := SaltoDominante(Dpr);
  Lines := SplitToLines(Dpr); // el troceador del motor: un CR suelto es salto
  Vista := SplitToLines(CodigoPascal(Dpr));
  // la linea donde ACABA el ultimo: uno partido en dos acaba en la segunda
  Last := -1;
  if Length(Leidos) > 0 then
    Last := LineaDePosicion(Dpr, Leidos[High(Leidos)].Ini + Leidos[High(Leidos)].Lon - 1) - 1;
  RunAt := -1;
  for I := 0 to High(Lines) do
    if TRegEx.IsMatch(Vista[I], '^\s*Application\.Run\b', [roIgnoreCase]) then
    begin
      RunAt := I;
      Break;
    end;
  if (Last = -1) and (RunAt = -1) then
    Exit;
  // La linea entra con el compositor de todos (CambiaLineasEnSuTexto): las
  // demas, con SU salto. Unidas todas al dominante, un .dpr mixto salia
  // entero a ese salto (1.18.2)
  // right before Application.Run, like the IDE: a CreateForm placed after
  // the last one could land inside that one's conditional block
  if RunAt <> -1 then
  begin
    // la sangria, con el lector de la casa (Lsp.Patch.LeadingWhite):
    // habia cinco copias a mano con TrimLeft, que se lleva tambien los
    // caracteres de control (#0..#31) a la linea nueva (1.15.0)
    Indent := LeadingWhite(Lines[RunAt]);
    Dpr := CambiaLineasEnSuTexto(Dpr, RunAt, 0, [Indent + CreateFormLine(AInfo)], NL);
  end
  else
  begin
    Indent := LeadingWhite(Lines[Last]);
    Dpr := CambiaLineasEnSuTexto(Dpr, Last + 1, 0, [Indent + CreateFormLine(AInfo)], NL);
  end;
  Result := True;
end;

{ Drops every Application.CreateForm naming AClass or AVar - del CODIGO
  (CreateFormsDe): uno comentado se queda; uno partido en varias lineas se
  va entero; y de una linea que lleva algo mas (el cierre de un comentario
  de encima) se va la sentencia sola: la llave que cerraba el comentario
  detras de un CreateForm se iba con el, y el comentario quedaba abierto
  hasta el final (revision de la 1.10.0, medido con remove-unit). }
function RemoveCreateForm(var Dpr: string; const AClassName, AFormName: string): Integer;
var
  Leidos: TArray<TCreateFormLeido>;
  Lines: TArray<string>;
  NL: string;
begin
  Result := 0;
  if (AClassName = '') and (AFormName = '') then
    Exit;
  NL := SaltoDominante(Dpr);
  Leidos := CreateFormsDe(Dpr);
  // De abajo arriba: quitar una sentencia no mueve lo de delante, donde
  // estan las que quedan por mirar. Cada una con el compositor de todos
  // (CambiaLineasEnSuTexto): las demas lineas, con SU salto. Unidas todas al
  // dominante, un .dpr mixto salia entero a ese salto (1.18.2)
  for var K := High(Leidos) downto 0 do
  begin
    var C := Leidos[K];
    if AClassName <> '' then
    begin
      if not MismoIdentificador(C.Clase, AClassName) then
        Continue;
    end
    else if not MismoIdentificador(C.Variable, AFormName) then
      Continue;
    Inc(Result);
    // la sentencia sola: lo de delante en su primera linea y lo de detras en
    // la ultima se quedan (entre ello puede ir el cierre del comentario de
    // encima: con la linea entera se iba la llave)
    var Fin := C.Ini + C.Lon - 1;
    var L1 := LineaDePosicion(Dpr, C.Ini) - 1;
    var L2 := LineaDePosicion(Dpr, Fin) - 1;
    Lines := SplitToLines(Dpr);
    var Resto := Copy(Lines[L1], 1, C.Ini - InicioDeLaLinea(Dpr, C.Ini)) +
      Copy(Lines[L2], Fin - InicioDeLaLinea(Dpr, Fin) + 2, MaxInt);
    if Resto.Trim <> '' then
      Dpr := CambiaLineasEnSuTexto(Dpr, L1, L2 - L1 + 1, [Resto.TrimRight], NL)
    else
      Dpr := CambiaLineasEnSuTexto(Dpr, L1, L2 - L1 + 1, nil, NL);
  end;
end;

{ ---- .dproj DCCReference ---- }

function DccRefXml(const AInfo: TUnitInfo; const AInclude: string): string;
const
  CRLF = #13#10;
begin
  if AInfo.IsDesigner and (AInfo.FormName <> '') then
  begin
    Result := '        <DCCReference ' + XmlAtributo('Include', AInclude) + '>' + CRLF +
      LineaXml('            ', 'Form', AInfo.FormName);
    if AInfo.FormType <> '' then
      Result := Result + LineaXml('            ', 'FormType', AInfo.FormType);
    if AInfo.DesignClass <> '' then
      Result := Result + LineaXml('            ', 'DesignClass', AInfo.DesignClass);
    Result := Result + '        </DCCReference>' + CRLF;
  end
  else
    Result := '        <DCCReference ' + XmlAtributo('Include', AInclude) + '/>' + CRLF;
end;

{ LA clave con la que se comparan dos Include (de un .dproj o de un uses): la
  del disco (ClaveDeRuta) y con barras de Windows. El IDE escribe '\', y un
  agente o una herramienta pueden escribir '/' (estaba a mano en cuatro sitios). }
function ClaveDeInclude(const AInclude: string): string;
begin
  Result := ClaveDeRuta(ConBarrasDeWindows(AInclude));
end;

{ Finds the element for AInclude (path compared case-insensitively with / and
  \ unified). Returns its [Start, Len) in Xml including the trailing newline. }
function FindDccRef(const Xml, AInclude: string; out AStart, ALen: Integer): Boolean;
var
  Want: string;
  Hasta: Integer;
begin
  // por EL analisis del .dproj (TramosDeEtiqueta, AtributoDeTramo): era una
  // regex con el Include el primero, entre comillas dobles, y la etiqueta
  // sola en su linea
  Result := False;
  Want := ClaveDeInclude(AInclude);
  for var T in TramosDeEtiqueta(Xml, 'DCCReference', True) do
    if ClaveDeInclude(AtributoDeTramo(Xml, T, 'DCCReference', 'Include')) = Want then
    begin
      ConSuLinea(Xml, T.Abre, T.Cierra, AStart, Hasta);
      ALen := Hasta - AStart;
      Exit(True);
    end;
end;

{ Inserts the element after the last DCCReference; else after </DelphiCompile>;
  else before the first <BuildConfiguration; else before the first </ItemGroup>. }
function InsertDccRef(const Xml, AElement: string): string;
var
  At, Desde, Hasta: Integer;
begin
  // los mismos cuatro sitios, por EL analisis (eran cuatro regex)
  var Refs := TramosDeEtiqueta(Xml, 'DCCReference', True);
  var Compila := TramosDeEtiqueta(Xml, 'DelphiCompile', True);
  var Configs := TramosDeEtiqueta(Xml, 'BuildConfiguration', True);
  var Grupos := TramosDeEtiqueta(Xml, 'ItemGroup');
  if Length(Refs) > 0 then
    ConSuLinea(Xml, Refs[High(Refs)].Abre, Refs[High(Refs)].Cierra, Desde, At)
  else if Length(Compila) > 0 then
    ConSuLinea(Xml, Compila[0].Abre, Compila[0].Cierra, Desde, At)
  else if Length(Configs) > 0 then
    ConSuLinea(Xml, Configs[0].Abre, Configs[0].Cierra, At, Hasta)
  else if Length(Grupos) > 0 then
    ConSuLinea(Xml, Grupos[0].Fin, Grupos[0].Cierra, At, Hasta)
  else
    Exit(Xml); // no ItemGroup at all: the caller reports "not in .dproj"
  Result := Copy(Xml, 1, At - 1) + AElement + Copy(Xml, At, MaxInt);
end;

{ ---- public operations ---- }

function AddProjectUnitNucleo(const AProject, APasPath: string;
  ARaizDelCreador: TRaizDeDiseno; APrevia: PUnitInfo): string;
var
  Dpr, Dproj, Enc, Text, Include, Entry, Note: string;
  Info: TUnitInfo;
  U: TUsesClause;
  E: string;
  Present, Completada, Estrenada, EsPaquete, ConCreateForm: Boolean;
  Entries: TArray<string>;
  S, L: Integer;
begin
  Result := ResolveProjectPair(AProject, Dpr, Dproj);
  if Result <> '' then
    Exit;
  Result := InspectUnit(APasPath, Info);
  if Result <> '' then
    Exit;
  // lo que es su raiz para el IDE, con la tabla como este: quien la espera lo
  // hace antes de coger el cerrojo; y su cadena, juzgada antes tambien
  // (APrevia, PrejuzgaRaiz: V177 de la 1.23.1)
  JuzgaRaizDeDiseno(Info, RegistroDelIde(Info.PasPath, Dproj), 0, ARaizDelCreador, APrevia);
  Include := IncludeFor(Dpr, Info.PasPath);

  // .dpr
  Text := PatchLoadText(Dpr, Enc);
  U := FindUses(Text);
  Estrenada := False;
  if not U.Found then
  begin
    // Un paquete recien creado no tiene clausula contains (una vacia no es
    // legal): la primera unit la estrena, justo antes del end. final.
    if SameText(U.Keyword, 'contains') then
    begin
      Estrenada := True;
      // el end. final, por EL lector (Lsp.Pascal)
      var Ends := EndsConPunto(CodigoPascal(Text));
      if Length(Ends) = 0 then
        Exit(MsgFmt(SR_UNIT_NO_USES_FMT, [TPath.GetFileName(Dpr)]));
      var NL := SaltoDominante(Text);
      Text := Copy(Text, 1, Ends[0].Ini - 1) + 'contains' + NL + '  ' +
        BuildEntry(Info, Include) + ';' + NL + NL + Copy(Text, Ends[0].Ini, MaxInt);
      PatchSaveText(Dpr, Text, Enc);
      Text := PatchLoadText(Dpr, Enc);
      U := FindUses(Text);
    end
    else
    begin
      // Un programa al que se le quito su ULTIMA unit tampoco la tiene (se va
      // entera: decima revision): la estrena justo tras la cabecera.
      if EstrenaUsesTrasCabecera(Text, BuildEntry(Info, Include)) then
      begin
        Estrenada := True;
        PatchSaveText(Dpr, Text, Enc);
        Text := PatchLoadText(Dpr, Enc);
        U := FindUses(Text);
      end;
    end;
    if not U.Found then
      Exit(MsgFmt(SR_UNIT_NO_USES_FMT, [TPath.GetFileName(Dpr)]));
  end;
  var NoSe := ClausulaQueNoSeReescribe(U, TPath.GetFileName(Dpr));
  if NoSe <> '' then
    Exit(NoSe);
  Present := False;
  Completada := False;
  Entries := U.Entries;
  for var I := 0 to High(Entries) do
    if MismoIdentificador(EntryUnitName(Entries[I]), Info.UnitName) then
    begin
      Present := True;
      if EntryInclude(Entries[I]) <> '' then
        Include := EntryInclude(Entries[I]) // the .dproj element follows the .dpr entry
      else
      begin
        // Presente por el NOMBRE pero sin clausula in: se daba por hecha
        // ("ya estaba, nada que cambiar"), se refrescaba el .dproj y el .dpr
        // se quedaba sin la ruta, asi que dcc no encontraba una unit de otra
        // carpeta (F2613). Medido 2026-09-23 (Hermes, bateria 1.2). Se
        // completa la entrada como la escribiria el IDE, conservando la
        // directiva o comentario que la preceda.
        Entries[I] := EntradaReescrita(Entries[I], BuildEntry(Info, Include));
        Completada := True;
      end;
    end;
  Note := '';
  if not Present then
  begin
    Entries := Entries + [BuildEntry(Info, Include)];
    Text := ReplaceUses(Text, U, Entries);
  end
  else if Completada then
    Text := ReplaceUses(Text, U, Entries);
  // un paquete no lleva CreateForm (no tiene programa principal): se
  // intentaba, contestaba CFG-046 y el mensaje decia "+ CreateForm" (P9)
  // ...y lo es por su cabecera, como lo compila dcc (EsFuenteDePaquete, A30)
  EsPaquete := EsFuenteDePaquete(Text);
  // ...ni el de un programa sin Application.Run ni otro CreateForm (una
  // consola): el mensaje dice lo que QUEDO en el .dpr, no lo que el form
  // pediria. Anunciaba "+ Application.CreateForm" y CFG-046 lo desmentia en
  // la linea siguiente (Hermes, 15-oct-2026, informe 1938c; gemelo de P9)
  ConCreateForm := False;
  if Info.NeedsCreateForm and not EsPaquete then
  begin
    ConCreateForm := InsertCreateForm(Text, Info);
    if not ConCreateForm then
      Note := MsgText(SN_UNIT_NO_RUN_ANCHOR);
  end;
  PatchSaveText(Dpr, Text, Enc);

  // .dproj
  if TFile.Exists(Dproj) then
  begin
    Text := PatchLoadText(Dproj, Enc);
    if FindDccRef(Text, Include, S, L) then
    begin
      // refresh the element (a plain unit that gained a form, for instance)
      Text := Copy(Text, 1, S - 1) + DccRefXml(Info, Include) + Copy(Text, S + L, MaxInt);
    end
    else
    begin
      Entry := InsertDccRef(Text, DccRefXml(Info, Include));
      if Entry = Text then
        Note := Note + IfThen(Note <> '', ' ', '') + MsgText(SN_UNIT_NO_ITEMGROUP)
      else
        Text := Entry;
    end;
    // con el salto del .dproj (DccRefXml compone en CRLF): add-unit metia
    // CRLF en un .dproj en LF (novena revision)
    PatchSaveConSuSalto(Dproj, Text, Enc);
  end
  else
    Note := Note + IfThen(Note <> '', ' ', '') + MsgText(SN_UNIT_NO_DPROJ);
  if NotaDeRaiz(Info) <> '' then
    Note := Note + IfThen(Note <> '', ' ', '') + NotaDeRaiz(Info);

  if Completada then
    Result := MsgFmt(SN_UNIT_COMPLETED_FMT, [Info.UnitName, TPath.GetFileName(Dpr),
      Info.UnitName, Include])
  else if Present and not Estrenada then
    Result := MsgFmt(SN_UNIT_PRESENT_FMT, [Info.UnitName, TPath.GetFileName(Dpr)])
  else if Info.IsDesigner then
    Result := MsgFmt(SN_UNIT_ADDED_FORM_FMT, [Info.UnitName, Include, Info.FormName,
      Info.ClassName, TPath.GetFileName(Dpr), U.Keyword, TPath.GetFileName(Dpr),
      IfThen(ConCreateForm, MsgText(SN_UNIT_CREATEFORM), '')])
  else
    Result := MsgFmt(SN_UNIT_ADDED_FMT, [Info.UnitName, Include, TPath.GetFileName(Dpr),
      U.Keyword, TPath.GetFileName(Dpr)]);
  if Note <> '' then
    Result := Result + #10 + Note;
end;

{ Un cambio del proyecto (el .dpr/.dpk y su .dproj) TODO O NADA: si la accion
  lanza o falla a mitad (un .dproj que otro proceso tiene abierto), lo ya
  escrito vuelve. Registrar una unit escribia el .dpr y contestaba "repite"
  con el .dproj sin tocar (quinta revision). }
function ProyectoTodoONada(const AProject: string; const AMas: TArray<string>;
  const AAccion: TFunc<string>): string; overload;
var
  Dpr, Dproj: string;
  Rutas: TArray<string>;
begin
  if ResolveProjectPair(AProject, Dpr, Dproj) <> '' then
    Exit(AAccion()); // la accion dira lo que no cuadra; no hay que deshacer
  // AMas: lo que la accion reescribe ADEMAS del par (un rename, las units)
  Rutas := [Dpr, Dproj];
  Rutas := Rutas + AMas;
  // la foto y su vuelta atras, las de todos (Lsp.TodoONada.FicherosTodoONada)
  Result := FicherosTodoONada(Rutas,
    function: string
    begin
      Result := AAccion();
    end);
end;

function ProyectoTodoONada(const AProject: string; const AAccion: TFunc<string>): string; overload;
begin
  Result := ProyectoTodoONada(AProject, [], AAccion);
end;

function AddProjectUnit(const AProject, APasPath: string;
  ARaizDelCreador: TRaizDeDiseno): string;
begin
  // Registrar una unidad es leer el .dpr, modificarlo y escribirlo: dos
  // agentes creando unidades en el MISMO proyecto a la vez perdian entradas
  // dando exito (medido 2026-09-20, bateria de concurrencia). Con el cerrojo
  // de escritura por delante, el .dpr deja de ser una carrera. Lo que es su
  // raiz por su cadena (el motor, si sale de la unidad), ANTES: dentro paraba
  // todas las escrituras del servidor (V177 de la 1.23.1, medido)
  var Previa := PrejuzgaRaiz(AProject, APasPath, APasPath, ARaizDelCreador);
  EnterFileEdit;
  try
    Result := ProyectoTodoONada(AProject,
      function: string
      begin
        Result := AddProjectUnitNucleo(AProject, APasPath, ARaizDelCreador, @Previa);
      end);
  finally
    LeaveFileEdit;
  end;
end;

function TResolutorDeUnidades.Resuelve(const ANombre: string): string;

  // por la clave con que se escribieron (Lsp.Discovery.EnLaBiblioteca): .ToLower
  // lleva el casing del idioma y con el turco no casaba (V98 de la 1.23.1)
  function Existe(const N: string): Boolean;
  begin
    Result := (IndexStr(ClaveDeIdentificador(N), Propias) >= 0) or EnLaBiblioteca(Biblioteca, N);
  end;

begin
  Result := ANombre;
  if Existe(ANombre) then
    Exit;
  for var S in Ambitos do
    if Existe(S + '.' + ANombre) then
      Exit(S + '.' + ANombre);
end;

function TResolutorDeUnidades.MismaUnidad(const A, B: string): Boolean;
begin
  Result := MismoIdentificador(A, B) or MismoIdentificador(Resuelve(A), Resuelve(B));
end;

function TResolutorDeUnidades.EnUses(const AUses: TArray<string>; const AUnidad: string): Boolean;
begin
  for var E in AUses do
    if MismaUnidad(E, AUnidad) then
      Exit(True);
  Result := False;
end;

function ResolutorDeUnidades(const AFuente: string; const ADeUnFichero: string): TResolutorDeUnidades;
var
  Dproj, Xml: string;
begin
  Result := Default(TResolutorDeUnidades);
  Result.Ambitos := DEFAULT_NAMESPACES.Split([';'], TStringSplitOptions.ExcludeEmpty);
  Result.Biblioteca := UnidadesDeLaBiblioteca;
  // la de un fichero es ESE fichero: Graphics.pas es Graphics, nunca
  // Vcl.Graphics (V107: remove-unit de un Graphics.pas que no listaba nadie
  // quitaba Vcl.Graphics del .dpr y decia "REMOVED unit Graphics")
  if ADeUnFichero <> '' then
    Result.Propias := [ClaveDeIdentificador(ADeUnFichero)];
  try
    if EsProyectoOSuFuente(AFuente) then
      Dproj := DprojDe(AFuente)
    else
      Dproj := TLspSession.Instance.FindDproj(AFuente);
    if (Dproj = '') or not TFile.Exists(Dproj) then
      Exit;
    // lo que compila el IDE mientras nadie pide otra cosa (sus selectores)
    Xml := LeeTexto(Dproj, [ltJaula]);
    var Info := InfoDeDproj(Xml);
    Result.Ambitos := AmbitosDelProyecto(Xml, Info.PlataformaPorDefecto, Info.ConfigPorDefecto).Split([';'],
      TStringSplitOptions.ExcludeEmpty);
    Result.Proyecto := Dproj;
    // las que lista su fuente principal, por EL lector de sus entradas
    var Unidades, Escritas, Rutas: TArray<string>;
    if LecturasDelIn(DprDe(Dproj), Unidades, Escritas, Rutas) = '' then
      for var N in Unidades do
        Result.Propias := Result.Propias + [ClaveDeIdentificador(N)];
    // y las que dcc encuentra por su NOMBRE sin que nadie las liste: las de la
    // carpeta del proyecto y las de su search path (medido con dcc, V107: un
    // Graphics.pas sin listar al lado del .dpr, o en una carpeta del search
    // path, es Graphics y no Vcl.Graphics - "uses Vcl.Graphics, Graphics"
    // compila -; un .dcu en la carpeta del proyecto cuenta; en una subcarpeta
    // que no esta en el search path, o al lado de la unidad que lo usa, no lo
    // encuentra, ni un .dcu viejo en la carpeta de salida). Lo que el motor no
    // puede ensenar no se mira: el build lo niega (BUILD-050)
    var Dentro, Fuera: TArray<string>;
    CarpetasDelProyecto(Xml, TPath.GetDirectoryName(Dproj), TPath.GetFileNameWithoutExtension(Dproj),
      Info.PlataformaPorDefecto, Info.ConfigPorDefecto, DiscoverRadStudio, Dentro, Fuera);
    Result.Propias := Result.Propias + UnidadesEnCarpetas([TPath.GetDirectoryName(Dproj)] + Dentro);
  except
    // lo que no se lee no cuenta: se queda lo que ya se sabe
  end;
end;

{ The entry and the .dproj include for a unit, by unit name or by file stem
  (the .pas may already be gone when delete calls us): the SAME unit, as dcc
  resolves it (TResolutorDeUnidades, V79 de la 1.23.1). }
function LocateEntry(const U: TUsesClause; const AUnitName: string; const AResolutor: TResolutorDeUnidades;
  out AEntry: string): Boolean;
var
  E: string;
begin
  for E in U.Entries do
    if AResolutor.MismaUnidad(EntryUnitName(E), AUnitName) then
    begin
      AEntry := E;
      Exit(True);
    end;
  Result := False;
end;

function RemoveProjectUnitNucleo(const AProject, APasPath: string;
  AFileGoesToo: Boolean): string;
var
  Dpr, Dproj, Enc, Text, UnitName, Entry, Include, FormName, ClassName: string;
  U: TUsesClause;
  Entries: TArray<string>;
  E: string;
  S, L, N: Integer;
  Info: TUnitInfo;
  InDpr, InDproj: Boolean;
begin
  Result := ResolveProjectPair(AProject, Dpr, Dproj);
  if Result <> '' then
    Exit;
  if SinMayusculas(TPath.GetExtension(APasPath)) <> '.pas' then
    Exit(MsgFmt(SR_UNIT_NOT_PAS_FMT, [TPath.GetFileName(APasPath)]));
  UnitName := TPath.GetFileNameWithoutExtension(APasPath);
  // la ENTRADA como la lista el proyecto: una relativa es desde su .dpr (EL
  // lector de lo que escribe IncludeFor). Se juzgaba desde la carpeta de
  // trabajo del servidor, y una que estaba dentro se daba por de fuera de lo
  // legible (Opus en Hermes, 1.22.2)
  var Pas := RutaDeInclude(Dpr, APasPath);
  ClassName := '';
  FormName := '';
  // una ruta de FUERA de lo legible no se abre: la entrada se quita por su
  // nombre, como una que no existe (remove-unit de una <DCCReference> que
  // BUILD-050 pide quitar, 21-oct-2026)
  var Fuera := ReadPathDenied(Pas) <> '';
  if (not Fuera) and (InspectUnit(Pas, Info) = '') then
  begin
    UnitName := Info.UnitName;
    ClassName := Info.ClassName;
    FormName := Info.FormName;
  end;

  Text := PatchLoadText(Dpr, Enc);
  U := FindUses(Text);
  if not U.Found then
    Exit(MsgFmt(SR_UNIT_NO_USES_FMT, [TPath.GetFileName(Dpr)]));
  var NoSe := ClausulaQueNoSeReescribe(U, TPath.GetFileName(Dpr));
  if NoSe <> '' then
    Exit(NoSe);
  InDpr := LocateEntry(U, UnitName, ResolutorDeUnidades(Dpr, UnitName), Entry);
  Include := IncludeFor(Dpr, Pas);
  if InDpr then
  begin
    if EntryInclude(Entry) <> '' then
      Include := EntryInclude(Entry);
    if FormName = '' then
      FormName := EntryFormName(Entry);
    // la entrada que se encontro, como esta escrita
    Entries := EntriesWithout(U.Entries, EntryUnitName(Entry));
    Text := ReplaceUses(Text, U, Entries);
    // the .pas gone: only the {Form} variable is known, match on it
    N := RemoveCreateForm(Text, ClassName, FormName);
    PatchSaveText(Dpr, Text, Enc);
  end
  else
    N := 0;

  InDproj := False;
  if TFile.Exists(Dproj) then
  begin
    Text := PatchLoadText(Dproj, Enc);
    if FindDccRef(Text, Include, S, L) then
    begin
      Text := Copy(Text, 1, S - 1) + Copy(Text, S + L, MaxInt);
      PatchSaveConSuSalto(Dproj, Text, Enc);
      InDproj := True;
    end;
  end;

  if not (InDpr or InDproj) then
    Exit(MsgFmt(SN_UNIT_ABSENT_FMT, [UnitName, TPath.GetFileName(Dpr)]));
  // The "the file is still on disk, delete it if you no longer want it" tail
  // belongs to command=remove-unit. It was also landing inside delphi_delete's
  // own answer, three lines under "BORRADO ... moved to the trash", and made
  // the reader doubt what had happened (measured 2026-08-25).
  // (con una ruta que no existe, la unidad se encontro por su nombre: decia
  // "still on disk" de un fichero que no estaba; punto 8 de la 1.18.2)
  var Plantilla := MsgText(SN_UNIT_REMOVED_FMT);
  // la entrada como la lista el proyecto (Lib\UX.pas): decia solo el fichero
  // (rondas de Opus de la 1.22.2)
  var Dado := Include;
  var Listado := '';
  if AFileGoesToo then
    Plantilla := MsgText(SN_UNIT_REMOVED_GONE_FMT)
  else if Fuera then
    // de fuera no se dice ni si existe: nada se abre alli
    Plantilla := MsgText(SN_UNIT_REMOVED_FUERA_FMT)
  else if not TFile.Exists(Pas) then
  begin
    // ...y si el proyecto la listaba por OTRA ruta que SI existe, es esa la
    // que sigue en disco y se nombra, con la dada entera al lado: CFG-112
    // negaba un fichero que estaba (M5 de los revisores de cierre). Include
    // es lo que listaba la entrada (o la ruta dada, si no la listaba nadie)
    Listado := RutaDeInclude(Dpr, Include);
    if TFile.Exists(Listado) then
    begin
      Plantilla := MsgText(SN_UNIT_REMOVED_OTRA_RUTA_FMT);
      Dado := Pas;
    end
    else
      Plantilla := MsgText(SN_UNIT_REMOVED_SIN_FICHERO_FMT);
  end;
  // (Format ignora el septimo argumento en las plantillas de seis)
  Result := Format(Plantilla, [UnitName, TPath.GetFileName(Dpr),
    IfThen(InDpr, U.Keyword, '-'), IfThen(N > 0, ' + CreateForm', ''),
    IfThen(InDproj, MsgText(SF_USES_DCCREFERENCE_DEL_DPROJ), ''), Dado, Listado]);
end;

function RemoveProjectUnit(const AProject, APasPath: string;
  AFileGoesToo: Boolean): string;
begin
  EnterFileEdit;
  try
    Result := ProyectoTodoONada(AProject,
      function: string
      begin
        Result := RemoveProjectUnitNucleo(AProject, APasPath, AFileGoesToo);
      end);
  finally
    LeaveFileEdit;
  end;
end;

function RenameProjectUnitNucleo(const AProject, AOldPasPath, ANewPasPath: string;
  APrevia: PUnitInfo): string;
var
  Dpr, Dproj, Enc, Text, OldName, OldInclude, Entry, NewInclude: string;
  U: TUsesClause;
  Entries: TArray<string>;
  E: string;
  Info: TUnitInfo;
  S, L, I: Integer;
  Found: Boolean;
begin
  Result := ResolveProjectPair(AProject, Dpr, Dproj);
  if Result <> '' then
    Exit;
  Result := InspectUnit(ANewPasPath, Info);
  if Result <> '' then
    Exit;
  // su raiz: la registro el IDE con la ruta VIEJA; su cadena, juzgada antes
  // del cerrojo (APrevia, V177 de la 1.23.1)
  JuzgaRaizDeDiseno(Info, RegistroDelIde(AOldPasPath, Dproj), 0, rdDesconocida, APrevia);
  OldName := TPath.GetFileNameWithoutExtension(AOldPasPath);
  NewInclude := IncludeFor(Dpr, Info.PasPath);

  Text := PatchLoadText(Dpr, Enc);
  U := FindUses(Text);
  if not U.Found then
    Exit(MsgFmt(SR_UNIT_NO_USES_FMT, [TPath.GetFileName(Dpr)]));
  var NoSe := ClausulaQueNoSeReescribe(U, TPath.GetFileName(Dpr));
  if NoSe <> '' then
    Exit(NoSe);
  Found := LocateEntry(U, OldName, ResolutorDeUnidades(Dpr, OldName), Entry);
  if not Found then
    Exit(MsgFmt(SN_UNIT_ABSENT_FMT, [OldName, TPath.GetFileName(Dpr)]));
  OldInclude := EntryInclude(Entry);
  if OldInclude = '' then
    OldInclude := IncludeFor(Dpr, TPath.GetFullPath(AOldPasPath));
  Entries := U.Entries;
  for I := 0 to High(Entries) do
    // la entrada que encontro el resolutor, como esta escrita (como sus
    // hermanas): con OldName, una entrada que casa por un ambito no se
    // reescribia y se anadia un DCCReference (V104 de la 1.23.1)
    if MismoIdentificador(EntryUnitName(Entries[I]), EntryUnitName(Entry)) then
    begin
      Entries[I] := EntradaReescrita(Entries[I], BuildEntry(Info, NewInclude));
    end;
  Text := ReplaceUses(Text, U, Entries);
  PatchSaveText(Dpr, Text, Enc);

  if TFile.Exists(Dproj) then
  begin
    Text := PatchLoadText(Dproj, Enc);
    if FindDccRef(Text, OldInclude, S, L) then
      Text := Copy(Text, 1, S - 1) + DccRefXml(Info, NewInclude) + Copy(Text, S + L, MaxInt)
    else
    begin
      E := InsertDccRef(Text, DccRefXml(Info, NewInclude));
      Text := E;
    end;
    PatchSaveConSuSalto(Dproj, Text, Enc);
  end;
  // (un RENAME reescribia ademas los uses y los UnitVieja.X de las otras
  // units: ninguna tool renombra una unit desde V19, y fix-references
  // re-apunta por el MISMO nombre)
  Result := MsgFmt(SN_UNIT_RENAMED_FMT, [OldName, OldInclude, Info.UnitName, NewInclude,
    TPath.GetFileName(Dpr), U.Keyword]);
  if NotaDeRaiz(Info) <> '' then
    Result := Result + #10 + NotaDeRaiz(Info);
end;

function RenameProjectUnit(const AProject, AOldPasPath, ANewPasPath: string): string;
begin
  // su cadena, ANTES del cerrojo, como add-unit (V177 de la 1.23.1)
  var Previa := PrejuzgaRaiz(AProject, ANewPasPath, AOldPasPath);
  EnterFileEdit;
  try
    // TODO O NADA, como registrar y quitar (ProyectoTodoONada): con el .dproj
    // en +R el .dpr quedaba re-apuntado y el DCCReference no, y la respuesta
    // decia "nothing was written" (medido en vivo, 28-sep-2026)
    Result := ProyectoTodoONada(AProject,
      function: string
      begin
        Result := RenameProjectUnitNucleo(AProject, AOldPasPath, ANewPasPath, @Previa);
      end);
  finally
    LeaveFileEdit;
  end;
end;

function AddPackageRequires(const AProject, ANames: string): string;
var
  Dpr, Dproj, Enc, Text, NL, Clausula, N, E: string;
  Nombres, Nuevos: TStringList;
  Entradas, Existentes: TArray<string>;
  Ya: Boolean;
  U: TUsesClause;
begin
  Result := ResolveProjectPair(AProject, Dpr, Dproj);
  if Result <> '' then
    Exit;
  Nombres := TStringList.Create;
  Nuevos := TStringList.Create;
  try
    for N in NombresDeUnidades(ANames) do
    begin
      if not EsIdentificador(N, True) then
        Exit(MsgFmt(SR_REQUIRES_BAD_NAME_FMT, [N]));
      Nombres.Add(N);
    end;
    if Nombres.Count = 0 then
      Exit(MsgText(SR_REQUIRES_NEED_NAMES));
    EnterFileEdit;
    try
      Text := PatchLoadText(Dpr, Enc);
      // un paquete por su cabecera, como lo compila dcc, no por ser un .dpk
      // (EsFuenteDePaquete, A30 de la 1.23)
      if not EsFuenteDePaquete(Text) then
        Exit(MsgFmt(SR_REQUIRES_NOT_PACKAGE_FMT, [TPath.GetFileName(Dpr)]));
      NL := SaltoDominante(Text);
      // EL lector y EL escritor de las clausulas (FindUses / ReplaceUses, los
      // de contains): se reescribia entera, un nombre por linea, y se perdian
      // sus comentarios y sus {$IFDEF} - en 'rtl, dbrtl{$IFDEF MSWINDOWS},
      // vcl{$ENDIF}' vcl pasaba a ser de todas las plataformas (medido el
      // 18-oct-2026). Partida en ramas no se toca, como contains
      U := FindUses(Text, 0, 'requires');
      var NoSe := ClausulaQueNoSeReescribe(U, TPath.GetFileName(Dpr));
      if NoSe <> '' then
        Exit(NoSe);
      Entradas := U.Entries;
      for N in Nombres do
      begin
        Ya := False;
        for E in Entradas do
          if MismoIdentificador(EntryUnitName(E), N) then
            Ya := True;
        if not Ya then
        begin
          Entradas := Entradas + [N];
          Nuevos.Add(N);
        end;
      end;
      if Nuevos.Count = 0 then
        Exit(MsgFmt(SN_REQUIRES_PRESENT_FMT, [TPath.GetFileName(Dpr)]));
      Existentes := [];
      for E in Entradas do
        Existentes := Existentes + [EntryUnitName(E)];
      if U.Found then
        Text := ReplaceUses(Text, U, Entradas)
      else
      begin
        Clausula := 'requires' + NL + '  ' + string.Join(',' + NL + '  ', Existentes) + ';';
        // delante de contains (EL lector de la clausula: FindUses) o del end.
        // final (EL suyo: Lsp.Pascal). contains se buscaba al principio de una
        // linea, y en un .dpk de una linea el requires caia DETRAS de el
        // (revisor 8, 10-oct-2026)
        var Donde := 0;
        var Contains := FindUses(Text);
        if Contains.Found then
          Donde := Contains.StartPos;
        var Ends := EndsConPunto(CodigoPascal(Text));
        if (Length(Ends) > 0) and ((Donde = 0) or (Ends[0].Ini < Donde)) then
          Donde := Ends[0].Ini;
        if Donde = 0 then
          Exit(MsgFmt(SR_UNIT_NO_USES_FMT, [TPath.GetFileName(Dpr)]));
        Text := Copy(Text, 1, Donde - 1) + Clausula + NL + NL + Copy(Text, Donde, MaxInt);
      end;
      PatchSaveText(Dpr, Text, Enc);
    finally
      LeaveFileEdit;
    end;
    Result := MsgFmt(SN_REQUIRES_ADDED_FMT, [TPath.GetFileName(Dpr),
      string.Join(', ', Nuevos.ToStringArray), string.Join(', ', Existentes)]);
  finally
    Nombres.Free;
    Nuevos.Free;
  end;
end;

function ClausulaRequires(const ATexto: string; out ANombres: TArray<string>;
  out AIni, ALargo: Integer): Boolean;
var
  U: TUsesClause;
begin
  ANombres := [];
  AIni := 0;
  ALargo := 0;
  if not EsFuenteDePaquete(ATexto) then
    Exit(False);
  // EL lector de las clausulas (FindUses, el de contains): lo PRIMERO detras
  // de la cabecera, con sus comentarios y sus ramas; los nombres, de todas.
  // Era una regex sobre el codigo con las directivas en blanco
  U := FindUses(ATexto, 0, 'requires');
  Result := U.Found;
  if not Result then
    Exit;
  AIni := U.StartPos;
  ALargo := U.EndPos - U.StartPos + 1;
  for var E in U.Entries + U.OtrasRamas do
    if EntryUnitName(E) <> '' then
      ANombres := ANombres + [EntryUnitName(E)];
end;

function ProjectUnits(const AProject: string; ANeedDproj: Boolean): TArray<TProjectUnit>;
var
  Dpr, Dproj, Enc, Text, E: string;
  U: TUsesClause;
  P: TProjectUnit;
  Includes: TDictionary<string, Boolean>;
begin
  Result := [];
  if ResolveProjectPair(AProject, Dpr, Dproj) <> '' then
    Exit;
  Includes := TDictionary<string, Boolean>.Create;
  try
    try
      Text := PatchLoadText(Dpr, Enc);
      U := FindUses(Text);
      if not U.Found then
        Exit;
      if ANeedDproj and TFile.Exists(Dproj) then
        // one sweep of the .dproj, then O(1) per entry
        for var Incl in AllTagAttr(PatchLoadText(Dproj, Enc), 'DCCReference', 'Include') do
          Includes.AddOrSetValue(ClaveDeInclude(Incl), True);
      // las de TODAS las ramas de un uses partido: la vista, fix-references
      // y la mudanza veian solo la primera
      for E in U.Entries + U.OtrasRamas do
      begin
        P.Include := EntryInclude(E);
        if P.Include = '' then
          Continue; // library units (no `in`) are not project files
        P.UnitName := EntryUnitName(E);
        P.FormName := EntryFormName(E);
        P.InDproj := (not ANeedDproj) or Includes.ContainsKey(ClaveDeInclude(P.Include));
        Result := Result + [P];
      end;
    except
      // un proyecto que otro proceso tiene abierto NO es "no lista nada":
      // borrar una unit contestaba "ningun .dpr la listaba" y el build
      // siguiente fallaba con F1026 (quinta revision). Ese error sube; lo
      // demas (un proyecto que no se entiende) sigue siendo "nada"
      // ...por la CLASE que llega de verdad: TFile.ReadAllBytes lanza
      // EInOutError, y el arreglo esperaba EFOpenError y no corria nunca (un
      // .dpr bloqueado: "ningun .dpr la listaba"; novena revision)
      on E: EInOutError do
        raise;
      on E: EFileStreamError do
        raise;
      on E: Exception do
        Result := [];
    end;
  finally
    Includes.Free;
  end;
end;

function ProjectUnits(const AProject: string): TArray<TProjectUnit>;
begin
  Result := ProjectUnits(AProject, True);
end;

procedure AddUnitsView(const ADproj: string; AReturn: TJSONObject);
var
  Arr: TJSONArray;
  O: TJSONObject;
  P: TProjectUnit;
begin
  Arr := TJSONArray.Create;
  for P in ProjectUnits(ADproj) do
  begin
    O := TJSONObject.Create;
    O.AddPair('unit', P.UnitName);
    O.AddPair('file', P.Include);
    if P.FormName <> '' then
      O.AddPair('form', P.FormName);
    if not P.InDproj then
      O.AddPair('dproj', TJSONBool.Create(False));
    Arr.AddElement(O);
  end;
  AReturn.AddPair('units', Arr);
end;

{ El eco de adduses y removeuses: la clausula de ASec de APasPath tal y como
  quedo, releida del disco; ASinElla si no hay seccion o clausula. ASec = ''
  es el uses de un programa, que tiene uno solo. Estaba dos veces, una en
  cada una, y otra en el adduses del .dpr }
function ClausulaReleida(const APasPath, ASec, ASinElla: string): string;
var
  Text, Enc: string;
  PosSec: Integer;
  U: TUsesClause;
begin
  Result := ASinElla;
  Text := PatchLoadText(APasPath, Enc);
  PosSec := 0;
  if ASec <> '' then
  begin
    PosSec := FinDeSeccion(CodigoPascal(Text), ASec);
    if PosSec = 0 then
      Exit;
  end;
  U := FindUses(Text, PosSec);
  if U.Found then
  begin
    // con el comentario que la ultima entrada lleva detras del ;, en su
    // misma linea (11.3): sigue en el disco y es parte de lo que quedo. La
    // copia acababa en el ; y el eco lo daba por perdido (B16 de la 1.28,
    // medido el 5-nov-2026)
    var Fin := U.EndPos;
    var PC, LC: Integer;
    if ComentarioTrasElCierre(Text, U.EndPos, True, PC, LC) then
      Fin := PC + LC - 1;
    Result := Copy(Text, U.StartPos, Fin - U.StartPos + 1);
  end;
end;

{ El nucleo de adduses sobre un TEXTO (ver AddUsesToUnit): estaba dentro de
  ella, y el insert de delphi_designer escribe la unidad JUNTO con su form,
  todo o nada (1.17.0). }
function UsesConUnidades(var AText: string; const ANames: TArray<string>;
  const ASec, AFichero: string; const AResolutor: TResolutorDeUnidades;
  out AFaltan, AYaEstan, AEnOtra: TArray<string>;
  out ACreada: Boolean): string;
var
  Blank, OtraSec, Nombre, E: string;
  U, UOtra: TUsesClause;
  Entries: TArray<string>;
  PosSec, FinLinea: Integer;
begin
  Result := '';
  AFaltan := [];
  AYaEstan := [];
  AEnOtra := [];
  ACreada := False;
  Blank := CodigoPascal(AText);
  PosSec := FinDeSeccion(Blank, ASec);
  if PosSec = 0 then
    Exit(MsgFmt(SR_ADDUSES_NO_SECTION_FMT, [ASec, AFichero]));
  U := FindUses(AText, PosSec);
  if U.Found then
  begin
    var NoSe := ClausulaQueNoSeReescribe(U, AFichero);
    if NoSe <> '' then
      Exit(NoSe);
  end;
  Entries := U.Entries;
  // La OTRA seccion tambien cuenta: una unit no puede ir en interface e
  // implementation a la vez (E2004 Identifier redeclared; Hermes lo midio
  // el 2026-09-23 con UPkgA en las dos).
  UOtra := UsesDeLaOtraSeccion(AText, Blank, ASec, OtraSec);
  for Nombre in ANames do
    if (U.Found and LocateEntry(U, Nombre, AResolutor, E)) or AResolutor.EnUses(AFaltan, Nombre) then
      AYaEstan := AYaEstan + [Nombre]
    else if UOtra.Found and LocateEntry(UOtra, Nombre, AResolutor, E) then
      AEnOtra := AEnOtra + [Nombre]
    else
    begin
      AFaltan := AFaltan + [Nombre];
      Entries := Entries + [Nombre];
    end;
  if Length(AFaltan) = 0 then
    Exit;
  ACreada := not U.Found;
  if U.Found then
    AText := ReplaceUses(AText, U, Entries)
  else
  begin
    // sin clausula: nace justo debajo de la palabra de seccion, con la
    // separacion que la palabra ya tenia (EstrenaClausula: la del IDE es una
    // linea en blanco); debajo de donde ACABA esa linea, que un comentario
    // abierto en ella se la llevaba dentro (revision de la 1.10.0, medido)
    FinLinea := FinDeLinea(AText, PosSec);
    // ...salvo si detras de la palabra, en su linea, sigue el CODIGO (una unit
    // de una linea: 'unit X; interface implementation end.', que FinDeSeccion
    // encuentra desde el 18-oct-2026): ahi va pegada a la palabra; debajo
    // caia detras del end. final
    if Trim(Copy(Blank, PosSec, FinLinea - PosSec)) <> '' then
      EstrenaClausula(AText, PosSec, string.Join(', ', AFaltan), True)
    else
      EstrenaClausula(AText, FinLinea, string.Join(', ', AFaltan));
  end;
end;

{ Las unidades de ANames que son del PROYECTO de ADpr: para cada nombre, en
  su mismo indice, la ruta relativa de la .pas de ese nombre al lado del .dpr
  o en cualquier carpeta de su arbol (EL recorredor: enlaces legibles; sin
  artefactos del IDE ni la papelera), o '' si no lo es. Solo se miraba la de
  al lado: una en Domain\ entraba como unidad de biblioteca, sin su ruta
  (punto 8 de la 1.18.2). El juez de adduses y de removeuses en un .dpr, uno
  para los dos (D8, 1.20.1). }
function UnidadesDelProyecto(const ADpr: string; const ANames: TArray<string>): TArray<string>;
begin
  var Dir := TPath.GetDirectoryName(ADpr);
  // UN paseo del arbol, no uno por nombre (M10 del revisor de cierre; que
  // siga los enlaces legibles es la regla del recorredor, la del copiador:
  // dcc los sigue igual)
  var Pas := WalkBajoLaRaiz(Dir, ['*.pas']);
  SetLength(Result, Length(ANames));
  for var I := 0 to High(ANames) do
  begin
    Result[I] := '';
    for var F in Pas do
      if SameFileName(TPath.GetFileNameWithoutExtension(F), ANames[I]) then
      begin
        Result[I] := ExtractRelativePath(IncludeTrailingPathDelimiter(Dir), F);
        Break;
      end;
  end;
end;

{ adduses en un .dpr (11.6, David 10-oct-2026: un muro medido moviendo
  SondaOrdenFmx): unidades de BIBLIOTECA - sin ruta: las encuentra el
  compilador por su search path - al uses del programa, por el mismo
  escritor que add-unit (FindUses/ReplaceUses, y EstrenaUsesTrasCabecera si
  no lo tiene). Una unidad del PROYECTO - su .pas junto al .dpr - va por
  add-unit, que escribe su in '...' y su DCCReference: se niega y se dice.
  Idempotente. }
function AddUsesToProgram(const ADpr: string; const ANames: TArray<string>): string;
var
  Text, Enc: string;
  U: TUsesClause;
  Faltan, YaEstan: TArray<string>;
begin
  // una unidad del PROYECTO va por add-unit, con su ruta
  var Propias := UnidadesDelProyecto(ADpr, ANames);
  for var I := 0 to High(ANames) do
    if Propias[I] <> '' then
      Exit(MsgFmt(SR_ADDUSES_UNIDAD_DEL_PROYECTO_FMT, [ANames[I], Propias[I]]));
  EnterFileEdit;
  try
    if not TFile.Exists(ADpr) then
      Exit(NoEsFichero(ADpr, MsgFmt(SR_ADDUSES_NO_FILE_FMT, [ADpr])));
    Text := PatchLoadText(ADpr, Enc);
    U := FindUses(Text);
    var NoSe := ClausulaQueNoSeReescribe(U, TPath.GetFileName(ADpr));
    if NoSe <> '' then
      Exit(NoSe);
    Faltan := [];
    YaEstan := [];
    // "ya esta" por EL juez de dcc (V79): tenia su propio bucle, el nombre exacto
    var R := ResolutorDeUnidades(ADpr);
    for var N in ANames do
    begin
      var E: string;
      if (U.Found and LocateEntry(U, N, R, E)) or R.EnUses(Faltan, N) then
        YaEstan := YaEstan + [N]
      else
        Faltan := Faltan + [N];
    end;
    if Length(Faltan) = 0 then
      Exit(MsgFmt(SN_ADDUSES_PRESENT_FMT, [string.Join(', ', ANames), 'program',
        TPath.GetFileName(ADpr)]));
    var Creada := not U.Found;
    if U.Found then
      Text := ReplaceUses(Text, U, U.Entries + Faltan)
    else if not EstrenaUsesTrasCabecera(Text, string.Join(', ', Faltan)) then
      Exit(MsgFmt(SR_UNIT_NO_USES_FMT, [TPath.GetFileName(ADpr)]));
    PatchSaveText(ADpr, Text, Enc);
    // el eco, releido del disco: la clausula tal y como ha quedado
    var Clausula := ClausulaReleida(ADpr, '', '(?)');
    Result := MsgFmt(SN_ADDUSES_ADDED_FMT, ['program', TPath.GetFileName(ADpr),
      string.Join(', ', Faltan),
      IfThen(Length(YaEstan) > 0, MsgFmt(SN_ADDUSES_SOME_PRESENT_FMT, [string.Join(', ', YaEstan)]), ''),
      IfThen(Creada, MsgText(SN_ADDUSES_CREADA_PROGRAMA), ''),
      Clausula]);
  finally
    LeaveFileEdit;
  end;
end;

const
  // los ficheros cuyo uses editan adduses y removeuses (un .dpk lleva
  // contains/requires: add-unit y add-requires); cada puerta tenia su copia
  // de la lista (C15 de la 1.26)
  EXTS_CON_USES: array[0..1] of string = ('.pas', '.dpr');

{ adduses de delphi_edit (David, 2026-09-23): una unit entra en el uses de
  OTRA unit, en la seccion que se diga, y la clausula la escribe el motor:
  comas, terminador y, si no existia, la clausula entera bajo la palabra de
  seccion. Es el espejo de add-unit para el .dpr: alli membresia de
  proyecto, aqui una dependencia entre units. Idempotente. Un solo escritor
  del formato: FindUses/ReplaceUses, los mismos del .dpr y el .dpk. }
function AddUsesToUnit(const APasPath: string; const ANames: TArray<string>;
  const ASection: string): string;
var
  Text, Enc, Sec, OtraSec, Nombre, Clausula: string;
  Names, Faltan, YaEstan, EnOtra: TArray<string>;
  Creada: Boolean;
begin
  if not TieneExtension(APasPath, EXTS_CON_USES) then
    Exit(MsgFmt(SR_ADDUSES_NOT_PAS_FMT, [TPath.GetFileName(APasPath)]));
  Names := Recortados(ANames);
  if Length(Names) = 0 then
    Exit(MsgText(SR_ADDUSES_NEED_NAMES));
  for Nombre in Names do
    if not EsIdentificador(Nombre, True) then
      Exit(MsgFmt(SR_ADDUSES_BAD_NAME_FMT, [Nombre]));
  // un programa tiene UN uses: section no aplica
  if SameText(TPath.GetExtension(APasPath), '.dpr') then
    Exit(AddUsesToProgram(APasPath, Names));
  Sec := LowerCase(ASection.Trim);
  if Sec = '' then
    Sec := 'implementation';
  if not MatchText(Sec, ['interface', 'implementation']) then
    Exit(MsgFmt(SR_ADDUSES_BAD_SECTION_FMT, [ASection]));
  OtraSec := IfThen(Sec = 'interface', 'implementation', 'interface');
  EnterFileEdit;
  try
    if not TFile.Exists(APasPath) then
      Exit(NoEsFichero(APasPath, MsgFmt(SR_ADDUSES_NO_FILE_FMT, [APasPath])));
    Text := PatchLoadText(APasPath, Enc);
    Result := UsesConUnidades(Text, Names, Sec, TPath.GetFileName(APasPath), ResolutorDeUnidades(APasPath),
      Faltan, YaEstan, EnOtra, Creada);
    if Result <> '' then
      Exit;
    if (Length(Faltan) = 0) and (Length(EnOtra) > 0) then
      Exit(MsgFmt(SN_ADDUSES_PRESENT_OTHER_FMT, [string.Join(', ', EnOtra), OtraSec,
        TPath.GetFileName(APasPath)]));
    if Length(Faltan) = 0 then
      Exit(MsgFmt(SN_ADDUSES_PRESENT_FMT, [string.Join(', ', Names), Sec,
        TPath.GetFileName(APasPath)]));
    PatchSaveText(APasPath, Text, Enc);
    // el eco, releido del disco: la clausula tal y como ha quedado
    Clausula := ClausulaReleida(APasPath, Sec, '(?)');
    Result := MsgFmt(SN_ADDUSES_ADDED_FMT, [Sec, TPath.GetFileName(APasPath),
      string.Join(', ', Faltan),
      IfThen(Length(YaEstan) > 0, MsgFmt(SN_ADDUSES_SOME_PRESENT_FMT, [string.Join(', ', YaEstan)]), '') +
      IfThen(Length(EnOtra) > 0, MsgFmt(SN_ADDUSES_IN_OTHER_FMT, [OtraSec, string.Join(', ', EnOtra)]), ''),
      IfThen(Creada, MsgFmt(SN_ADDUSES_CREATED_FMT, [Sec]), ''),
      Clausula]);
  finally
    LeaveFileEdit;
  end;
end;

{ removeuses en un .dpr: la inversa de AddUsesToProgram (D8 de la auditoria
  de la 1.20.1, medido: adduses System.JSON entraba en el .dpr y nada la
  sacaba - removeuses contestaba USES-014 y remitia a remove-unit, que pide
  un .pas). Solo unidades de BIBLIOTECA: una del PROYECTO - su .pas en el
  arbol del .dpr, el juez de adduses, o una entrada con su in '...' aunque el
  .pas viva fuera - va por remove-unit, que quita tambien su CreateForm y su
  DCCReference. Si la clausula se queda vacia se va entera. }
function RemoveUsesFromProgram(const ADpr: string; const ANames: TArray<string>): string;
var
  Text, Enc, E: string;
  U: TUsesClause;
  Entries, Quitadas, NoEstaban: TArray<string>;
begin
  // el arbol se recorre FUERA del cerrojo, como en adduses; y solo cuenta
  // para las que estan en el uses: la que no esta es USES-017, no remove-unit.
  // Se mira la unidad que dcc toma por ese nombre - la de la entrada que se
  // encuentra -, no el nombre dicho: removeuses=Graphics sobre un Vcl.Graphics,
  // con un Graphics.pas en una subcarpeta que dcc no mira, mandaba a
  // remove-unit una unidad de la biblioteca (V107)
  var R := ResolutorDeUnidades(ADpr);
  var Resueltas: TArray<string> := nil;
  for var N in ANames do
    Resueltas := Resueltas + [R.Resuelve(N)];
  var Propias := UnidadesDelProyecto(ADpr, Resueltas);
  EnterFileEdit;
  try
    if not TFile.Exists(ADpr) then
      Exit(NoEsFichero(ADpr, MsgFmt(SR_ADDUSES_NO_FILE_FMT, [ADpr])));
    Text := PatchLoadText(ADpr, Enc);
    U := FindUses(Text);
    if not U.Found then
      Exit(MsgFmt(SN_REMOVEUSES_NO_CLAUSE_FMT, ['program', TPath.GetFileName(ADpr)]));
    var NoSe := ClausulaQueNoSeReescribe(U, TPath.GetFileName(ADpr));
    if NoSe <> '' then
      Exit(NoSe);
    Entries := U.Entries;
    Quitadas := [];
    NoEstaban := [];
    for var I := 0 to High(ANames) do
      if LocateEntry(U, ANames[I], R, E) then
      begin
        // del proyecto: con su in '...' aunque el .pas viva fuera del arbol,
        // o con su .pas en el
        if EntryInclude(E) <> '' then
          Exit(MsgFmt(SR_REMOVEUSES_UNIDAD_DEL_PROYECTO_FMT, [ANames[I], EntryInclude(E)]));
        if Propias[I] <> '' then
          Exit(MsgFmt(SR_REMOVEUSES_UNIDAD_DEL_PROYECTO_FMT, [ANames[I], Propias[I]]));
        Quitadas := Quitadas + [ANames[I]];
        // la entrada que se encontro, como esta escrita (Forms quita Vcl.Forms)
        Entries := EntriesWithout(Entries, EntryUnitName(E));
      end
      else
        NoEstaban := NoEstaban + [ANames[I]];
    if Length(Quitadas) = 0 then
      Exit(MsgFmt(SN_REMOVEUSES_ABSENT_FMT, [string.Join(', ', ANames), 'program',
        TPath.GetFileName(ADpr)]));
    Text := ReplaceUses(Text, U, Entries); // vacia: la clausula entera fuera
    PatchSaveText(ADpr, Text, Enc);
    // el eco, releido del disco
    Result := MsgFmt(SN_REMOVEUSES_REMOVED_FMT, ['program', TPath.GetFileName(ADpr),
      string.Join(', ', Quitadas),
      IfThen(Length(NoEstaban) > 0, MsgFmt(SN_REMOVEUSES_SOME_ABSENT_FMT, [string.Join(', ', NoEstaban)]), ''),
      ClausulaReleida(ADpr, '', MsgFmt(SN_REMOVEUSES_GONE_FMT, ['program']))]);
  finally
    LeaveFileEdit;
  end;
end;

{ removeuses: la inversa de adduses. Si la clausula se queda vacia se va
  entera, con el salto de linea que la seguia: un `uses ;` no compila. }
function RemoveUsesFromUnit(const APasPath: string; const ANames: TArray<string>;
  const ASection: string): string;
var
  Text, Enc, Sec, Nombre, E, Clausula, Blank: string;
  U: TUsesClause;
  Names, Entries, Quitadas, NoEstaban: TArray<string>;
  PosSec: Integer;
  Resolutor: TResolutorDeUnidades; // EL juez de "es la misma unidad" (V79)

  // lo de ANombres que esta en la uses de la OTRA seccion, dicho con la
  // section que lo quita; '' si alli no esta nada (Hermes, 1.18.0). Lee Text
  // y Blank como estan: se llama antes de reescribir la clausula.
  function EnLaOtra(const ANombres: TArray<string>): string;
  var
    Otra, N, Ent: string;
    UO: TUsesClause;
    Estan: TArray<string>;
  begin
    Result := '';
    UO := UsesDeLaOtraSeccion(Text, Blank, Sec, Otra);
    if not UO.Found then
      Exit;
    Estan := [];
    for N in ANombres do
      if LocateEntry(UO, N, Resolutor, Ent) then
        Estan := Estan + [N];
    if Length(Estan) > 0 then
      Result := MsgFmt(SN_REMOVEUSES_EN_LA_OTRA_FMT, [string.Join(', ', Estan), Otra, Otra]);
  end;

begin
  if not TieneExtension(APasPath, EXTS_CON_USES) then
    Exit(MsgFmt(SR_REMOVEUSES_NOT_PAS_FMT, [TPath.GetFileName(APasPath)]));
  Names := Recortados(ANames);
  if Length(Names) = 0 then
    Exit(MsgText(SR_REMOVEUSES_NEED_NAMES));
  for Nombre in Names do
    if not EsIdentificador(Nombre, True) then
      Exit(MsgFmt(SR_ADDUSES_BAD_NAME_FMT, [Nombre]));
  // un programa tiene UN uses: section no aplica
  if SameText(TPath.GetExtension(APasPath), '.dpr') then
    Exit(RemoveUsesFromProgram(APasPath, Names));
  Sec := LowerCase(ASection.Trim);
  if Sec = '' then
    Sec := 'implementation';
  if not MatchText(Sec, ['interface', 'implementation']) then
    Exit(MsgFmt(SR_ADDUSES_BAD_SECTION_FMT, [ASection]));
  Resolutor := ResolutorDeUnidades(APasPath);
  EnterFileEdit;
  try
    if not TFile.Exists(APasPath) then
      Exit(NoEsFichero(APasPath, MsgFmt(SR_ADDUSES_NO_FILE_FMT, [APasPath])));
    Text := PatchLoadText(APasPath, Enc);
    Blank := CodigoPascal(Text);
    PosSec := FinDeSeccion(Blank, Sec);
    if PosSec = 0 then
      Exit(MsgFmt(SR_ADDUSES_NO_SECTION_FMT, [Sec, TPath.GetFileName(APasPath)]));
    U := FindUses(Text, PosSec);
    if not U.Found then
      Exit(MsgFmt(SN_REMOVEUSES_NO_CLAUSE_FMT, [Sec, TPath.GetFileName(APasPath)]) +
        EnLaOtra(Names));
    var NoSe := ClausulaQueNoSeReescribe(U, TPath.GetFileName(APasPath));
    if NoSe <> '' then
      Exit(NoSe);
    Entries := U.Entries;
    Quitadas := [];
    NoEstaban := [];
    for Nombre in Names do
      if LocateEntry(U, Nombre, Resolutor, E) then
      begin
        Quitadas := Quitadas + [Nombre];
        // la entrada que se encontro, como esta escrita (Forms quita Vcl.Forms)
        Entries := EntriesWithout(Entries, EntryUnitName(E));
      end
      else
        NoEstaban := NoEstaban + [Nombre];
    if Length(Quitadas) = 0 then
      Exit(MsgFmt(SN_REMOVEUSES_ABSENT_FMT, [string.Join(', ', Names), Sec,
        TPath.GetFileName(APasPath)]) + EnLaOtra(Names));
    var EnOtra := EnLaOtra(NoEstaban); // antes de reescribir: lee Text
    Text := ReplaceUses(Text, U, Entries); // vacia: la clausula entera fuera
    PatchSaveText(APasPath, Text, Enc);
    // el eco, releido del disco
    Clausula := ClausulaReleida(APasPath, Sec, MsgFmt(SN_REMOVEUSES_GONE_FMT, [Sec]));
    Result := MsgFmt(SN_REMOVEUSES_REMOVED_FMT, [Sec, TPath.GetFileName(APasPath),
      string.Join(', ', Quitadas),
      IfThen(Length(NoEstaban) > 0, MsgFmt(SN_REMOVEUSES_SOME_ABSENT_FMT, [string.Join(', ', NoEstaban)]) + EnOtra, ''),
      Clausula]);
  finally
    LeaveFileEdit;
  end;
end;

{ La subida por carpetas, compartida: desde ADesde hasta el borde de la jaula
  (ReadPathDenied) y con el tope de la casa para el modo sin jaula
  (Ancestros, NIVELES_DE_SUBIDA), acumulando en ADirs sin repetir. Un solo
  buscador para ProjectsUsingUnit y WorkspacePackagesWithUnit (24-sep-2026),
  no dos. }
procedure SubeCarpetas(const ADesde: string; var ADirs: TArray<string>);
begin
  for var D in Ancestros(ADesde, NIVELES_DE_SUBIDA) do
  begin
    if ReadPathDenied(D) <> '' then
      Break;
    if not RutaEnLista(D, ADirs) then
      ADirs := ADirs + [D];
  end;
end;

{ Las units de un proyecto (.dpr/.dpk) para BUSCAR una entre ellas, sin leer
  el .dproj: si el proyecto no se puede leer (ACL, otro proceso), la negativa
  dice que se leia para saber si lista la unit - salia el SYS-028 pelado y el
  agente lo tomaba por un intento de escribirlo (decima revision). Los dos
  buscadores eran gemelos. }
function UnitsParaBuscar(const AProyecto, AUnit: string): TArray<TProjectUnit>;
begin
  try
    Result := ProjectUnits(AProyecto, False);
  except
    on E: Exception do
    begin
      var Causa := MotivoDelSistema(E.Message);
      if Causa = '' then
        Causa := E.Message;
      raise Exception.Create(MsgConCausa(SR_PROYECTO_NO_LEIDO_AL_BUSCAR_FMT, Causa,
        [TPath.GetFileName(AProyecto), AUnit, Causa]));
    end;
  end;
end;

{ Los sitios donde buscar un proyecto que liste una unidad: cada carpeta de la
  subida (SubeCarpetas) y sus subcarpetas inmediatas que esta sesion puede
  leer. Dos trabajos viven en carpetas HERMANAS (app\ y scratch\, pkgA\ y
  pkgB\), no una encima de otra. Un listado por carpeta, sin recursion. Lo
  miraban solo los paquetes: delete y move solo subian, y el .dpr de la
  carpeta de al lado se quedaba listando la unidad borrada (H5-02 de Hermes,
  1.19.2). Un recorredor para los dos, no dos. }
function SitiosDeProyectos(const ADirs: TArray<string>): TArray<string>;
var
  D: string;
begin
  Result := [];
  for D in ADirs do
  begin
    if not TDirectory.Exists(D) then
      Continue;
    Result := Result + [D];
    try
      // una subcarpeta que la jaula no deja leer (un enlace a fuera) no se
      // mira: se leian sus .dpk de detras (medida M1)
      for var Sub in TDirectory.GetDirectories(D) do
        if not RutaEnLista(Sub, ADirs) and (ReadPathDenied(Sub) = '') then
          Result := Result + [Sub];
    except
      // una carpeta que no se deja listar no es motivo para no mirar el resto
    end;
  end;
end;

function WorkspacePackagesWithUnit(const ADpkPath, AUnitName: string): TArray<string>;
var
  Dirs: TArray<string>;
  D, F: string;
  P: TProjectUnit;
begin
  Result := [];
  Dirs := [];
  SubeCarpetas(TPath.GetDirectoryName(TPath.GetFullPath(ADpkPath)), Dirs);
  for D in SitiosDeProyectos(Dirs) do
  begin
    for F in TDirectory.GetFiles(D, '*.dpk') do
    begin
      if SameFileName(TPath.GetFullPath(F), TPath.GetFullPath(ADpkPath)) then
        Continue;
      for P in UnitsParaBuscar(F, AUnitName) do // el .dpk decide; sin leer .dproj
        if MismoIdentificador(P.UnitName, AUnitName) then
        begin
          Result := Result + [TPath.GetFullPath(F)];
          Break;
        end;
    end;
  end;
end;

function ProyectoListaUnidad(const AProyecto, APasPath: string;
  AConSuFuente: Boolean): Boolean;
var
  F, Stem: string;
begin
  Result := False;
  F := AProyecto;
  if SameText(TPath.GetExtension(F), '.dproj') then
    F := DprDe(F);
  if not EsFuentePrincipal(F) or not TFile.Exists(F) then
    Exit;
  if AConSuFuente and (NormPath(F) = NormPath(APasPath)) then
    Exit(True);
  // el nombre de la unit sale del nombre LARGO: el de UPROVE~1.PAS no es UPROVE~1
  Stem := TPath.GetFileNameWithoutExtension(LongCanonical(APasPath));
  for var P in UnitsParaBuscar(F, Stem) do
    if MismoIdentificador(P.UnitName, Stem) and
      MismoInclude(F, P.Include, APasPath) then // EL resolutor (V204)
      Exit(True);
end;

function ProjectsUsingUnit(const APasPath: string): TArray<string>;
var
  Dir, D, F: string;
  Dirs: TArray<string>;
begin
  Result := [];
  Dir := TPath.GetDirectoryName(TPath.GetFullPath(APasPath));
  // Se sube desde la carpeta de la unit HASTA EL BORDE DE LA JAULA. Solo
  // miraba la carpeta y su madre, asi que en cuanto un proyecto tenia
  // profundidad de verdad (Dominio\Modelos\UCliente.pas) mover esa unit
  // contestaba "ningun .dpr lo listaba" y dejaba el proyecto sin compilar
  // (medido en vivo el 2026-09-21). La estructura la decide el programador:
  // el buscador no puede suponer que es plana. El freno es el mismo que el
  // de Lsp.Session al buscar un .dproj - nunca mas alla de lo que este
  // workspace puede leer - y un tope de niveles para el modo sin jaula, que
  // si no subiria hasta la raiz del disco. Cada nivel es UN listado de *.dpr
  // sin recursion: barato.
  Dirs := [];
  SubeCarpetas(Dir, Dirs);
  // ...y las carpetas de al lado de cada nivel (SitiosDeProyectos): el .dpr
  // de app\ que lista ..\scratch\U.pas no esta en la subida desde scratch\
  for D in SitiosDeProyectos(Dirs) do
  begin
    for F in TDirectory.GetFiles(D, '*.dp?') do // .dpr y .dpk, no .dproj
      if EsFuentePrincipal(F) then
        if ProyectoListaUnidad(F, APasPath) then // the .dpr decides; no .dproj read
          Result := Result + [F];
  end;
end;

function FormsDeLasClases(const AProyecto: string; const AClases: TArray<string>;
  const AExt: string): TArray<TFormDelProyecto>;
begin
  Result := [];
  for var U in ProjectUnits(AProyecto, False) do
  begin
    if (U.FormName = '') or not MatchText('T' + U.FormName, AClases) then
      Continue;
    var Ruta := ChangeFileExt(RutaDesde(TPath.GetDirectoryName(AProyecto), U.Include), AExt);
    if not TFile.Exists(Ruta) or EsEnlace(Ruta) or (ReadPathDenied(Ruta) <> '') then
      Continue;
    var Texto, Enc: string;
    if TextoDeDesigner(Ruta, Texto, Enc) <> '' then
      Continue;
    for var L in LineasDeForm(SplitToLines(Texto)) do
      if L.Clase = clfObjeto then
      begin
        if MatchText(L.ClaseObj, AClases) then
        begin
          var F: TFormDelProyecto;
          F.Clase := L.ClaseObj;
          F.Designer := Ruta;
          F.Unidad := U.UnitName;
          Result := Result + [F];
        end;
        Break;
      end;
  end;
end;

{ ================================================ rutas que cruzan un borde }

function DirectivasDeFichero(const ATexto: string): TArray<TDirectivaFichero>;
var
  D: TDirectivaFichero;
  Maximo: Integer;
begin
  Result := [];
  // por el lector UNICO de directivas: una comentada (tambien con //) o
  // dentro de una cadena ya no cuenta, y la forma parentesis-asterisco si
  for var X in DirectivasPascal(ATexto) do
  begin
    if DirectivaDeFicheroDe(X.Nombre) = dfNinguna then
      Continue;
    // {$R a.res a.rc}: el .rc del que sale el .res es la SEGUNDA ruta de la
    // misma directiva, y tambien es un fichero (revision 26-sep-2026)
    Maximo := 1;
    if DirectivaDeFicheroDe(X.Nombre) = dfRecurso then
      Maximo := 2;
    // los trozos, por EL troceador (Lsp.Pascal, el que lee tambien la vista
    // FMX del renderizador)
    for var T in TrozosDeDirectiva(X.Argumento, Maximo) do
      // Un comodin es el andamiaje del IDE ({$R *.res}, {$R *.dfm}); un
      // caracter suelto, un interruptor ({$I +}), no un fichero.
      if not ((T.Texto = '') or T.Texto.Contains('*') or
         ((T.Comilla = #0) and ((Length(T.Texto) <= 1) or CharInSet(T.Texto[1], ['+', '-'])))) then
      begin
        D.Texto := Copy(ATexto, X.Inicio, X.Largo);
        D.Ruta := T.Texto;
        D.Comilla := T.Comilla;
        D.Inicio := X.InicioArg + T.Inicio - 1;
        D.Largo := Length(T.Texto);
        Result := Result + [D];
      end;
  end;
end;

end.
