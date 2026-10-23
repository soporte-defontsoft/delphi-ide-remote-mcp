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

  TProjectUnit = record
    UnitName: string;
    Include: string;     // as written in the .dpr ('Unit1.pas', 'src\X.pas')
    FormName: string;    // from the {Form} comment, '' for plain units
    InDproj: Boolean;    // has its <DCCReference>
  end;

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
  AEsperaMs: Cardinal; ARaizDelCreador: TRaizDeDiseno = rdDesconocida);
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

{ Re-points an existing entry to a new path/name (the file was already moved
  or renamed by the caller; the new file's header decides the unit name). }
function RenameProjectUnit(const AProject, AOldPasPath, ANewPasPath: string): string;

{ Lo que un RENAME de unit reescribe ademas del .dpr/.dpk y su .dproj: cada
  unit que el proyecto lista (sus uses y sus UnitVieja.X) y la unit en su
  sitio nuevo, en absoluto y sin repetir; en ANoEscritos, lo que no puede
  escribir (una ruta que nadie resuelve, fuera de las raices) y que la
  respuesta nombra. UNA lista: la foto del todo-o-nada (la del propio rename
  y la del move que lo llama) y el bucle que reescribe miran la misma. }
function FicherosDelRename(const AProject, ANewPasPath: string;
  out ANoEscritos: TArray<string>): TArray<string>;

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

{ Projects (.dproj paths) in ADir and its parent that list APasPath. For the
  file tools: delete/move a unit keeps the projects that use it consistent. }
{ AAlsoDir: una segunda carpeta desde la que subir (la de DESTINO de un move). }
function ProjectsUsingUnit(const APasPath: string; const AAlsoDir: string = ''): TArray<string>;
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

{ adduses de delphi_edit: nombres de unit al uses de una seccion (interface o
  implementation) de un .pas; la clausula la escribe el motor. }
function AddUsesToUnit(const APasPath: string; const ANames: TArray<string>;
  const ASection: string): string;
{ El nucleo de adduses sobre un TEXTO: ANames (identificadores ya
  validados) entran en el uses de ASec (interface|implementation) y AText
  sale con la clausula reescrita. '' = hecho, o la negativa (sin esa
  seccion, una clausula en ramas IFDEF). AFaltan entran; AYaEstan ya
  estaban; AEnOtra estan en la otra seccion y no entran (E2004); ACreada,
  la clausula nacio. AFichero, solo para los mensajes. }
function UsesConUnidades(var AText: string; const ANames: TArray<string>;
  const ASec, AFichero: string; out AFaltan, AYaEstan, AEnOtra: TArray<string>;
  out ACreada: Boolean): string;
{ removeuses de delphi_edit: la inversa; la clausula se va entera si queda vacia. }
function RemoveUsesFromUnit(const APasPath: string; const ANames: TArray<string>;
  const ASection: string): string;

function RenombrarIdentificadorUnit(const APath, AViejo, ANuevo: string): Integer;

{ La ruta de APas vista desde la carpeta de ADpr, en la forma que escribe el
  IDE (Sub\X.pas, ..\..\shared\X.pas; absoluta solo en otra unidad). EL
  nombrador de rutas relativas: las units de un proyecto, los proyectos de
  un grupo, los search paths y las directivas que re-apunta una mudanza. }
function IncludeFor(const ADpr, APas: string): string;
{ La inversa: la ruta COMPLETA de lo que un .dpr lista como AInclude (Sub\X.pas,
  ..\shared\X.pas, o absoluta), vista desde su carpeta. EL lector de lo que
  escribe IncludeFor. }
function RutaDeInclude(const ADpr, AInclude: string): string;

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
  comodines (R *.res) ni interruptores; de R a.res a.rc solo la primera. EL
  lector: la jaula del build (Lsp.BuildRunner) y la mudanza lo comparten. }
function DirectivasDeFichero(const ATexto: string): TArray<TDirectivaFichero>;

{ Donde empieza (1-based) el condicional ABIERTO mas externo al final de
  ATexto - el primer IF, IFDEF, IFNDEF o IFOPT sin su ENDIF/IFEND -; 0 si no
  queda ninguno abierto. Por EL lector de directivas. La frontera de un
  insert lo pregunta: un initialization dentro de un IFDEF DEBUG metia la
  rutina DENTRO del bloque (W1 del revisor de cierre de la 1.18.2). }
function PrimerCondicionalAbierto(const ATexto: string): Integer;

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

{ La mudanza de AViejo a ANuevo (una carpeta o un fichero; delphi_move, o su
  copia): re-apunta toda ruta RELATIVA que cruza el borde de lo movido,
  porque un relativo que sale de ahi deja de apuntar a lo mismo. DENTRO de
  lo nuevo: las units de fuera que lista cada proyecto (.dpr/.dpk y
  DCCReference), las rutas de busqueda y de salida del .dproj, las
  directivas $I/$R/$L y los proyectos de cada grupo. Y si no es copia,
  FUERA, en todo el workspace: las directivas, units, rutas y grupos que
  apuntaban dentro. '' si no habia nada que re-apuntar. }
function ReubicaArbol(const AViejo, ANuevo: string; ACopia: Boolean): string;

implementation

uses
  System.IOUtils,
  System.StrUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  System.Character,
  Lsp.Patch,
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
  Lsp.Settings,
  Lsp.TodoONada,
  Lsp.Args;

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

function NormPath(const P: string): string;
begin
  // la forma LARGA (Lsp.Rutas.LongCanonical): UPROVE~1.PAS y
  // UProveedorModelo.pas son el mismo fichero (sexta revision). Salvo un
  // UNC que no es de ningun sitio declarado: estas rutas salen de lo que
  // dice un .dpr, y alargarla abria SMB hacia ese host (octava revision)
  // ...ni uno con prefijo de dispositivo (\\?\UNC\host\...): la pregunta de
  // todos (Lsp.Guard.RutaSinTocarElDisco; novena revision)
  if RutaSinTocarElDisco(P) then
    Exit(P.ToLower);
  Result := LongCanonical(P).ToLower;
end;

function ResolveProjectPair(const AProject: string; out ADpr, ADproj: string): string;
var
  Ext: string;
begin
  Result := '';
  ADpr := '';
  ADproj := '';
  if AProject.Trim = '' then
    Exit(MsgText(SR_UNIT_NEED_PROJECT));
  Ext := TPath.GetExtension(AProject).ToLower;
  if (Ext <> '.dpr') and (Ext <> '.dpk') and (Ext <> '.dproj') then
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
  if Full.ToLower.StartsWith(Base.ToLower) then
    Result := Full.Substring(Length(Base))
  else if SameText(TPath.GetPathRoot(Full), TPath.GetPathRoot(Base)) then
    Result := ExtractRelativePath(Base, Full) // ..\..\shared\X.pas, the IDE's form
  else
    Result := Full; // another drive: no relative form exists
end;

function RutaDeInclude(const ADpr, AInclude: string): string;
begin
  Result := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(TPath.GetFullPath(ADpr)), AInclude));
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
    Xml, Enc, Dir: string;
  begin
    Result := '';
    if (ADprojDe = '') or not TFile.Exists(ADprojDe) then
      Exit;
    Xml := PatchLoadText(ADprojDe, Enc);
    Dir := TPath.GetDirectoryName(TPath.GetFullPath(ADprojDe));
    // por EL analisis del .dproj, y por la ruta que resuelve el Include (como
    // ProyectoListaUnidad), no por como va escrito
    for var T in TramosDeEtiqueta(Xml, 'DCCReference', True) do
      if NormPath(TPath.Combine(Dir, AtributoDeTramo(Xml, T, 'DCCReference', 'Include'))) =
         NormPath(APasPath) then
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
  AEsperaMs: Cardinal; ARaizDelCreador: TRaizDeDiseno);
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
  // 3) la clase de la unidad por su cadena, contra la tabla de su marco
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
  if TPath.GetExtension(APasPath).ToLower <> '.pas' then
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
      AInfo.FormType := TPath.GetExtension(Form).Substring(1).ToLower;
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

type
  TUsesClause = record
    Found: Boolean;
    StartPos: Integer;  // index (1-based) of the 'u' of 'uses'
    EndPos: Integer;    // index of the closing ';'
    Entries: TArray<string>; // raw entry texts, trimmed
    Keyword: string;    // 'uses' (program/library) o 'contains' (package)
    // Partida en RAMAS ({$IFDEF X} a, b; {$ELSE} c; {$ENDIF}): su ';' cierra
    // una rama y las otras siguen detras. Se LEEN (OtrasRamas) y ningun
    // escritor la toca: no sabe en que rama va una unit (el muro del 26-sep).
    EnRamas: Boolean;
    OtrasRamas: TArray<string>;
    // donde acaba la clausula ENTERA: EndPos, o en ramas, el condicional que
    // las cierra (lo que mira el renombrado de una unit: sus entradas)
    FinRamas: Integer;
  end;

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

{ Splits the clause body on top-level commas (outside quotes, comments and
  directives; those stay glued to the entry they precede or follow). }
function SplitEntries(const Body: string): TArray<string>;
var
  I, N: Integer;
  Cur: string;
  L: TStringList;
begin
  L := TStringList.Create;
  try
    Cur := '';
    I := 1;
    while I <= Length(Body) do
    begin
      N := CommentLen(Body, I);
      if N = 0 then
        N := QuoteLen(Body, I);
      if N > 0 then
      begin
        Cur := Cur + Copy(Body, I, N);
        Inc(I, N);
        Continue;
      end;
      if Body[I] = ',' then
      begin
        if Cur.Trim <> '' then
          L.Add(Cur.Trim);
        Cur := '';
      end
      else
        Cur := Cur + Body[I];
      Inc(I);
    end;
    if Cur.Trim <> '' then
      L.Add(Cur.Trim);
    Result := L.ToStringArray;
  finally
    L.Free;
  end;
end;

{ La clausula de units del proyecto: `uses` tras `program X;` (o `library`),
  y `contains` tras `package X;` - en un paquete la `requires` que va antes
  se salta entera. Nunca una dentro de un comentario; cerrada por el primer
  `;` fuera de comillas y comentarios. }
const
  // Los condicionales de Pascal: los que ABREN, los que cambian de RAMA y los
  // que CIERRAN. Una lista para los lectores de un uses de esta unidad: estaba
  // escrita a mano en CondicionalesAbiertos, EntradasDeOtrasRamas y EsEnvuelta
  CONDICIONAL_ABRE: array[0..3] of string = ('IF', 'IFDEF', 'IFNDEF', 'IFOPT');
  CONDICIONAL_RAMA: array[0..1] of string = ('ELSE', 'ELSEIF');
  CONDICIONAL_CIERRA: array[0..1] of string = ('ENDIF', 'IFEND');
  // las combinaciones de ramas que ListaEnCadaRama recorre como mucho
  MAX_COMBINACIONES_DE_RAMAS = 256;

// EL paseo por los condicionales de ATexto (IF, IFDEF, IFNDEF e IFOPT abren;
// ENDIF e IFEND cierran), por EL lector de directivas: AAbiertos, los que
// quedan abiertos al final (negativo con un cierre de mas), y APrimero, donde
// empieza el abierto mas EXTERNO (0 si no queda ninguno)
procedure RecorreCondicionales(const ATexto: string; out AAbiertos, APrimero: Integer);
var
  Pila: TArray<Integer>;
begin
  AAbiertos := 0;
  Pila := [];
  for var D in DirectivasPascal(ATexto) do
    if MatchText(D.Nombre, CONDICIONAL_ABRE) then
    begin
      Inc(AAbiertos);
      Pila := Pila + [D.Inicio];
    end
    else if MatchText(D.Nombre, CONDICIONAL_CIERRA) then
    begin
      Dec(AAbiertos);
      if Length(Pila) > 0 then
        SetLength(Pila, Length(Pila) - 1);
    end;
  APrimero := 0;
  if Length(Pila) > 0 then
    APrimero := Pila[0];
end;

// Los condicionales que quedan ABIERTOS al final de ATexto.
function CondicionalesAbiertos(const ATexto: string): Integer;
var
  Primero: Integer;
begin
  RecorreCondicionales(ATexto, Result, Primero);
end;

function PrimerCondicionalAbierto(const ATexto: string): Integer;
var
  Abiertos: Integer;
begin
  RecorreCondicionales(ATexto, Abiertos, Result);
end;

// True si ATexto lleva alguna directiva condicional (abre, cambia de rama o
// cierra): entre una coma y el nombre de su entrada, las pone en regiones
// distintas (EntriesWithout)
function LlevaCondicional(const ATexto: string): Boolean;
begin
  for var D in DirectivasPascal(ATexto) do
    if MatchText(D.Nombre, CONDICIONAL_ABRE) or MatchText(D.Nombre, CONDICIONAL_RAMA) or
       MatchText(D.Nombre, CONDICIONAL_CIERRA) then
      Exit(True);
  Result := False;
end;

// LA COMPROBACION DE UN USES CON CONDICIONALES, la unica gramatica propia de
// esta unidad para ellos: no hay juez, dcc solo compila la rama de los
// simbolos que tiene. En CADA combinacion de ramas, lo activo tiene que ser
// una lista - entradas separadas por comas, sin coma al principio, al final
// ni dos seguidas, y al menos una entrada. Dos trozos de entrada seguidos
// con solo una directiva en medio cuentan como una entrada partida, no como
// dos. 1 = alguna rama la rompe; 0 = todas bien; -1 = no se puede juzgar (un
// condicional que abre o cierra fuera de la clausula, o mas de
// MAX_COMBINACIONES_DE_RAMAS): quien pregunta no niega por eso. ACuerpo, la
// clausula sin su palabra (uses / contains), con o sin su ';'. Revisor de
// version de la 1.18.0: removeuses dejaba una coma fuera de su condicional.
function ListaEnCadaRama(const ACuerpo: string): Integer;
type
  TEvento = record
    Clase: Integer; // 0 un trozo de entrada, 1 una coma, 2 abre, 3 rama, 4 cierra
    Bloque: Integer;
  end;
var
  Eventos: TArray<TEvento>;
  Ramas: TArray<Integer>;     // las ramas de cada bloque
  ConElse: TArray<Boolean>;   // ...y si una de ellas es un ELSE (si no, cabe "ninguna")
  Pila: TArray<Integer>;

  procedure Anota(AClase, ABloque: Integer);
  var
    Ev: TEvento;
  begin
    Ev.Clase := AClase;
    Ev.Bloque := ABloque;
    Eventos := Eventos + [Ev];
  end;

begin
  Eventos := [];
  Ramas := [];
  ConElse := [];
  Pila := [];
  var Clases := ClasesPascal(ACuerpo);
  var Ds := DirectivasPascal(ACuerpo);
  var DI := 0;
  var EnEntrada := False;
  var I := 1;
  while I <= Length(ACuerpo) do
  begin
    if (DI <= High(Ds)) and (Ds[DI].Inicio = I) then
    begin
      var Nombre := Ds[DI].Nombre;
      if MatchText(Nombre, CONDICIONAL_ABRE) then
      begin
        Ramas := Ramas + [1];
        ConElse := ConElse + [False];
        Pila := Pila + [High(Ramas)];
        Anota(2, High(Ramas));
      end
      else if MatchText(Nombre, CONDICIONAL_RAMA) then
      begin
        if Length(Pila) = 0 then
          Exit(-1);
        Inc(Ramas[Pila[High(Pila)]]);
        if SameText(Nombre, 'ELSE') then
          ConElse[Pila[High(Pila)]] := True;
        Anota(3, Pila[High(Pila)]);
      end
      else if MatchText(Nombre, CONDICIONAL_CIERRA) then
      begin
        if Length(Pila) = 0 then
          Exit(-1);
        Anota(4, Pila[High(Pila)]);
        SetLength(Pila, Length(Pila) - 1);
      end;
      EnEntrada := False;
      I := Ds[DI].Inicio + Ds[DI].Largo;
      Inc(DI);
      Continue;
    end;
    if Clases[I] in [cpCodigo, cpCadena] then
    begin
      if (Clases[I] = cpCodigo) and (ACuerpo[I] = ';') then
        Break;
      if (Clases[I] = cpCodigo) and (ACuerpo[I] = ',') then
      begin
        Anota(1, -1);
        EnEntrada := False;
      end
      else if not CharInSet(ACuerpo[I], [' ', #9, #10, #13]) then
      begin
        if not EnEntrada then
          Anota(0, -1);
        EnEntrada := True;
      end;
    end;
    Inc(I);
  end;
  if Length(Pila) > 0 then
    Exit(-1);
  // cada bloque elige una de sus ramas, o ninguna si no tiene ELSE
  var Opciones: TArray<Integer>;
  SetLength(Opciones, Length(Ramas));
  var Total := 1;
  for var B := 0 to High(Ramas) do
  begin
    Opciones[B] := Ramas[B] + (if ConElse[B] then 0 else 1);
    Total := Total * Opciones[B];
    if Total > MAX_COMBINACIONES_DE_RAMAS then
      Exit(-1);
  end;
  var Elegida, Actual: TArray<Integer>;
  SetLength(Elegida, Length(Ramas));
  SetLength(Actual, Length(Ramas));
  for var Combo := 0 to Total - 1 do
  begin
    var R := Combo;
    for var B := 0 to High(Ramas) do
    begin
      Elegida[B] := R mod Opciones[B];
      R := R div Opciones[B];
    end;
    var Abiertos: TArray<Integer> := [];
    var Estado := 0; // 0 nada todavia, 1 tras una entrada, 2 tras una coma
    for var Ev in Eventos do
      case Ev.Clase of
        2:
          begin
            Actual[Ev.Bloque] := 0;
            Abiertos := Abiertos + [Ev.Bloque];
          end;
        3:
          Inc(Actual[Ev.Bloque]);
        4:
          SetLength(Abiertos, Length(Abiertos) - 1);
      else
        begin
          var Activo := True;
          for var B in Abiertos do
            if Actual[B] <> Elegida[B] then
              Activo := False;
          if Activo then
            if Ev.Clase = 0 then
              Estado := 1
            else if Estado <> 1 then
              Exit(1) // una coma al principio o dos seguidas
            else
              Estado := 2;
        end;
      end;
    if Estado <> 1 then
      Exit(1); // una coma al final, o ninguna entrada en esta rama
  end;
  Result := 0;
end;

{ Las entradas de las OTRAS ramas de una clausula partida: de ADesde (tras el
  ';' de la primera) al condicional que la cierra. Cada rama acaba en su ';':
  se leen como una lista mas, sin las que solo son directivas. }
function EntradasDeOtrasRamas(const ATexto: string; ADesde, AAbiertos: Integer;
  out AFin: Integer): TArray<string>;
var
  Prof, Fin: Integer;
begin
  Prof := AAbiertos;
  Fin := Length(ATexto) + 1;
  for var D in DirectivasPascal(Copy(ATexto, ADesde, MaxInt)) do
  begin
    if MatchText(D.Nombre, CONDICIONAL_ABRE) then
      Inc(Prof)
    else if MatchText(D.Nombre, CONDICIONAL_CIERRA) then
      Dec(Prof);
    if Prof <= 0 then
    begin
      Fin := ADesde + D.Inicio - 1;
      Break;
    end;
  end;
  AFin := Fin;
  Result := [];
  for var E in SplitEntries(Copy(ATexto, ADesde, Fin - ADesde).Replace(';', ',')) do
    if BlankComments(E).Trim <> '' then
      Result := Result + [E];
end;

// APalabra: otra clausula que la de la unidad, del programa o del paquete -
// 'requires', la de un paquete: la leia una regex sobre el codigo con las
// directivas en blanco, y add-requires la reescribia sin ellas (18-oct-2026)
function FindUses(const Dpr: string; AFrom: Integer = 0; const APalabra: string = ''): TUsesClause;
var
  I, N, Start, K: Integer;
  Token: string;
begin
  Result := Default(TUsesClause);
  Result.Keyword := 'uses';
  I := 1;
  if AFrom > 0 then
    // Una SECCION de un .pas (adduses, 2026-09-23): se busca desde justo
    // despues de interface/implementation, y otro token antes de la clausula
    // (type, const, procedure, la seccion siguiente...) = no hay uses ahi.
    I := AFrom
  else
  begin
    // en la vista del codigo: un 'program viejo; uses X;' dentro de un
    // comentario de arriba era la cabecera, y add-unit escribia en el uses
    // COMENTADO diciendo que lo habia hecho (sonda del lexico, 2-oct-2026)
    // EL lector de la cabecera (Lsp.Pascal): desde detras de su ';'
    var Cab: TCabeceraFuente;
    if CabeceraDeFuente(CodigoPascal(Dpr), Cab) and (Cab.Palabra <> 'unit') then
    begin
      I := Cab.Fin;
      if Cab.Palabra = 'package' then
        Result.Keyword := 'contains';
    end;
  end;
  if APalabra <> '' then
    Result.Keyword := APalabra;
  K := Length(Result.Keyword);
  Start := 0;
  while I <= Length(Dpr) do
  begin
    N := CommentLen(Dpr, I);
    if N = 0 then
      N := QuoteLen(Dpr, I);
    if N > 0 then
    begin
      Inc(I, N);
      Continue;
    end;
    if Start = 0 then
    begin
      if ((I = 1) or not EsCaracterDeIdent(Dpr[I - 1])) and (I + K - 1 <= Length(Dpr)) and
         SameText(Copy(Dpr, I, K), Result.Keyword) and
         ((I + K > Length(Dpr)) or not EsCaracterDeIdent(Dpr[I + K])) then
      begin
        Start := I;
        Inc(I, K);
        Continue;
      end;
      if EsCaracterDeIdent(Dpr[I]) then
      begin
        // another token before the clause (const, type, begin...): no clause.
        // Except `requires ...;` in a package, which comes BEFORE contains
        // and is skipped whole.
        Token := '';
        while (I <= Length(Dpr)) and EsCaracterDeIdent(Dpr[I]) do
        begin
          Token := Token + Dpr[I];
          Inc(I);
        end;
        if SameText(Token, 'requires') then
        begin
          while (I <= Length(Dpr)) and (Dpr[I] <> ';') do
          begin
            N := CommentLen(Dpr, I);
            if N = 0 then
              N := QuoteLen(Dpr, I);
            if N > 0 then
              Inc(I, N)
            else
              Inc(I);
          end;
          Inc(I); // the ';' of requires
          Continue;
        end;
        if not SameText(Token, Result.Keyword) then
          Exit;
        Start := I - K;
      end
      else
        Inc(I);
      Continue;
    end;
    if Dpr[I] = ';' then
    begin
      Result.StartPos := Start;
      Result.EndPos := I;
      Result.Found := True;
      Result.Entries := SplitEntries(Copy(Dpr, Start + K, I - (Start + K)));
      Result.FinRamas := I;
      // Un ';' DENTRO de un condicional abierto cierra una rama, no la
      // clausula: las otras ramas van detras (el uses del nodo de escritorio,
      // Windows y Linux). Se leia solo la primera.
      var Abiertos := CondicionalesAbiertos(Copy(Dpr, Start, I - Start));
      if Abiertos > 0 then
      begin
        Result.EnRamas := True;
        Result.OtrasRamas := EntradasDeOtrasRamas(Dpr, I + 1, Abiertos, Result.FinRamas);
      end;
      Exit;
    end;
    Inc(I);
  end;
end;

// Leading comments/directives of an entry (kept when the entry is dropped so
// a conditional directive around it stays balanced) and the bare entry text.
procedure SplitEntryPrefix(const Entry: string; out APrefix, ACore: string);
var
  I, N: Integer;
begin
  I := 1;
  while I <= Length(Entry) do
  begin
    N := CommentLen(Entry, I);
    if N > 0 then
      Inc(I, N)
    else if Entry[I].IsWhiteSpace then
      Inc(I)
    else
      Break;
  end;
  APrefix := Copy(Entry, 1, I - 1).Trim;
  ACore := Copy(Entry, I, MaxInt).Trim;
end;

function EntryUnitName(const Entry: string): string;
var
  M: TMatch;
  Prefix, Core: string;
begin
  SplitEntryPrefix(Entry, Prefix, Core);
  M := TRegEx.Match(Core, '^(' + PATRON_IDENT_PUNTOS + ')');
  if M.Success then
    Result := M.Groups[1].Value
  else
    Result := Core;
end;

function EntryInclude(const Entry: string): string;
var
  M: TMatch;
begin
  M := TRegEx.Match(Entry, '^\s*' + PATRON_IDENT_PUNTOS + '\s+in\s*''([^'']+)''', [roIgnoreCase]);
  if not M.Success then
  begin
    var Prefix, Core: string;
    SplitEntryPrefix(Entry, Prefix, Core);
    M := TRegEx.Match(Core, '^' + PATRON_IDENT_PUNTOS + '\s+in\s*''([^'']+)''', [roIgnoreCase]);
  end;
  if M.Success then
    Result := M.Groups[1].Value
  else
    Result := '';
end;

function EntryFormName(const Entry: string): string;
var
  M: TMatch;
  Prefix, Core: string;
begin
  SplitEntryPrefix(Entry, Prefix, Core);
  M := TRegEx.Match(Core, '''\s*\{\s*(' + PATRON_IDENT + ')');
  if M.Success then
    Result := M.Groups[1].Value
  else
    Result := '';
end;

function BuildEntry(const AInfo: TUnitInfo; const AInclude: string): string;
begin
  Result := AInfo.UnitName + ' in ''' + AInclude + '''';
  if AInfo.IsDesigner and (AInfo.FormName <> '') then
  begin
    if AInfo.DesignClass <> '' then
      Result := Result + ' {' + AInfo.FormName + ': ' + AInfo.DesignClass + '}'
    else
      Result := Result + ' {' + AInfo.FormName + '}';
  end;
end;

// La entrada AEntrada reescrita con ANueva (renombrada; completada con su
// in): conserva lo que la precede (su comentario o su directiva) y lo que
// lleva DETRAS de lo suyo - el nombre, el in y el comentario del form, que
// ANueva trae -: una directiva o un comentario. Los dos escritores la
// rehacian con lo de delante solo, y renombrar "Unit1 in 'Unit1.pas'
// {$IFDEF DEBUG}," perdia el IFDEF: el .dpr no compilaba y la tool decia
// que si (revision de la 1.10.0, medido con delphi_move y con add-unit)
function EntradaReescrita(const AEntrada, ANueva: string): string;
var
  Prefix, Core: string;
  M: TMatch;
begin
  SplitEntryPrefix(AEntrada, Prefix, Core);
  Result := ANueva;
  // con EL identificador (Lsp.Pascal): con [A-Za-z_][\w.]* el nombre de una
  // unit con acento casaba hasta el acento, y lo de detras (el resto del
  // nombre y su in) se pegaba a la entrada nueva (censo del 4-oct-2026)
  M := TRegEx.Match(Core, '^\s*' + PATRON_IDENT_PUNTOS + '(\s+in\s*''[^'']*''(\s*\{\s*' + PATRON_IDENT +
    '\s*(:\s*' + PATRON_IDENT_PUNTOS + '\s*)?\})?)?',
    [roIgnoreCase]);
  if M.Success then
    Result := Result + Copy(Core, M.Length + 1, MaxInt);
  if Prefix <> '' then
    Result := Prefix + #10 + Result;
end;

{ Rewrites the clause with AEntries, keeping the text before/after intact.
  Entries go one per line with the indent the clause already used (the IDE's
  two spaces when it had none). Measured 2026-08-23: the indent was applied
  TWICE (join + a second replace) and every add/remove-unit re-indented the
  whole clause to four spaces - a 40-line cosmetic diff on a real project. }
// Una entrada envuelta ENTERA en su condicional, en lineas suyas: la primera
// abre (IFDEF X, IFNDEF X, IF ..., IFOPT ...), la ultima cierra (ENDIF /
// IFEND) y en medio esta la unit. Lo dice EL lector de directivas: con su
// propia regex no veia la forma parentesis-asterisco ni un // detras de la
// directiva, y quitar la entrada de detras dejaba 'UA, ;' sin DEBUG
// (revision de la 1.10.0, medido)
function EsEnvuelta(const AEntrada: string): Boolean;
var
  L: TArray<string>;

  // la linea es UNA directiva de esas y nada de codigo (un comentario si)
  function SoloDirectiva(const ALinea: string; const ANombres: array of string): Boolean;
  var
    Ds: TArray<TDirectivaPascal>;
  begin
    Ds := DirectivasPascal(ALinea);
    Result := (Length(Ds) = 1) and MatchText(Ds[0].Nombre, ANombres) and
      (CodigoPascal(ALinea).Trim = '');
  end;

begin
  L := [];
  for var S in SplitToLines(AEntrada) do
    if S.Trim <> '' then
      L := L + [S.Trim];
  Result := (Length(L) >= 3) and SoloDirectiva(L[0], CONDICIONAL_ABRE) and
    SoloDirectiva(L[High(L)], CONDICIONAL_CIERRA);
end;

// Que entrada NUEVA es cada una de la clausula ORIGINAL (-1: se quito). Los
// escritores la cambian de tres maneras: anaden al final, cambian una entrada
// EN SU SITIO (completarla; renombrarla, con otro nombre) o quitan por el
// nombre, y entonces la lista se acorta. Se casan por el nombre; sin quitar
// ninguna, la que no casa es la misma en su sitio con otro nombre. Iba solo
// por el nombre, y el rename acertaba porque su lista ES la de la clausula
// (un array dinamico se asigna por referencia), no por metodo (revision de
// la 1.10.0)
function EntradaNuevaDe(const AOriginal, ANuevas: TArray<string>): TArray<Integer>;
var
  I: Integer;
begin
  SetLength(Result, Length(AOriginal));
  I := 0;
  for var K := 0 to High(AOriginal) do
  begin
    Result[K] := -1;
    if (I <= High(ANuevas)) and
       (MismoIdentificador(EntryUnitName(AOriginal[K]), EntryUnitName(ANuevas[I])) or
        (Length(ANuevas) >= Length(AOriginal))) then
    begin
      Result[K] := I;
      Inc(I);
    end;
  end;
end;

{ Una clausula COMPACTA - alguna linea con varias units, sin comentarios ni
  directivas, solo identificadores - editada EN SU SITIO: las que se van
  salen con su coma (y la linea que se queda vacia, con ellas) y las nuevas
  entran detras de la ultima, en su linea mientras quepa (80 columnas, o la
  linea mas larga que ya tenia), si no en una nueva con su sangria. '' si
  no es compacta o el cambio no es "quitar unas y anadir al final": entonces
  escribe ReplaceUses, una por linea, como siempre. Rehacerla una por linea
  era un diff de cuarenta lineas por una unit (adduses y removeuses en
  UTrayMain, 9-oct-2026; 3.13 de la 1.18.0). }
function UsesCompacta(const Dpr: string; const U: TUsesClause;
  const AEntries: TArray<string>): string;
var
  Ini, P, I, K, Ancho: Integer;
  Cuerpo, NL, Indent, Nuevo, Antes: string;
  Pos_: TArray<Integer>;
  Quedan: TArray<Boolean>;
  M: TMatch;
begin
  Result := '';
  if (Length(U.Entries) = 0) or (Length(AEntries) = 0) then
    Exit;
  Ini := U.StartPos + Length(U.Keyword);
  Cuerpo := Copy(Dpr, Ini, U.EndPos - Ini);
  // ni un comentario ni una directiva, y solo nombres de unit
  if CodigoPascal(Cuerpo) <> Cuerpo then
    Exit;
  for var E in U.Entries + AEntries do
    if not EsIdentificador(E, True) then
      Exit;
  // compacta: alguna linea con dos o mas
  if not TRegEx.IsMatch(Cuerpo, ',[ \t]*[^\s]') then
    Exit;
  // un comentario DETRAS del ';', en su linea, es de la ULTIMA entrada
  // original (11.3): editada en su sitio, la compacta lo dejaba tras la nueva
  // ('SysUtils, Classes; // para Format') o con otra si quitaba la suya.
  // ReplaceUses ya sabe de quien es (revisor de version de la 1.18.0, medido)
  var PC := U.EndPos + 1;
  while (PC <= Length(Dpr)) and CharInSet(Dpr[PC], [' ', #9]) do
    Inc(PC);
  if (CommentLen(Dpr, PC) > 0) and not Copy(Dpr, PC, 2).Equals('{$') and
     not Copy(Dpr, PC, 3).Equals('(*$') then
    Exit;
  // las que se quedan, en su orden; detras, solo nuevas
  SetLength(Quedan, Length(U.Entries));
  K := 0;
  for I := 0 to High(U.Entries) do
  begin
    Quedan[I] := (K <= High(AEntries)) and (AEntries[K] = U.Entries[I]);
    if Quedan[I] then
      Inc(K);
  end;
  if K = 0 then
    Exit;
  for I := K to High(AEntries) do
    for var E in U.Entries do
      if MismoIdentificador(AEntries[I], E) then
        Exit; // una que estaba, fuera de su orden: el camino de siempre
  // donde empieza cada una; entre dos, solo la coma y blancos
  SetLength(Pos_, Length(U.Entries));
  P := 1;
  for I := 0 to High(U.Entries) do
  begin
    var Q := PosEx(U.Entries[I], Cuerpo, P);
    if (Q = 0) or not (Copy(Cuerpo, P, Q - P).Replace(',', '').Trim = '') then
      Exit;
    Pos_[I] := Q;
    P := Q + Length(U.Entries[I]);
  end;
  // fuera las que se van: su nombre y la coma y los blancos que la siguen
  // en SU linea (el salto se queda)
  Nuevo := Cuerpo;
  for I := High(U.Entries) downto 0 do
    if not Quedan[I] then
    begin
      var Fin := Pos_[I] + Length(U.Entries[I]);
      while (Fin <= Length(Nuevo)) and CharInSet(Nuevo[Fin], [' ', #9]) do
        Inc(Fin);
      if (Fin <= Length(Nuevo)) and (Nuevo[Fin] = ',') then
        Inc(Fin);
      while (Fin <= Length(Nuevo)) and CharInSet(Nuevo[Fin], [' ', #9]) do
        Inc(Fin);
      Delete(Nuevo, Pos_[I], Fin - Pos_[I]);
    end;
  // sin coma colgando al final, sin blancos al final de linea, sin lineas
  // que se quedaron vacias
  Nuevo := TRegEx.Replace(Nuevo, '[\s,]+$', '');
  Nuevo := TRegEx.Replace(Nuevo, '[ \t]+(\r?\n)', '$1');
  repeat
    Antes := Nuevo;
    Nuevo := TRegEx.Replace(Nuevo, '\r?\n[ \t]*(?=\r?\n)', '');
  until Nuevo = Antes;
  // las nuevas, detras de la ultima
  NL := SaltoDominante(Dpr);
  M := TRegEx.Match(Cuerpo, '\n([ \t]+)\S');
  if M.Success then
    Indent := M.Groups[1].Value
  else
    Indent := '  ';
  Ancho := 80;
  for var L in SplitToLines(Copy(Dpr, U.StartPos, U.EndPos - U.StartPos + 1)) do
    if Length(L) > Ancho then
      Ancho := Length(L);
  for I := K to High(AEntries) do
  begin
    // la columna en la que acaba la ultima linea (con lo que hay delante de
    // la palabra uses, si sigue en su linea)
    var UltSalto := Nuevo.LastIndexOf(#10);
    var Col: Integer;
    if UltSalto >= 0 then
      Col := Length(Nuevo) - UltSalto - 1
    else
    begin
      var IniLinea := U.StartPos;
      while (IniLinea > 1) and not CharInSet(Dpr[IniLinea - 1], [#10, #13]) do
        Dec(IniLinea);
      Col := U.StartPos - IniLinea + Length(U.Keyword) + Length(Nuevo);
    end;
    if Col + 2 + Length(AEntries[I]) + 1 <= Ancho then
      Nuevo := Nuevo + ', ' + AEntries[I]
    else
      Nuevo := Nuevo + ',' + NL + Indent + AEntries[I];
  end;
  Result := Copy(Dpr, 1, Ini - 1) + Nuevo + Copy(Dpr, U.EndPos, MaxInt);
end;

function ReplaceUses(const Dpr: string; const U: TUsesClause; const AEntries: TArray<string>): string;
var
  Body, NL, Indent, Clause, E: string;
  M: TMatch;
  Parts: TArray<string>;
  I: Integer;
  Mapa: TArray<Integer>;
  ClasesClausula: TArray<TClasePascal>;

  // la primera linea de una entrada cuando va sola (con un salto detras)
  function PrimeraLinea(const AEntrada: string): string;
  begin
    var T := ConSalto(AEntrada, #10); // tambien el CR suelto (decima revision)
    var P := T.IndexOf(#10);
    Result := IfThen(P >= 0, Copy(T, 1, P), '').Trim;
  end;

  // si el // con el que empieza la entrada NUEVA AI iba, en la clausula
  // ORIGINAL, detras de la coma de la que ahora es la AI-1. Por si hay uno
  // asi, no por el primero con ese texto: con dos '// TODO' iguales detras
  // de dos comas, el segundo se daba a la duena del primero y bajaba a una
  // linea suya (revision de la 1.10.0, medido con adduses)
  function EsDeLaAnterior(AI: Integer; const AComentario: string): Boolean;
  begin
    for var K := 1 to High(U.Entries) do
      if (PrimeraLinea(U.Entries[K]) = AComentario) and (Mapa[K - 1] = AI - 1) then
        Exit(True);
    Result := False;
  end;

  // AEntrada sin la primera linea que es ALinea (recortada)
  function SinLinea(const AEntrada, ALinea: string): string;
  begin
    var Quedan: TArray<string> := [];
    var Quitada := False;
    for var L in ConSalto(AEntrada, #10).Split([#10]) do
      if not Quitada and (L.Trim = ALinea) then
        Quitada := True
      else
        Quedan := Quedan + [L];
    Result := string.Join(#10, Quedan);
  end;

  // el hueco que habia en la clausula ORIGINAL entre un separador de ASeps y
  // el comentario //; False si ese comentario no iba detras de uno. Un
  // separador DE CODIGO y un // DE VERDAD, segun el lexico: el mismo texto
  // dentro de una llave o de una cadena no cuenta
  function HuecoTrasSeparador(const ASeps, AComentario: string; out AHueco: string): Boolean;
  begin
    AHueco := '';
    for var MM in TRegEx.Matches(Clause, '[' + ASeps + ']([ \t]*)' + TRegEx.Escape(AComentario)) do
      if (ClasesClausula[MM.Index] = cpCodigo) and
         (ClasesClausula[MM.Index + MM.Length - Length(AComentario)] = cpLinea) then
      begin
        AHueco := MM.Groups[1].Value;
        Exit(True);
      end;
    Result := False;
  end;

  // si el comentario // AComentario iba, en la clausula ORIGINAL, detras de la
  // coma de codigo numero ANumero (la que separa la entrada ANumero-1 de la
  // ANumero), en su misma linea, y con que hueco. HuecoTrasSeparador mira
  // cualquier coma: un '// TODO' de linea propia se iba con la quitada si otro
  // '// TODO' iba detras de otra coma (revisor de version de la 1.18.0, medido)
  function TrasLaComa(ANumero: Integer; const AComentario: string; out AHueco: string): Boolean;
  var
    N: Integer;
  begin
    AHueco := '';
    N := 0;
    for var J := 1 to Length(Clause) do
      if (ClasesClausula[J] = cpCodigo) and (Clause[J] = ',') then
      begin
        Inc(N);
        if N = ANumero then
        begin
          var MC := TRegEx.Match(Copy(Clause, J + 1, MaxInt), '^([ \t]*)' + TRegEx.Escape(AComentario));
          Result := MC.Success and
            (ClasesClausula[J + MC.Length - Length(AComentario) + 1] = cpLinea);
          if Result then
            AHueco := MC.Groups[1].Value;
          Exit;
        end;
      end;
    Result := False;
  end;

begin
  // EL escritor pregunta el mismo, como AtomicWrite: una clausula partida en
  // ramas no se reescribe - la unit caeria en la rama que no toca, o la
  // clausula perderia su forma. Los llamadores lo dicen antes, con el fichero.
  if U.EnRamas then
    raise Exception.Create(MsgFmt(SR_USES_EN_RAMAS_FMT, [U.Keyword, MsgText(SF_USES_EL_FICHERO)]));
  // sin entradas no hay clausula: la palabra sola no compila, y quitar la
  // ULTIMA unit de un .dpr/.dpk la dejaba asi diciendo OK (decima revision).
  // Se va entera con los saltos que la seguian; removeuses lo hacia a mano.
  if Length(AEntries) = 0 then
  begin
    var Fin := U.EndPos + 1;
    while (Fin <= Length(Dpr)) and CharInSet(Dpr[Fin], [#10, #13]) do
      Inc(Fin);
    Exit(Copy(Dpr, 1, U.StartPos - 1) + Copy(Dpr, Fin, MaxInt));
  end;
  // una clausula compacta se edita en su sitio (UsesCompacta)
  Result := UsesCompacta(Dpr, U, AEntries);
  if Result <> '' then
    Exit;
  NL := SaltoDominante(Dpr);
  // the indent of the first entry line of the existing clause
  Clause := Copy(Dpr, U.StartPos, U.EndPos - U.StartPos + 1);
  ClasesClausula := ClasesPascal(Clause);
  M := TRegEx.Match(Clause, '\n([ \t]+)\S');
  if M.Success then
    Indent := M.Groups[1].Value
  else
    Indent := '  ';
  SetLength(Parts, Length(AEntries));
  Mapa := EntradaNuevaDe(U.Entries, AEntries);
  // un // que va detras de la coma es de la entrada de ANTES (esta en su
  // misma linea), aunque el troceo por comas lo deje al principio de la
  // siguiente: se le devuelve a su dueno, y el separador (la coma o el ;)
  // va DELANTE de el. Si no, quitar la ultima entrada dejaba el ; dentro
  // del comentario y la clausula sin cerrar, y cada reescritura bajaba el
  // comentario a una linea suya (medido 27-sep con removeuses). Y a SU
  // dueno, no a la de antes en la lista nueva: quitada la duena, se pegaba a
  // la anterior ('UA, // de UB', medido el 2-oct-2026 con remove-unit). Y si
  // su duena se QUITA, se va con ella: el comentario en la linea de una
  // entrada es suyo; el que va en una linea propia se queda (David, 10-oct-2026,
  // 11.3: regla de la casa, no hay juez; quedaba huerfano dentro del uses).
  var Entradas := Copy(AEntries);
  var Colas: TArray<string>;
  SetLength(Colas, Length(Entradas));
  for I := 1 to High(Entradas) do
  begin
    var Texto := ConSalto(Entradas[I], #10);
    var P := Texto.IndexOf(#10);
    var Primera := PrimeraLinea(Entradas[I]);
    // solo si en el original iba detras de SU coma: uno que estaba en una
    // linea suya no sube; y con el hueco que tenia (las entradas llegan
    // recortadas: el hueco sale del texto original de la clausula)
    var HC: string;
    if Primera.StartsWith('//') and HuecoTrasSeparador(',', Primera, HC) and
       EsDeLaAnterior(I, Primera) then
    begin
      Colas[I - 1] := IfThen(HC <> '', HC, ' ') + Primera;
      Entradas[I] := Copy(Texto, P + 2, MaxInt);
    end;
  end;
  // el // que iba detras de la coma de una entrada QUITADA se va con ella
  // (11.3): viajaba al principio de la siguiente, detras de lo que la
  // quitada le deja pegado (EntriesWithout: su prefijo), y se quita ahi
  for var K := 1 to High(U.Entries) do
    if (Mapa[K] >= 0) and (Mapa[K - 1] = -1) then
    begin
      var Suyo := PrimeraLinea(U.Entries[K]);
      var HS: string;
      // detras de SU coma, la de la quitada (la K), no de cualquiera
      if Suyo.StartsWith('//') and TrasLaComa(K, Suyo, HS) then
        Entradas[Mapa[K]] := SinLinea(Entradas[Mapa[K]], Suyo);
    end;
  // el comentario que va DETRAS del ; final, en su misma linea, es de la
  // ULTIMA entrada original, y queda fuera de la clausula: con una unit
  // anadida detras se iba a la nueva ('Lsp.NetDrives; // PrefijoSinBarra'
  // salio 'Lsp.Texts; // PrefijoSinBarra', medido el 2-oct-2026 con adduses,
  // y lo mismo add-unit en un .dpr), y quitada su entrada se pegaba a la que
  // quedaba ('// de SysUtils // de Classes'). Se queda con su entrada; si su
  // entrada se fue, se va con ella, como el de una quitada de en medio (11.3;
  // hasta el 10-oct-2026 se quedaba en una linea suya)
  var Resto := U.EndPos + 1;   // desde donde sigue el texto de detras
  var PosCom := U.EndPos + 1;
  while (PosCom <= Length(Dpr)) and CharInSet(Dpr[PosCom], [' ', #9]) do
    Inc(PosCom);
  var LargoCom := CommentLen(Dpr, PosCom);
  // (una directiva no es un comentario de nadie: {$ o (*$ no viaja)
  if (LargoCom > 0) and (Length(U.Entries) > 0) and
     (Copy(Dpr, PosCom, LargoCom).IndexOfAny([#10, #13]) < 0) and
     not Copy(Dpr, PosCom, 2).Equals('{$') and not Copy(Dpr, PosCom, 3).Equals('(*$') then
  begin
    // la que corresponde a la ultima original, no por su texto: el de una
    // entrada lleva delante el comentario de la anterior, que quitar esa
    // anterior cambia (medido)
    var Duena := Mapa[High(U.Entries)];
    if Duena < High(Entradas) then
    begin
      var Coment := Copy(Dpr, PosCom, LargoCom);
      if Duena >= 0 then
        Colas[Duena] := Colas[Duena] + IfThen(PosCom > U.EndPos + 1,
          Copy(Dpr, U.EndPos + 1, PosCom - U.EndPos - 1), ' ') + Coment;
      Resto := PosCom + LargoCom;
    end;
  end;
  // la COLA de entradas envueltas cada una en su condicional ({$IFDEF X} /
  // la unit / {$ENDIF}) al final de la clausula: el separador de la de antes
  // tiene que ir DENTRO de cada condicional (A {$IFDEF X}, B {$ENDIF};), o
  // con X apagado queda 'A, ;' y no compila. Quitar la ultima C de 'A,
  // {$IFDEF DEBUG} DebugU, {$ENDIF} C;' lo dejaba asi (medido en la revision
  // de la 1.10.0; venia de antes)
  var InicioCola := Length(Entradas);
  while (InicioCola - 1 >= 1) and EsEnvuelta(Entradas[InicioCola - 1]) do
    Dec(InicioCola);
  for I := 0 to High(Entradas) do
  begin
    // a multi-line entry (directives around it) keeps its lines indented too:
    // cada linea se reindenta desde cero, que la que venia con su sangria
    // propia (la vecina de una entrada quitada) salia con las dos (medido
    // en vivo con removeuses, 2026-09-23)
    var Lineas := SplitToLines(Entradas[I]);
    for var J := 0 to High(Lineas) do
      Lineas[J] := Lineas[J].Trim;
    var Sep := IfThen(I < High(Entradas), ',', ';');
    if InicioCola < Length(Entradas) then
    begin
      if (I = InicioCola - 1) or ((I >= InicioCola) and (I < High(Entradas))) then
        Sep := '';
      if I >= InicioCola then
        Lineas[1] := ', ' + Lineas[1]; // la coma, dentro del condicional
    end;
    // el separador, detras de la ultima linea con codigo y delante de su //.
    // Lo que es un // lo dice el lexico, con el estado de las lineas de antes:
    // el de '{ver https://x}' no lo es, y la coma caia DENTRO de la llave
    // (adduses acababa en SYS-006, medido el 2-oct-2026)
    var Coms := ComentariosDeLinea(Lineas);
    var K := High(Lineas);
    while (K > 0) and (Coms[K] = 1) do
      Dec(K);
    var C := Coms[K];
    if C > 0 then
    begin
      var Codigo := Copy(Lineas[K], 1, C - 1);
      var Hueco := Copy(Codigo, Length(Codigo.TrimRight) + 1, MaxInt);
      // el que tenia en el original, detras de su separador. (Era un IfThen
      // con MH.Groups[1] de argumento: IfThen es una funcion, sus argumentos
      // se evaluan todos, y sin casar el grupo lanzaba 'Index out of bounds
      // (1)': el SYS-006 de la sonda)
      if (Hueco = '') and
         (not HuecoTrasSeparador(',;', Copy(Lineas[K], C, MaxInt), Hueco) or (Hueco = '')) then
        Hueco := ' ';
      Lineas[K] := Codigo.TrimRight + Sep + Hueco + Copy(Lineas[K], C, MaxInt);
    end
    else
      Lineas[K] := Lineas[K] + Sep;
    Lineas[High(Lineas)] := Lineas[High(Lineas)] + Colas[I];
    E := string.Join(NL + Indent, Lineas);
    Parts[I] := Indent + E;
  end;
  Body := IfThen(U.Keyword <> '', U.Keyword, 'uses') + NL + string.Join(NL, Parts);
  Body := TRegEx.Replace(Body, '[ \t]+(\r?\n)', '$1'); // no trailing blanks
  // EL escritor pregunta si lo que deja sigue siendo una lista en cada rama de
  // sus condicionales (ListaEnCadaRama), y solo si la que habia lo era: una
  // coma fuera de su condicional no compila con unos simbolos (revisor de
  // version de la 1.18.0, medido con dcc: E2029). Se niega sin escribir
  var Palabra := IfThen(U.Keyword <> '', U.Keyword, 'uses');
  if (ListaEnCadaRama(Copy(Clause, Length(Palabra) + 1, MaxInt)) = 0) and
     (ListaEnCadaRama(Copy(Body, Length(Palabra) + 1, MaxInt)) = 1) then
    raise Exception.Create(MsgFmt(SR_USES_RAMA_SIN_LISTA_FMT, [Palabra]));
  Result := Copy(Dpr, 1, U.StartPos - 1) + Body + Copy(Dpr, Resto, MaxInt);
end;

function CreateFormLine(const AInfo: TUnitInfo): string;
begin
  Result := 'Application.CreateForm(' + AInfo.ClassName + ', ' + AInfo.FormName + ');';
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
  I, Last, RunAt: Integer;
  NL, Indent: string;
begin
  Result := False;
  if TRegEx.IsMatch(CodigoPascal(Dpr), PATRON_NO_IDENT_ANTES + 'CreateForm\s*\(\s*' + PatronIdentEntero(AInfo.ClassName) + '\s*,', [roIgnoreCase]) then
    Exit(True); // already there
  NL := SaltoDominante(Dpr);
  Lines := SplitToLines(Dpr); // el troceador del motor: un CR suelto es salto
  Vista := SplitToLines(CodigoPascal(Dpr));
  Last := -1;
  RunAt := -1;
  for I := 0 to High(Lines) do
  begin
    if TRegEx.IsMatch(Vista[I], '^\s*Application\.CreateForm\s*\(', [roIgnoreCase]) then
      Last := I;
    if (RunAt = -1) and TRegEx.IsMatch(Vista[I], '^\s*Application\.Run\b', [roIgnoreCase]) then
      RunAt := I;
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

{ Drops every Application.CreateForm line naming AClass or AVar - del
  CODIGO: uno comentado se queda, y de una linea que lleva algo mas (el
  cierre de un comentario de encima) se va la sentencia sola: la llave que
  cerraba el comentario detras de un CreateForm se iba con el, y el
  comentario quedaba abierto hasta el final (revision de la 1.10.0, medido
  con remove-unit). }
function RemoveCreateForm(var Dpr: string; const AClassName, AFormName: string): Integer;
var
  Lines, Vista: TArray<string>;
  M: TMatch;
  I: Integer;
  NL: string;
  Pat: string;
begin
  Result := 0;
  NL := SaltoDominante(Dpr);
  Lines := SplitToLines(Dpr);
  Vista := SplitToLines(CodigoPascal(Dpr));
  if AClassName <> '' then
    Pat := '^\s*(Application\.CreateForm\s*\(\s*' + TRegEx.Escape(AClassName) + '\s*,[^)]*\)\s*;?)'
  else if AFormName <> '' then
    Pat := '^\s*(Application\.CreateForm\s*\(\s*' + PATRON_IDENT + '\s*,\s*' + TRegEx.Escape(AFormName) + '\s*\)\s*;?)'
  else
    Exit;
  // De abajo arriba: cambiar una linea no mueve las de encima, que son las
  // que quedan por mirar. Cada una con el compositor de todos
  // (CambiaLineasEnSuTexto): las demas, con SU salto. Unidas todas al
  // dominante, un .dpr mixto salia entero a ese salto (1.18.2)
  for I := High(Lines) downto 0 do
  begin
    M := TRegEx.Match(Vista[I], Pat, [roIgnoreCase]);
    if not M.Success then
      Continue;
    Inc(Result);
    // la sentencia sola (el grupo): lo de delante en la vista son blancos,
    // y entre ellos puede ir el cierre del comentario de encima (medido:
    // con el match entero se iba la llave)
    var G := M.Groups[1];
    var Resto := Copy(Lines[I], 1, G.Index - 1) + Copy(Lines[I], G.Index + G.Length, MaxInt);
    if Resto.Trim <> '' then
      Dpr := CambiaLineasEnSuTexto(Dpr, I, 1, [Resto.TrimRight], NL)
    else
      Dpr := CambiaLineasEnSuTexto(Dpr, I, 1, nil, NL);
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
      '            ' + XmlElemento('Form', AInfo.FormName) + CRLF;
    if AInfo.FormType <> '' then
      Result := Result + '            ' + XmlElemento('FormType', AInfo.FormType) + CRLF;
    if AInfo.DesignClass <> '' then
      Result := Result + '            ' + XmlElemento('DesignClass', AInfo.DesignClass) + CRLF;
    Result := Result + '        </DCCReference>' + CRLF;
  end
  else
    Result := '        <DCCReference ' + XmlAtributo('Include', AInclude) + '/>' + CRLF;
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
  Want := AInclude.Replace('/', '\').ToLower;
  for var T in TramosDeEtiqueta(Xml, 'DCCReference', True) do
    if AtributoDeTramo(Xml, T, 'DCCReference', 'Include').Replace('/', '\').ToLower = Want then
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

{ Estrena la clausula ACuerpo ('uses ...;') en APos de AText, donde empieza el
  salto que sigue a la palabra de seccion o a la cabecera: con la MISMA
  separacion que habia alli, delante y detras. Asi removeuses, que quita la
  clausula con los saltos que la siguen (ReplaceUses), es su inversa: con dos
  saltos fijos delante, una unit compacta ('interface' y el codigo justo
  debajo) ganaba una linea en blanco tras adduses + removeuses (test completo
  de Opus de la 1.22.0); con una linea en blanco, la forma del IDE, salen los
  mismos bytes que antes. Sin salto en APos, dos delante, como antes. EL
  escritor de una clausula nueva de un .pas y de un .dpr (eran dos). }
procedure EstrenaClausula(var AText: string; APos: Integer; const ACuerpo: string);
var
  Fin: Integer;
begin
  Fin := APos;
  while (Fin <= Length(AText)) and CharInSet(AText[Fin], [#10, #13]) do
    Inc(Fin);
  if Fin = APos then
    AText := Copy(AText, 1, APos - 1) + SaltoDominante(AText) + SaltoDominante(AText) +
      ACuerpo + Copy(AText, APos, MaxInt)
  else
  begin
    var Sep := Copy(AText, APos, Fin - APos);
    AText := Copy(AText, 1, APos - 1) + Sep + ACuerpo + Sep + Copy(AText, Fin, MaxInt);
  end;
end;

{ Estrena el uses de un programa o una biblioteca justo detras de su
  cabecera (EL lector: CabeceraDeFuente) con AEntradas ya escritas, sin el
  ';'. False si AText no es un program/library. La clausula que nace la
  escriben add-unit (al programa le quitaron su ultima unit: se fue entera)
  y adduses en un .dpr: un solo escritor de ese uses. }
function EstrenaUsesTrasCabecera(var AText: string; const AEntradas: string): Boolean;
var
  Cab: TCabeceraFuente;
begin
  Result := CabeceraDeFuente(CodigoPascal(AText), Cab) and
    MatchText(Cab.Palabra, ['program', 'library']);
  if Result then
  begin
    var NL := SaltoDominante(AText);
    EstrenaClausula(AText, Cab.Fin, 'uses' + NL + '  ' + AEntradas + ';');
  end;
end;

{ ---- public operations ---- }

function AddProjectUnitNucleo(const AProject, APasPath: string;
  ARaizDelCreador: TRaizDeDiseno): string;
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
  // hace antes de coger el cerrojo
  JuzgaRaizDeDiseno(Info, RegistroDelIde(Info.PasPath, Dproj), 0, ARaizDelCreador);
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
  if U.EnRamas then
    Exit(MsgFmt(SR_USES_EN_RAMAS_FMT, [U.Keyword, TPath.GetFileName(Dpr)]));
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
  EsPaquete := SameText(TPath.GetExtension(Dpr), '.dpk');
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
  // de escritura por delante, el .dpr deja de ser una carrera.
  EnterFileEdit;
  try
    Result := ProyectoTodoONada(AProject,
      function: string
      begin
        Result := AddProjectUnitNucleo(AProject, APasPath, ARaizDelCreador);
      end);
  finally
    LeaveFileEdit;
  end;
end;

{ The entry and the .dproj include for a unit, by unit name or by file stem
  (the .pas may already be gone when delete calls us). }
function LocateEntry(const U: TUsesClause; const AUnitName: string; out AEntry: string): Boolean;
var
  E: string;
begin
  for E in U.Entries do
    if MismoIdentificador(EntryUnitName(E), AUnitName) then
    begin
      AEntry := E;
      Exit(True);
    end;
  Result := False;
end;

{ Las entradas de una clausula SIN la unit dicha. El comentario o directiva
  que precede a la entrada quitada se queda, pegado a la siguiente (o a la
  anterior si era la ultima), para no desbalancear un IFDEF. Lo hacia
  remove-unit (.dpr/.dpk) en su sitio; ahora tambien removeuses (.pas): un
  solo sitio (2026-09-23). }
function EntriesWithout(const AEntries: TArray<string>; const AUnitName: string): TArray<string>;
var
  E, Carry, Prefix, Core, Detras: string;

  // lo que deja una entrada quitada, al FINAL de la anterior de la lista nueva
  procedure PegaALaAnterior(const ALoQueDeja: string);
  begin
    // un // en la primera linea del prefijo iba detras de la coma de la
    // anterior: vuelve a SU linea (ReplaceUses pone el ; delante de el)
    var C := ConSalto(ALoQueDeja, #10); // tambien el CR suelto (decima revision)
    var P := C.IndexOf(#10);
    var Primera := IfThen(P >= 0, Copy(C, 1, P), C);
    if Primera.TrimLeft.StartsWith('//') then
    begin
      Result[High(Result)] := Result[High(Result)] + Primera.TrimRight;
      C := IfThen(P >= 0, Copy(C, P + 2, MaxInt), '');
    end;
    if C.Trim <> '' then
      Result[High(Result)] := Result[High(Result)] + #10 + C;
  end;

begin
  Result := [];
  Carry := '';
  for E in AEntries do
    if not MismoIdentificador(EntryUnitName(E), AUnitName) then
    begin
      if Carry <> '' then
        Result := Result + [Carry + #10 + E]
      else
        Result := Result + [E];
      Carry := '';
    end
    else
    begin
      SplitEntryPrefix(E, Prefix, Core);
      // ...y las directivas que la entrada lleva DETRAS: 'DebugU{$ENDIF}'
      // perdia su ENDIF y el IFDEF de la de antes quedaba abierto (medido en
      // la revision de la 1.10.0; venia de antes). Por el lector UNICO de
      // directivas, cada una en su linea: aqui se escribio un gemelo suyo
      // (DirectivasDe) y lo encontro el censo del lexico, el mismo dia
      Detras := '';
      for var D in DirectivasPascal(Core) do
        Detras := IfThen(Detras <> '', Detras + #10, '') + Copy(Core, D.Inicio, D.Largo);
      // La coma que se va con la entrada es la de su MISMA region: sin una
      // directiva condicional entre ella y el nombre. Lo de siempre es la de
      // DETRAS, y lo que la entrada deja va al principio de la siguiente. Si
      // un condicional abre DETRAS del nombre ('B {$IFDEF X}, C{$ENDIF}'), la
      // de detras es de otra region: se va la de DELANTE y lo que deja va al
      // final de la anterior ('A {$IFDEF X}, C{$ENDIF}'); antes quedaba 'A,
      // {$IFDEF X} C{$ENDIF}', E2029 sin X (revisor de version de la 1.18.0,
      // medido con dcc). Si ninguna de las dos, lo niega ReplaceUses (USES-023)
      if (Length(Result) > 0) and LlevaCondicional(Detras) and not LlevaCondicional(Prefix) then
        PegaALaAnterior(IfThen(Prefix <> '', Prefix + #10, '') + Detras)
      else
        Carry := Prefix + IfThen((Prefix <> '') and (Detras <> ''), #10, '') + Detras;
    end;
  // la ULTIMA se fue: lo que deja, al final de la anterior
  if (Carry <> '') and (Length(Result) > 0) then
    PegaALaAnterior(Carry);
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
  if TPath.GetExtension(APasPath).ToLower <> '.pas' then
    Exit(MsgFmt(SR_UNIT_NOT_PAS_FMT, [TPath.GetFileName(APasPath)]));
  UnitName := TPath.GetFileNameWithoutExtension(APasPath);
  ClassName := '';
  FormName := '';
  // una ruta de FUERA de lo legible no se abre: la entrada se quita por su
  // nombre, como una que no existe (remove-unit de una <DCCReference> que
  // BUILD-050 pide quitar, 21-oct-2026)
  var Fuera := ReadPathDenied(APasPath) <> '';
  if (not Fuera) and (InspectUnit(APasPath, Info) = '') then
  begin
    UnitName := Info.UnitName;
    ClassName := Info.ClassName;
    FormName := Info.FormName;
  end;

  Text := PatchLoadText(Dpr, Enc);
  U := FindUses(Text);
  if not U.Found then
    Exit(MsgFmt(SR_UNIT_NO_USES_FMT, [TPath.GetFileName(Dpr)]));
  if U.EnRamas then
    Exit(MsgFmt(SR_USES_EN_RAMAS_FMT, [U.Keyword, TPath.GetFileName(Dpr)]));
  InDpr := LocateEntry(U, UnitName, Entry);
  Include := IncludeFor(Dpr, TPath.GetFullPath(APasPath));
  if InDpr then
  begin
    if EntryInclude(Entry) <> '' then
      Include := EntryInclude(Entry);
    if FormName = '' then
      FormName := EntryFormName(Entry);
    Entries := EntriesWithout(U.Entries, UnitName);
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
  var Dado := TPath.GetFileName(APasPath);
  var Listado := '';
  if AFileGoesToo then
    Plantilla := MsgText(SN_UNIT_REMOVED_GONE_FMT)
  else if Fuera then
    // de fuera no se dice ni si existe: nada se abre alli
    Plantilla := MsgText(SN_UNIT_REMOVED_FUERA_FMT)
  else if not TFile.Exists(APasPath) then
  begin
    // ...y si el proyecto la listaba por OTRA ruta que SI existe, es esa la
    // que sigue en disco y se nombra, con la dada entera al lado: CFG-112
    // negaba un fichero que estaba (M5 de los revisores de cierre). Include
    // es lo que listaba la entrada (o la ruta dada, si no la listaba nadie)
    Listado := RutaDeInclude(Dpr, Include);
    if TFile.Exists(Listado) then
    begin
      Plantilla := MsgText(SN_UNIT_REMOVED_OTRA_RUTA_FMT);
      Dado := TPath.GetFullPath(APasPath);
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
  const AFicheros, ANoEscritos: TArray<string>): string;
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
  // su raiz: la registro el IDE con la ruta VIEJA
  JuzgaRaizDeDiseno(Info, RegistroDelIde(AOldPasPath, Dproj), 0);
  OldName := TPath.GetFileNameWithoutExtension(AOldPasPath);
  NewInclude := IncludeFor(Dpr, Info.PasPath);

  Text := PatchLoadText(Dpr, Enc);
  U := FindUses(Text);
  if not U.Found then
    Exit(MsgFmt(SR_UNIT_NO_USES_FMT, [TPath.GetFileName(Dpr)]));
  if U.EnRamas then
    Exit(MsgFmt(SR_USES_EN_RAMAS_FMT, [U.Keyword, TPath.GetFileName(Dpr)]));
  Found := LocateEntry(U, OldName, Entry);
  if not Found then
    Exit(MsgFmt(SN_UNIT_ABSENT_FMT, [OldName, TPath.GetFileName(Dpr)]));
  OldInclude := EntryInclude(Entry);
  if OldInclude = '' then
    OldInclude := IncludeFor(Dpr, TPath.GetFullPath(AOldPasPath));
  Entries := U.Entries;
  for I := 0 to High(Entries) do
    if MismoIdentificador(EntryUnitName(Entries[I]), OldName) then
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
  // Las OTRAS units del proyecto y el propio .dpr: sus uses y toda referencia
  // CUALIFICADA (UnitVieja.Identificador) seguian nombrando la unit vieja y
  // el build caia con E2003 (Hermes, 2026-09-22, test 19). Se reescribe el
  // nombre como identificador entero, fuera de cadenas, en cada fichero que
  // el proyecto lista, y la respuesta cuenta cuantas y donde.
  var NRefs := 0;
  var NFich := 0;
  // Mismo nombre (move de carpeta sin renombrar): no hay nada que reescribir
  // y la cuenta decia "1 en 1 fichero" por sustituir X por X (medido en
  // vivo, 2026-09-23). La lista, y lo que no se escribe, las da
  // FicherosDelRename: la misma que fotografio el todo-o-nada
  if not MismoIdentificador(OldName, Info.UnitName) then
    for var Fich in AFicheros do
    begin
      var N := RenombrarIdentificadorUnit(Fich, OldName, Info.UnitName);
      if N > 0 then
      begin
        Inc(NRefs, N);
        Inc(NFich);
      end;
    end;
  Result := MsgFmt(SN_UNIT_RENAMED_FMT, [OldName, OldInclude, Info.UnitName, NewInclude,
    TPath.GetFileName(Dpr), U.Keyword, NRefs, NFich]);
  if Length(ANoEscritos) > 0 then
    Result := Result + #10 + MsgFmt(SN_UNIT_RENAME_NOT_WRITTEN_FMT,
      [Length(ANoEscritos), string.Join(', ', ANoEscritos)]);
  if NotaDeRaiz(Info) <> '' then
    Result := Result + #10 + NotaDeRaiz(Info);
end;

function FicherosDelRename(const AProject, ANewPasPath: string;
  out ANoEscritos: TArray<string>): TArray<string>;
var
  Dpr, Dproj: string;
  Todos: TArray<string>;
begin
  Result := [];
  ANoEscritos := [];
  if ResolveProjectPair(AProject, Dpr, Dproj) <> '' then
    Exit; // el rename dira lo que no cuadra
  Todos := [Dpr];
  for var PU in ProjectUnits(AProject, False) do
    if PU.Include <> '' then
      Todos := Todos + [RutaDeInclude(Dpr, PU.Include)];
  // la unit en su sitio nuevo: el .dpr todavia la lista por el viejo (que ya
  // no existe y no entra)
  Todos := Todos + [TPath.GetFullPath(ANewPasPath)];
  for var Fich in Todos do
    // lo que el .dpr nombra y nadie resuelve (un UNC ajeno): ni se mira si
    // existe, que era SMB hacia ese host (novena revision)
    if RutaSinTocarElDisco(Fich) then
      ANoEscritos := ANoEscritos + [TPath.GetFileName(Fich)]
    else if TFile.Exists(Fich) and (IndexText(Fich, Result) < 0) then
      // El .dpr puede listar ficheros de FUERA (../Common, una referencia):
      // se reescribe solo lo que esta sesion puede escribir, y lo demas se
      // dice. El escritor tambien lo comprueba (EscrituraDenegada): esto es
      // para contestarlo en vez de lanzar a mitad (auditoria 25-sep-2026)
      if EscrituraDenegada(Fich) <> '' then
        ANoEscritos := ANoEscritos + [TPath.GetFileName(Fich)]
      else
        Result := Result + [Fich];
end;

function RenameProjectUnit(const AProject, AOldPasPath, ANewPasPath: string): string;
var
  Ficheros, NoEscritos: TArray<string>;
begin
  EnterFileEdit;
  try
    // TODO O NADA, como registrar y quitar (ProyectoTodoONada): con el .dproj
    // en +R el .dpr quedaba re-apuntado y el DCCReference no, y la respuesta
    // decia "nothing was written" (medido en vivo, 28-sep-2026). En la foto,
    // ademas del par, lo que un RENAME reescribe (las units del proyecto y
    // la propia en su sitio nuevo); un move sin renombrar no las toca
    Ficheros := [];
    NoEscritos := [];
    if not MismoIdentificador(TPath.GetFileNameWithoutExtension(AOldPasPath),
                    TPath.GetFileNameWithoutExtension(ANewPasPath)) then
      Ficheros := FicherosDelRename(AProject, ANewPasPath, NoEscritos);
    Result := ProyectoTodoONada(AProject, Ficheros,
      function: string
      begin
        Result := RenameProjectUnitNucleo(AProject, AOldPasPath, ANewPasPath,
          Ficheros, NoEscritos);
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
  if not SameText(TPath.GetExtension(Dpr), '.dpk') then
    Exit(MsgFmt(SR_REQUIRES_NOT_PACKAGE_FMT, [TPath.GetFileName(Dpr)]));
  Nombres := TStringList.Create;
  Nuevos := TStringList.Create;
  try
    for N in ANames.Split([';', ',', ' ']) do
      if N.Trim <> '' then
      begin
        if not EsIdentificador(N.Trim, True) then
          Exit(MsgFmt(SR_REQUIRES_BAD_NAME_FMT, [N.Trim]));
        Nombres.Add(N.Trim);
      end;
    if Nombres.Count = 0 then
      Exit(MsgText(SR_REQUIRES_NEED_NAMES));
    EnterFileEdit;
    try
      Text := PatchLoadText(Dpr, Enc);
      NL := SaltoDominante(Text);
      // EL lector y EL escritor de las clausulas (FindUses / ReplaceUses, los
      // de contains): se reescribia entera, un nombre por linea, y se perdian
      // sus comentarios y sus {$IFDEF} - en 'rtl, dbrtl{$IFDEF MSWINDOWS},
      // vcl{$ENDIF}' vcl pasaba a ser de todas las plataformas (medido el
      // 18-oct-2026). Partida en ramas no se toca, como contains
      U := FindUses(Text, 0, 'requires');
      if U.EnRamas then
        Exit(MsgFmt(SR_USES_EN_RAMAS_FMT, [U.Keyword, TPath.GetFileName(Dpr)]));
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
  Cab: TCabeceraFuente;
  U: TUsesClause;
begin
  ANombres := [];
  AIni := 0;
  ALargo := 0;
  if not CabeceraDeFuente(CodigoPascal(ATexto), Cab) or (Cab.Palabra <> 'package') then
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
          Includes.AddOrSetValue(Incl.Replace('/', '\').ToLower, True);
      // las de TODAS las ramas de un uses partido: la vista, fix-references
      // y la mudanza veian solo la primera
      for E in U.Entries + U.OtrasRamas do
      begin
        P.Include := EntryInclude(E);
        if P.Include = '' then
          Continue; // library units (no `in`) are not project files
        P.UnitName := EntryUnitName(E);
        P.FormName := EntryFormName(E);
        P.InDproj := (not ANeedDproj) or Includes.ContainsKey(P.Include.Replace('/', '\').ToLower);
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

{ DONDE acaba la palabra de la seccion ASec (interface|implementation) en
  ACodigo (la vista CodigoPascal): la posicion 1-based detras de ella, 0 si
  no esta. LA regla de la seccion de un uses: estaba cinco veces en tres
  funciones (inventario del 10-oct-2026). La primera vez que la palabra sale
  ENTERA en el codigo, este donde este: se buscaba a principio de linea, y
  en 'unit X; interface uses A; implementation end.' no habia seccion
  (adduses negaba, y el renombrado de una unit, que desde el 18-oct-2026 mira
  sus clausulas, la necesita). Lo que la lleva dentro de otra palabra
  (dispinterface, IInterface) no; en una unit la seccion va antes que un
  'IX = interface'. }
function FinDeSeccion(const ACodigo, ASec: string): Integer;
var
  M: TMatch;
begin
  M := TRegEx.Match(ACodigo, '(?<![\w.])' + ASec + '\b', [roIgnoreCase]);
  if M.Success then
    Result := M.Index + M.Length
  else
    Result := 0;
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
    Result := Copy(Text, U.StartPos, U.EndPos - U.StartPos + 1);
end;

{ La OTRA seccion de ASec (interface <-> implementation) y su clausula uses
  (Found = False si no la tiene); ABlank, AText en la vista del codigo. UNA
  para adduses (una unit no va en las dos) y removeuses (lo que no esta en la
  suya y si en la otra, USES-024): estaba escrita dos veces (revisor de
  version de la 1.18.1). }
function UsesDeLaOtraSeccion(const AText, ABlank, ASec: string; out AOtra: string): TUsesClause;
var
  PosOtra: Integer;
begin
  AOtra := IfThen(SameText(ASec, 'interface'), 'implementation', 'interface');
  Result := Default(TUsesClause);
  PosOtra := FinDeSeccion(ABlank, AOtra);
  if PosOtra > 0 then
    Result := FindUses(AText, PosOtra);
end;

{ El nucleo de adduses sobre un TEXTO (ver AddUsesToUnit): estaba dentro de
  ella, y el insert de delphi_designer escribe la unidad JUNTO con su form,
  todo o nada (1.17.0). }
function UsesConUnidades(var AText: string; const ANames: TArray<string>;
  const ASec, AFichero: string; out AFaltan, AYaEstan, AEnOtra: TArray<string>;
  out ACreada: Boolean): string;
var
  Blank, OtraSec, NL, Nombre, E: string;
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
  NL := SaltoDominante(AText);
  U := FindUses(AText, PosSec);
  if U.Found and U.EnRamas then
    Exit(MsgFmt(SR_USES_EN_RAMAS_FMT, [U.Keyword, AFichero]));
  Entries := U.Entries;
  // La OTRA seccion tambien cuenta: una unit no puede ir en interface e
  // implementation a la vez (E2004 Identifier redeclared; Hermes lo midio
  // el 2026-09-23 con UPkgA en las dos).
  UOtra := UsesDeLaOtraSeccion(AText, Blank, ASec, OtraSec);
  for Nombre in ANames do
    if U.Found and LocateEntry(U, Nombre, E) then
      AYaEstan := AYaEstan + [Nombre]
    else if UOtra.Found and LocateEntry(UOtra, Nombre, E) then
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
      AText := Copy(AText, 1, PosSec - 1) + ' uses ' + string.Join(', ', AFaltan) + ';' +
        Copy(AText, PosSec, MaxInt)
    else
      EstrenaClausula(AText, FinLinea, 'uses' + NL + '  ' + string.Join(', ', AFaltan) + ';');
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
  var Pas := WalkFiles(Dir, '*.pas');
  SetLength(Result, Length(ANames));
  for var I := 0 to High(ANames) do
  begin
    Result[I] := '';
    for var F in Pas do
      if SameText(TPath.GetFileNameWithoutExtension(F), ANames[I]) and not SkipBajoLaRaiz(F, Dir) then
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
    if U.EnRamas then
      Exit(MsgFmt(SR_USES_EN_RAMAS_FMT, [U.Keyword, TPath.GetFileName(ADpr)]));
    Faltan := [];
    YaEstan := [];
    for var N in ANames do
    begin
      var Esta := False;
      for var E in U.Entries do
        if MismoIdentificador(EntryUnitName(E), N) then
          Esta := True;
      for var F in Faltan do
        if MismoIdentificador(F, N) then
          Esta := True;
      if Esta then
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
  if not MatchText(TPath.GetExtension(APasPath), ['.pas', '.dpr']) then
    Exit(MsgFmt(SR_ADDUSES_NOT_PAS_FMT, [TPath.GetFileName(APasPath)]));
  Names := [];
  for Nombre in ANames do
    if Nombre.Trim <> '' then
      Names := Names + [Nombre.Trim];
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
    Result := UsesConUnidades(Text, Names, Sec, TPath.GetFileName(APasPath),
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
  // para las que estan en el uses: la que no esta es USES-017, no remove-unit
  var Propias := UnidadesDelProyecto(ADpr, ANames);
  EnterFileEdit;
  try
    if not TFile.Exists(ADpr) then
      Exit(NoEsFichero(ADpr, MsgFmt(SR_ADDUSES_NO_FILE_FMT, [ADpr])));
    Text := PatchLoadText(ADpr, Enc);
    U := FindUses(Text);
    if not U.Found then
      Exit(MsgFmt(SN_REMOVEUSES_NO_CLAUSE_FMT, ['program', TPath.GetFileName(ADpr)]));
    if U.EnRamas then
      Exit(MsgFmt(SR_USES_EN_RAMAS_FMT, [U.Keyword, TPath.GetFileName(ADpr)]));
    Entries := U.Entries;
    Quitadas := [];
    NoEstaban := [];
    for var I := 0 to High(ANames) do
      if LocateEntry(U, ANames[I], E) then
      begin
        // del proyecto: con su in '...' aunque el .pas viva fuera del arbol,
        // o con su .pas en el
        if EntryInclude(E) <> '' then
          Exit(MsgFmt(SR_REMOVEUSES_UNIDAD_DEL_PROYECTO_FMT, [ANames[I], EntryInclude(E)]));
        if Propias[I] <> '' then
          Exit(MsgFmt(SR_REMOVEUSES_UNIDAD_DEL_PROYECTO_FMT, [ANames[I], Propias[I]]));
        Quitadas := Quitadas + [ANames[I]];
        Entries := EntriesWithout(Entries, ANames[I]);
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
      if LocateEntry(UO, N, Ent) then
        Estan := Estan + [N];
    if Length(Estan) > 0 then
      Result := MsgFmt(SN_REMOVEUSES_EN_LA_OTRA_FMT, [string.Join(', ', Estan), Otra, Otra]);
  end;

begin
  if not MatchText(TPath.GetExtension(APasPath), ['.pas', '.dpr']) then
    Exit(MsgFmt(SR_REMOVEUSES_NOT_PAS_FMT, [TPath.GetFileName(APasPath)]));
  Names := [];
  for Nombre in ANames do
    if Nombre.Trim <> '' then
      Names := Names + [Nombre.Trim];
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
    if U.EnRamas then
      Exit(MsgFmt(SR_USES_EN_RAMAS_FMT, [U.Keyword, TPath.GetFileName(APasPath)]));
    Entries := U.Entries;
    Quitadas := [];
    NoEstaban := [];
    for Nombre in Names do
      if LocateEntry(U, Nombre, E) then
      begin
        Quitadas := Quitadas + [Nombre];
        Entries := EntriesWithout(Entries, Nombre);
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
  (ReadPathDenied) y con tope de niveles para el modo sin jaula, acumulando
  en ADirs sin repetir. Un solo buscador para ProjectsUsingUnit y
  WorkspacePackagesWithUnit (24-sep-2026), no dos. }
procedure SubeCarpetas(ADesde: string; var ADirs: TArray<string>);
var
  Padre: string;
  Niveles: Integer;
begin
  Niveles := 0;
  while (ADesde <> '') and (Niveles < 12) and (ReadPathDenied(ADesde) = '') do
  begin
    if not MatchText(ADesde, ADirs) then
      ADirs := ADirs + [ADesde];
    Padre := TPath.GetDirectoryName(ADesde);
    if (Padre = '') or SameText(Padre, ADesde) then
      Break;
    ADesde := Padre;
    Inc(Niveles);
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
        if not MatchText(Sub, ADirs) and (ReadPathDenied(Sub) = '') then
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
      if SameText(TPath.GetFullPath(F), TPath.GetFullPath(ADpkPath)) then
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
  if not MatchText(TPath.GetExtension(F), ['.dpr', '.dpk']) or not TFile.Exists(F) then
    Exit;
  if AConSuFuente and (NormPath(F) = NormPath(APasPath)) then
    Exit(True);
  // el nombre de la unit sale del nombre LARGO: el de UPROVE~1.PAS no es UPROVE~1
  Stem := TPath.GetFileNameWithoutExtension(LongCanonical(APasPath));
  for var P in UnitsParaBuscar(F, Stem) do
    if MismoIdentificador(P.UnitName, Stem) and
      (NormPath(TPath.Combine(TPath.GetDirectoryName(F), P.Include)) = NormPath(APasPath)) then
      Exit(True);
end;

function ProjectsUsingUnit(const APasPath: string; const AAlsoDir: string): TArray<string>;
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
  // Y la misma subida desde la carpeta de DESTINO de un move: la unit
  // volvia a la carpeta de su paquete desde la de arriba, y el .dpk que la
  // lista vive ABAJO, donde el origen no mira (Hermes, 2026-09-23). Un solo
  // buscador con dos puntos de partida, no dos buscadores.
  Dirs := [];
  SubeCarpetas(Dir, Dirs);
  if AAlsoDir <> '' then
    SubeCarpetas(TPath.GetFullPath(AAlsoDir), Dirs);
  // ...y las carpetas de al lado de cada nivel (SitiosDeProyectos): el .dpr
  // de app\ que lista ..\scratch\U.pas no esta en la subida desde scratch\
  for D in SitiosDeProyectos(Dirs) do
  begin
    for F in TDirectory.GetFiles(D, '*.dp?') do // .dpr y .dpk, no .dproj
      if MatchText(TPath.GetExtension(F), ['.dpr', '.dpk']) then
        if ProyectoListaUnidad(F, APasPath) then // the .dpr decides; no .dproj read
          Result := Result + [F];
  end;
end;

{ Reescribe el NOMBRE de una unit como identificador entero en un fuente: las
  entradas de sus uses (interface e implementation) y las referencias
  cualificadas UnitVieja.Identificador. Solo en el CODIGO, segun el lexico:
  ni en cadenas ni en comentarios (David, 2-oct-2026; hasta entonces los
  comentarios si, "que un comentario que nombra la unit vieja tambien
  miente", y las cadenas se contaban por comillas impares en la linea, que
  un apostrofo dentro de un comentario de llave despistaba: la referencia de
  detras se quedaba sin renombrar y el build caia con E2003, medido con la
  sonda del lexico). La cabecera "unit X;" no se toca: la reescribe el que mueve
  el fichero. Devuelve cuantas ocurrencias cambio (0 = fichero intacto, no se
  reescribe). Medido por Hermes el 2026-09-22 (test 19): tras el rename el
  .dpr conservaba UBatHelper.Bat11Sum y el build caia con E2003. }
function RenombrarIdentificadorUnit(const APath, AViejo, ANuevo: string): Integer;
var
  Enc, Texto, Linea: string;
  Lineas, Saltos, Vistas, SaltosVista: TArray<string>;
  Re: TRegEx;
  M: TMatch;
  I, Ultimo: Integer;
  Partes: TStringBuilder;
begin
  Result := 0;
  Texto := PatchLoadText(APath, Enc);
  Re := TRegEx.Create('(?<!\.)' + PatronIdentEntero(AViejo), [roIgnoreCase]);
  // cada linea con SU salto, que vuelve intacto (Lsp.Patch.SplitToLinesConSalto):
  // troceaba solo por LF, y un fichero de CR sueltos era UNA linea que empezaba
  // por "unit" y no se reescribia (MOVED y el build caia; novena revision)
  Lineas := SplitToLinesConSalto(Texto, Saltos);
  // el nombre se busca en la vista del codigo (mismo largo y mismos saltos:
  // sus lineas son las del texto) y se cambia en el texto, en esa posicion
  var VistaTexto := CodigoPascal(Texto);
  Vistas := SplitToLinesConSalto(VistaTexto, SaltosVista);
  // el NOMBRE de la cabecera no se toca (lo cambia quien mueve): su sitio,
  // por EL lector de la cabecera (Lsp.Pascal), tambien partida en varias; lo
  // demas de sus lineas, si. Se miraba si la linea empezaba por 'unit ' (con
  // un tabulador detras, no), y despues se saltaban las lineas enteras: un
  // uses en la linea de la cabecera se quedaba con el nombre viejo (revisor 8,
  // 10-oct-2026)
  var NomIni := 0;
  var NomFin := 0;
  var Cab: TCabeceraFuente;
  var HayCab := CabeceraDeFuente(VistaTexto, Cab);
  if HayCab and (Cab.Palabra = 'unit') then
  begin
    NomIni := Cab.NombreIni;
    NomFin := Cab.NombreIni + Cab.NombreLen;
  end;
  // donde el nombre ES la unit: una entrada de sus clausulas (los uses de
  // interface e implementation; el uses o contains de un programa o un
  // paquete, con sus ramas), y fuera de ellas delante de un punto (Vieja.X).
  // Se cambiaba TODO identificador igual: un campo o una variable con el
  // nombre de la unit pasaban a llamarse como la nueva, y el build caia con
  // E2003 y la tool decia MOVED (medido el 18-oct-2026). Por EL lector de
  // las clausulas (FindUses) y EL de la seccion (FinDeSeccion)
  var Clausulas: TArray<TUsesClause> := [];
  if HayCab and (Cab.Palabra = 'unit') then
  begin
    for var Sec in TArray<string>.Create('interface', 'implementation') do
    begin
      var PosSec := FinDeSeccion(VistaTexto, Sec);
      if PosSec > 0 then
      begin
        var U := FindUses(Texto, PosSec);
        if U.Found then
          Clausulas := Clausulas + [U];
      end;
    end;
  end
  else
  begin
    var U := FindUses(Texto);
    if U.Found then
      Clausulas := Clausulas + [U];
  end;
  var IniLinea := 1; // donde empieza la linea I en el texto (1-based)
  for I := 0 to High(Lineas) do
  begin
    if I > 0 then
      Inc(IniLinea, Length(Vistas[I - 1]) + Length(SaltosVista[I - 1]));
    Linea := Lineas[I];
    Partes := TStringBuilder.Create;
    try
      Ultimo := 0; // 0-based: hasta donde se ha copiado ya la linea
      for M in Re.Matches(Vistas[I]) do
      begin
        var PosAbs := IniLinea + M.Index - 1; // en el texto, 1-based
        if (PosAbs >= NomIni) and (PosAbs < NomFin) then
          Continue;
        var EnClausula := False;
        for var U in Clausulas do
          if (PosAbs >= U.StartPos) and (PosAbs <= U.FinRamas) then
            EnClausula := True;
        // delante de un punto (y no de un rango: '..'), en la vista del codigo
        var J := PosAbs + M.Length;
        while (J <= Length(VistaTexto)) and VistaTexto[J].IsWhiteSpace do
          Inc(J);
        var Punto := (J < Length(VistaTexto)) and (VistaTexto[J] = '.') and (VistaTexto[J + 1] <> '.');
        // en una clausula, la entrada (Vieja.Algo seria OTRA unit, con
        // puntos); fuera, solo la cualificada
        if EnClausula = Punto then
          Continue;
        Partes.Append(Linea.Substring(Ultimo, M.Index - 1 - Ultimo));
        Partes.Append(ANuevo);
        Ultimo := M.Index - 1 + M.Length;
        Inc(Result);
      end;
      if Ultimo = 0 then
        Continue;
      Partes.Append(Linea.Substring(Ultimo));
      Lineas[I] := Partes.ToString;
    finally
      Partes.Free;
    end;
  end;
  if Result > 0 then
    PatchSaveText(APath, UneConSusSaltos(Lineas, Saltos), Enc);
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
    if not MatchText(X.Nombre, ['I', 'INCLUDE', 'R', 'RESOURCE', 'L', 'LINK']) then
      Continue;
    // {$R a.res a.rc}: el .rc del que sale el .res es la SEGUNDA ruta de la
    // misma directiva, y tambien es un fichero (revision 26-sep-2026)
    Maximo := 1;
    if MatchText(X.Nombre, ['R', 'RESOURCE']) then
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
  Result := StartsText(IncludeTrailingPathDelimiter(NormPath(AArbol)),
    IncludeTrailingPathDelimiter(NormPath(ARuta)));
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
  // del 26-sep-2026).
  if ADebeExistir and not (TFile.Exists(Nuevo) or TDirectory.Exists(Nuevo)) then
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
  AtributosDeTramo). Devuelve cuantas rutas cambio. }
function ReapuntaSitios(const AFichero, ABaseVieja: string;
  const ASitios: TArray<TSitioDeRutas>; const AMapa: TFunc<string, string>): Integer;
var
  Enc, Texto: string;
  Cambios: TArray<TCambioTexto>;
  Cuenta: Integer;

  procedure Reapunta(AIni, AFin: Integer; const AExtension: string; AComilla: Char);
  begin
    var Escrito := Copy(Texto, AIni, AFin - AIni);
    // un valor con un CDATA o un comentario dentro no se sabe reescribir
    if Escrito.Contains('<') or
       ((AExtension <> '') and not Escrito.Trim.ToLower.EndsWith(AExtension)) then
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
  if Result > 0 then
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
  for var E in TArray<string>.Create('DCC_UnitSearchPath', 'DCC_IncludePath',
    'DCC_ResourcePath', 'DCC_ObjPath', 'Icon_MainIcon', 'Manifest_File',
    'CfgDependentOn') do
    Result := Result + [Sitio(E)];
  for var E in BUILD_OUTPUT_TAGS do
    Result := Result + [Sitio(E)];
  Result := Result + [Sitio('RcCompile', 'Include'), Sitio('RcItem', 'Include'),
    Sitio('DeployFile', 'LocalName'), Sitio('Import', 'Project', '.optset'),
    Sitio('Import', 'Condition', '.optset', True)];
end;

function ReapuntaDirectivas(const AFichero, ABaseVieja: string;
  const AMapa: TFunc<string, string>): Integer;
var
  Enc, Texto: string;
  Cambios: TArray<TCambioTexto>;
begin
  Result := 0;
  Texto := PatchLoadText(AFichero, Enc);
  Cambios := [];
  for var D in DirectivasDeFichero(Texto) do
  begin
    var R := RutaReapuntada(D.Ruta, ABaseVieja, AFichero, AMapa, True);
    if R <> '' then
    begin
      var C: TCambioTexto;
      C.Inicio := D.Inicio;
      C.Largo := D.Largo;
      C.Texto := R;
      // sin comillas, una ruta nueva con un espacio no se leeria entera
      if (D.Comilla = #0) and R.Contains(' ') then
        C.Texto := '''' + R + '''';
      Cambios := Cambios + [C];
      Inc(Result);
    end;
  end;
  if Result > 0 then
    PatchSaveText(AFichero, AplicaCambios(Texto, Cambios), Enc);
end;

{ Los proyectos de un grupo viven en TRES sitios del fichero: el Include de
  su <Projects>, el Projects= del MSBuild de sus targets y las
  <Dependencies> de los que dependen de el (esas no se re-apuntaban). }
function ReapuntaGrupo(const AGroup, ABaseVieja: string;
  const AMapa: TFunc<string, string>): Integer;
begin
  Result := ReapuntaSitios(AGroup, ABaseVieja, [Sitio('Projects', 'Include'),
    Sitio('MSBuild', 'Projects'), Sitio('Dependencies')], AMapa);
end;

{ Las units que lista un proyecto y cuyo destino dice AMapa: por
  RenameProjectUnit, que re-apunta el .dpr/.dpk y el DCCReference a la vez. }
{ Si RenameProjectUnit dice que LO HIZO (su respuesta empieza como
  SN_UNIT_RENAMED_FMT). Lo preguntan la mudanza y fix-references: los dos
  contaban el intento como hecho (revision 26-sep-2026). }
function Reapuntada(const AResp: string): Boolean;
begin
  Result := EsMsg(AResp, SN_UNIT_RENAMED_FMT);
end;

function ReapuntaUnits(const AProyecto, ABaseVieja: string;
  const AMapa: TFunc<string, string>; var AFallos: TArray<string>): Integer;
begin
  Result := 0;
  for var PU in ProjectUnits(AProyecto, False) do
    if PU.Include <> '' then
    begin
      var R := RutaReapuntada(PU.Include, ABaseVieja, AProyecto, AMapa);
      if R = '' then
        Continue;
      var Nuevo := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(AProyecto), R));
      if not TFile.Exists(Nuevo) then
        Continue;
      // la ruta la da el .dpr y puede salir de lo movido (..\..\Shared\X.pas):
      // fuera de las raices ni se lee ni se re-apunta, y se dice (la lectura
      // escondida de la mudanza: medida M1)
      var Fuera := ReadPathDenied(Nuevo);
      if Fuera <> '' then
      begin
        AFallos := AFallos + [TPath.GetFileName(AProyecto) + ': ' + PrimerTrozo(Fuera, [#10])];
        Continue;
      end;
      // La ruta VIEJA de verdad: RenameProjectUnit busca en el .dpr por el
      // nombre que sale de ella, y en un rename no es el nuevo. Se pasaba la
      // nueva dos veces: el rename no encontraba nada y se contaba como hecho
      // (revision 26-sep-2026). Solo cuenta lo que dice REAPUNTADA.
      var Viejo := TPath.GetFullPath(TPath.Combine(ABaseVieja, PU.Include));
      var Resp := RenameProjectUnit(AProyecto, Viejo, Nuevo);
      if Reapuntada(Resp) then
        Inc(Result)
      else
        AFallos := AFallos + [TPath.GetFileName(AProyecto) + ': ' + PrimerTrozo(Resp, [#10])];
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
  if Length(WorkspaceRoots) = 0 then
  begin
    Padre := TPath.GetDirectoryName(ADir);
    if Padre <> '' then
      Result := Padre;
    Exit;
  end;
  for var Niveles := 1 to 12 do
  begin
    Padre := TPath.GetDirectoryName(Result);
    if (Padre = '') or SameText(Padre, Result) or (EscrituraDenegada(Padre) <> '') then
      Break;
    Result := Padre;
  end;
end;

function BordeDesde(const ADir: string): string; forward;

{ Lo que el build de AFichero, un .dproj ya re-apuntado, sigue leyendo donde
  ESTABA lo movido (AViejo, que ahora es ANuevo): un trozo de un sitio de ruta
  que la mudanza no re-apunta (RutaReapuntada) - el que llega por una
  propiedad del documento ($(My-Path): una propiedad puede ser cualquier cosa
  y no se reescribe) o el escrito absoluto -. Cada valor, expandido como lo
  tiene msbuild donde lo lee (ValoresQueLeeElBuild, EL expansor de la puerta
  del build) en cada build que el proyecto declara, antes (AXmlAntes, desde
  ABaseVieja) y despues (desde su carpeta de ahora): lo que llevaba a un sitio
  que existe y ya no lleva a donde ese sitio esta ahora. Se NOMBRA, uno por
  valor (Opus en Hermes, 22-oct-2026: tras mover lib, un $(My-Path)=lib daba
  F2613 sin pista y la descripcion prometia nombrar lo que no re-apunta). }
function RutasQueYaNoLlegan(const AFichero, AXmlAntes, ABaseVieja, AViejo,
  ANuevo: string): TArray<string>;
var
  Enc, XmlAhora, BaseNueva, Mal: string;
  Propiedades, Items, Plataformas, Configs: TArray<string>;
  Info: TDprojInfo;

  // un trozo ya expandido, resuelto desde ABase; '' si no se sabe a donde
  // lleva (lo que el documento no sabe queda escrito como $(X))
  function Resuelto(const ATrozo, ABase: string): string;
  begin
    Result := '';
    if ATrozo.Contains('$(') or ATrozo.Contains('@(') or ATrozo.Contains('%(') then
      Exit;
    try
      if TPath.IsPathRooted(ATrozo) then
        Result := SinBarraFinal(TPath.GetFullPath(ATrozo))
      else
        Result := SinBarraFinal(TPath.GetFullPath(TPath.Combine(ABase, ATrozo)));
    except
      Result := '';
    end;
  end;

  // si algun sitio de ruta lleva un trozo que RutaReapuntada se salta: uno
  // absoluto o uno que empieza por una propiedad que el documento define (no
  // la del propio elemento: $(DCC_UnitSearchPath), la herencia que escribe el
  // IDE). Lo demas lo re-apunto ella; sin esto no se evalua nada
  function HayQueMirar: Boolean;
  var
    Els: TArray<TElementoXml>;
    Definidas, Valores: TArray<string>;
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
          var Q := Pos(')', T);
          if T.StartsWith('$(') and (Q > 3) then
          begin
            var Nombre := Copy(T, 3, Q - 3);
            if not SameText(Nombre, E.Escrito) and MatchText(Nombre, Definidas) then
              Exit(True);
          end;
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
  Plataformas := [];
  for var P in Info.Platforms do
    if P.Enabled then
      Plataformas := Plataformas + [P.Name];
  if Length(Plataformas) = 0 then
    Plataformas := [Info.PlataformaPorDefecto];
  Configs := Info.Compilables;
  if Length(Configs) = 0 then
    Configs := [Info.ConfigPorDefecto];
  for var Plat in Plataformas do
    for var Cfg in Configs do
    begin
      var Antes := ValoresQueLeeElBuild(AXmlAntes, Plat, Cfg, [], []);
      var Ahora := ValoresQueLeeElBuild(XmlAhora, Plat, Cfg, [], []);
      // la reescritura no quita ni pone valores: si no casan, no se compara
      if Length(Antes) <> Length(Ahora) then
        Continue;
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
          var R := Resuelto(T, ABaseVieja);
          if R = '' then
            Continue;
          // donde esta AHORA lo que leia: movido si estaba dentro
          var Destino := R;
          if DentroDe(R, AViejo) then
            Destino := ANuevo + R.Substring(Length(AViejo));
          if MatchText(Destino, Leidas) or not (TDirectory.Exists(Destino) or TFile.Exists(Destino)) then
            Continue;
          var Item := MsgFmt(SF_REUBICA_NO_LLEGA_ITEM_FMT, [TPath.GetFileName(AFichero),
            Antes[I].Elemento, Antes[I].Escrito, R, Destino]);
          if not MatchText(Item, Result) then
            Result := Result + [Item];
        end;
      end;
    end;
end;

function ReubicaArbol(const AViejo, ANuevo: string; ACopia: Boolean): string;
var
  Viejo, Nuevo: string;
  NUnits, NRutas, NDirect, NGrupos, NFuera: Integer;
  Tocados, Fallos, Saltadas, NoLlegan: TArray<string>;
  EsDeMudanza: TFunc<string, Boolean>;

  procedure Anota(const AFichero: string; ACuantos: Integer; var ASuma: Integer);
  begin
    if ACuantos <= 0 then
      Exit;
    Inc(ASuma, ACuantos);
    // por la ruta entera: dos App.dproj de carpetas distintas son dos
    if not MatchText(AFichero, Tocados) then
      Tocados := Tocados + [AFichero];
  end;

  procedure Falla(const AFichero: string; E: Exception);
  begin
    Fallos := Fallos + [TPath.GetFileName(AFichero) + ': ' + E.Message];
  end;

  { UN reparto por formato, el mismo dentro y fuera (estaba escrito dos
    veces), y cada reescritura en su try: un fallo en una no se lleva las
    demas del mismo fichero. }
  procedure Reapunta(const AFichero, ABase: string; const AMapa: TFunc<string, string>;
    var AUnits, ARutas, ADirect, AGrupos: Integer);
  var
    Ext, EncAntes, Antes: string;
  begin
    Ext := LowerCase(TPath.GetExtension(AFichero));
    if (Ext = '.dpr') or (Ext = '.dpk') then
      try
        Anota(AFichero, ReapuntaUnits(AFichero, ABase, AMapa, Fallos), AUnits);
      except
        on E: Exception do
          Falla(AFichero, E);
      end;
    if Ext = '.dproj' then
    begin
      Antes := '';
      try
        // el de antes, para lo que el build lee por una propiedad o absoluto
        Antes := PatchLoadText(AFichero, EncAntes);
        Anota(AFichero, ReapuntaSitios(AFichero, ABase, SitiosDeDproj, AMapa), ARutas);
      except
        on E: Exception do
          Falla(AFichero, E);
      end;
      if (Antes <> '') and not ACopia then
        try
          for var N in RutasQueYaNoLlegan(AFichero, Antes, ABase, Viejo, Nuevo) do
            if not MatchText(N, NoLlegan) then
              NoLlegan := NoLlegan + [N];
        except
          // una nota, no una reescritura: si no se puede evaluar no hay nota,
          // y lo re-apuntado queda como esta (no es un fallo de la mudanza)
        end;
    end;
    if Ext = '.deployproj' then
      try
        Anota(AFichero, ReapuntaSitios(AFichero, ABase,
          [Sitio('DeployFile', 'Include')], AMapa), ARutas);
      except
        on E: Exception do
          Falla(AFichero, E);
      end;
    if EsRutaDeFuente(AFichero) then // EL predicado (era SOURCE_EXTS a mano)
      try
        Anota(AFichero, ReapuntaDirectivas(AFichero, ABase, AMapa), ADirect);
      except
        on E: Exception do
          Falla(AFichero, E);
      end;
    if Ext = '.groupproj' then
      try
        Anota(AFichero, ReapuntaGrupo(AFichero, ABase, AMapa), AGrupos);
      except
        on E: Exception do
          Falla(AFichero, E);
      end;
  end;

begin
  Result := '';
  Viejo := PrefijoSinBarra(TPath.GetFullPath(AViejo));
  Nuevo := PrefijoSinBarra(TPath.GetFullPath(ANuevo));
  NUnits := 0; NRutas := 0; NDirect := 0; NGrupos := 0; NFuera := 0;
  Tocados := [];
  Fallos := [];
  Saltadas := [];
  NoLlegan := [];
  // Lo de DENTRO que apunta FUERA: su destino no se ha movido, y es el
  // relativo el que ya no llega. Lo de dentro que apunta dentro viaja con el.
  var Fuera: TFunc<string, string> :=
    function(A: string): string
    begin
      if DentroDe(A, Viejo) then
        Result := ''
      else
        Result := A;
    end;
  // Lo de FUERA que apuntaba DENTRO: su destino SI se ha movido.
  var Traslada: TFunc<string, string> :=
    function(A: string): string
    begin
      if DentroDe(A, Viejo) then
        Result := Nuevo + TPath.GetFullPath(A).Substring(Length(Viejo))
      else
        Result := '';
    end;
  EsDeMudanza :=
    function(F: string): Boolean
    begin
      Result := MatchText(TPath.GetExtension(F), ['.dpr', '.dpk', '.dproj', '.pas',
        '.inc', '.groupproj', '.deployproj']);
    end;

  // Con el cerrojo de las ediciones: la misma carrera que perdia cambios en
  // delphi_edit (medido: 6 de 12) la tenia la mudanza, que lee, cambia y
  // guarda proyectos y grupos que otra llamada puede estar tocando.
  EnterFileEdit;
  try
    for var F in FicherosBajo(Nuevo, EsDeMudanza, 0, Saltadas) do
      Reapunta(F, TPath.GetDirectoryName(Viejo + F.Substring(Length(Nuevo))), Fuera,
        NUnits, NRutas, NDirect, NGrupos);
    // Y si no es copia, FUERA, todo lo que apuntaba DENTRO de lo movido: un
    // {$I} de una unit de fuera, un proyecto de una carpeta HERMANA... Se
    // recorre desde el borde escribible (BordeDeMudanza) con el mismo
    // recorredor y el mismo reparto.
    if not ACopia then
      for var F in FicherosBajo(BordeDeMudanza(TPath.GetDirectoryName(Viejo)),
        EsDeMudanza, 0, Saltadas) do
        if not DentroDe(F, Nuevo) then
          Reapunta(F, TPath.GetDirectoryName(F), Traslada, NFuera, NFuera, NFuera, NFuera);
  finally
    LeaveFileEdit;
  end;

  if NUnits + NRutas + NDirect + NGrupos + NFuera > 0 then
  begin
    var Nombres: TArray<string> := [];
    for var T in Tocados do
      Nombres := Nombres + [TPath.GetFileName(T)];
    Result := MsgFmt(SN_REUBICA_FMT, [NUnits, NRutas, NDirect, NGrupos, NFuera,
      string.Join(', ', Nombres)]);
  end;
  if Length(Fallos) > 0 then
    Result := Result + IfThen(Result <> '', #10, '') +
      MsgFmt(SN_REUBICA_FALLOS_FMT, [string.Join('; ', Fallos)]);
  if Length(Saltadas) > 0 then
    Result := Result + IfThen(Result <> '', #10, '') +
      MsgFmt(SN_REUBICA_SALTADAS_FMT, [string.Join('; ', Saltadas)]);
  if Length(NoLlegan) > 0 then
    Result := Result + IfThen(Result <> '', #10, '') +
      MsgFmt(SN_REUBICA_NO_LLEGA_FMT, [string.Join('; ', NoLlegan)]);
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
    Result := SameText(NormPath(TPath.Combine(TPath.GetDirectoryName(AGroup), AInclude)),
      NormPath(AAbs));
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
  Nombre := TPath.GetFileNameWithoutExtension(Proj);
  // El IDE nombra los targets por el proyecto: dos con el mismo nombre en un
  // grupo no caben. Se dice, no se inventa un sufijo.
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
      Result := SameText(TPath.GetFileName(F), ANombre);
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
        Abs := TPath.GetFullPath(TPath.Combine(Base, I));
        // lo de fuera de lo que esta sesion puede leer ni se mira ni se
        // dice (ni si existe), como en el view de un grupo
        if (ReadPathDenied(Abs) <> '') or TFile.Exists(Abs) then
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
      Abs := TPath.GetFullPath(TPath.Combine(Base, PU.Include));
      if (ReadPathDenied(Abs) <> '') or TFile.Exists(Abs) then
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
           not MatchText(R.Escrita, RutasFaltan) then
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
  // con el cerrojo de las ediciones, como toda reescritura de proyectos
  // (el de un grupo corria sin el)
  EnterFileEdit;
  try
    Result := ArreglaReferenciasNucleo(AProject);
  finally
    LeaveFileEdit;
  end;
end;

end.
