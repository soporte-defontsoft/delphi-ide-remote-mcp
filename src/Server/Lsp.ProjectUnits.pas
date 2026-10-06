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
  System.SysUtils, System.Classes, System.JSON;

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
    DesignClass: string; // 'TDataModule' | 'TFrame' | '' (plain form)
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

{ Adds the unit to the .dpr uses (+ CreateForm) and the .dproj. Idempotent:
  an entry already present is left alone and reported. }
function AddProjectUnit(const AProject, APasPath: string): string;

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

{ Paquetes (.dpk) del workspace cuya clausula contains lista la unit
  AUnitName, subiendo desde la carpeta de ADpkPath hasta el borde de la jaula
  (el MISMO buscador que ProjectsUsingUnit); el propio ADpkPath no cuenta.
  Es la pista de requires de delphi_build cuando la unit no esta en ningun
  BPL de la instalacion (punto 8 de Hermes; David, 24-sep-2026): solo pista,
  sin comprobar dcp ni instalacion - compilar el paquete es cosa del agente. }
function WorkspacePackagesWithUnit(const ADpkPath, AUnitName: string): TArray<string>;

{ La cabecera "unit X;" de un .pas: el nombre tal cual y donde empieza
  (1-based), fuera de comentarios y con las directivas que admite detras
  (platform, deprecated, library, experimental). False si no la hay. UN
  lector: InspectUnit la leia con una regex que solo casaba "unit X;" y
  delphi_move la reescribia con otra igual - "unit X platform;" ni se
  registraba ni se reescribia, y MOVE-015 decia que si (decima revision). }
function CabeceraDeUnit(const ASrc: string; out ANombre: string;
  out AInicio: Integer): Boolean;

{ adduses de delphi_edit: nombres de unit al uses de una seccion (interface o
  implementation) de un .pas; la clausula la escribe el motor. }
function AddUsesToUnit(const APasPath: string; const ANames: TArray<string>;
  const ASection: string): string;
{ removeuses de delphi_edit: la inversa; la clausula se va entera si queda vacia. }
function RemoveUsesFromUnit(const APasPath: string; const ANames: TArray<string>;
  const ASection: string): string;

function RenombrarIdentificadorUnit(const APath, AViejo, ANuevo: string): Integer;

{ La ruta de APas vista desde la carpeta de ADpr, en la forma que escribe el
  IDE (Sub\X.pas, ..\..\shared\X.pas; absoluta solo en otra unidad). EL
  nombrador de rutas relativas: las units de un proyecto, los proyectos de
  un grupo, los search paths y las directivas que re-apunta una mudanza. }
function IncludeFor(const ADpr, APas: string): string;

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
  Lsp.Dproj,       // XmlUnescape: el lector de la casa
  Lsp.References,
  Lsp.NetDrives,  // SkipIdeArtifacts: una mudanza no entra en artefactos
  Lsp.Pascal,
  Lsp.PascalDecl; // EL lector de clases y LA cadena de ancestros

{ TUnitInfo }

function TUnitInfo.IsDesigner: Boolean;
begin
  Result := Designer <> '';
end;

function TUnitInfo.NeedsCreateForm: Boolean;
begin
  Result := IsDesigner and (FormName <> '') and (DesignClass <> 'TFrame');
end;

{ ---- paths ---- }

function NormPath(const P: string): string;
begin
  // la forma LARGA (Lsp.Guard.LongCanonical): UPROVE~1.PAS y
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
  Ext, Stem: string;
begin
  Result := '';
  ADpr := '';
  ADproj := '';
  if AProject.Trim = '' then
    Exit(MsgText(SR_UNIT_NEED_PROJECT));
  Ext := TPath.GetExtension(AProject).ToLower;
  Stem := TPath.Combine(TPath.GetDirectoryName(TPath.GetFullPath(AProject)),
    TPath.GetFileNameWithoutExtension(AProject));
  if (Ext <> '.dpr') and (Ext <> '.dpk') and (Ext <> '.dproj') then
    Exit(MsgFmt(SR_UNIT_PROJECT_EXT_FMT, [TPath.GetFileName(AProject)]));
  // Un paquete es un proyecto: su fuente principal es el .dpk (con clausula
  // contains en vez de uses) y el .dproj es el mismo. Desde un .dproj se
  // decide por lo que hay en disco: el .dpr si existe, si no el .dpk.
  // (Hermes, bateria 1.2 caso 1: sin esto un paquete propio no se podia
  // trabajar por tools.)
  if Ext = '.dpk' then
    ADpr := Stem + '.dpk'
  else if (Ext = '.dproj') and (not TFile.Exists(Stem + '.dpr')) and TFile.Exists(Stem + '.dpk') then
    ADpr := Stem + '.dpk'
  else
    ADpr := Stem + '.dpr';
  ADproj := Stem + '.dproj';
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

{ ---- unit inspection ---- }

function DesignerHeaderName(const ADesigner: string; out AName, AClass: string): Boolean;
var
  B: TBytes;
  Enc, Line, Clave, Nombre, Clase: string;
  Lines: TArray<string>;
begin
  Result := False;
  AName := '';
  AClass := '';
  B := TFile.ReadAllBytes(ADesigner);
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
  for Line in Lines do
  begin
    // THE reader of an object line (Lsp.DesignerBin); the root is never an
    // inline frame and always has a name
    if LineaDeObjeto(Line, Clave, Nombre, Clase) and (Clave <> 'inline') and (Nombre <> '') then
    begin
      AName := Nombre;
      AClass := Clase;
      Exit(True);
    end;
    if Line.Trim <> '' then
      Break; // the first non-blank line is the root object
  end;
end;

{ The IDE's DesignClass for an ancestor: TFrame / TDataModule (unit-qualified
  accepted), a class declared in the same unit is followed up the chain, and
  a custom base living elsewhere is classified by its NAME SUFFIX only
  (TBaseFrame -> frame, TDMBase -> form: the form side is the safe default
  because a spurious CreateForm on a frame breaks the build, a missing
  DesignClass on a data module only changes the IDE's icon). The chain is
  THE one (Lsp.PascalDecl.CadenaDeAncestros) over the classes of this unit
  (AnotaAncestros): its own regex did not follow 'class abstract(TFrame)'
  and add-unit wrote a CreateForm for a frame (4-oct-2026). }
function DesignClassOf(const AMapa: TDictionary<string, string>; const AAncestor: string): string;
var
  Name: string;
  Sale: Boolean;
begin
  Result := '';
  Name := '';
  for var C in CadenaDeAncestros(AMapa, AAncestor, Sale, 9) do // 8 saltos
  begin
    Name := UltimoTrozo(C);
    if SameText(Name, 'TFrame') or SameText(Name, 'TCustomFrame') then
      Exit('TFrame');
    if SameText(Name, 'TDataModule') then
      Exit('TDataModule');
    if SameText(Name, 'TForm') or SameText(Name, 'TCustomForm') or SameText(Name, 'TForm3D') then
      Exit('');
  end;
  if Name.EndsWith('Frame', True) then
    Result := 'TFrame'
  else if Name.EndsWith('DataModule', True) then
    Result := 'TDataModule';
end;

function InspectUnit(const APasPath: string; out AInfo: TUnitInfo): string;
var
  Enc, Src, Stem, DName, DClass, Cab: string;
  Ini: Integer;
  U: TUnidadPas;
  Mapa: TDictionary<string, string>;
begin
  Result := '';
  AInfo := Default(TUnitInfo);
  if not TFile.Exists(APasPath) then
    Exit(NoEsFichero(APasPath, MsgFmt(SR_UNIT_PAS_MISSING_FMT, [APasPath])));
  if TPath.GetExtension(APasPath).ToLower <> '.pas' then
    Exit(MsgFmt(SR_UNIT_NOT_PAS_FMT, [TPath.GetFileName(APasPath)]));
  AInfo.PasPath := TPath.GetFullPath(APasPath);
  Src := PatchLoadText(AInfo.PasPath, Enc);
  if not CabeceraDeUnit(Src, Cab, Ini) then
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

  // designer pair?
  if TFile.Exists(ChangeFileExt(AInfo.PasPath, '.dfm')) then
  begin
    AInfo.Designer := ChangeFileExt(AInfo.PasPath, '.dfm');
    AInfo.FormType := 'dfm';
  end
  else if TFile.Exists(ChangeFileExt(AInfo.PasPath, '.fmx')) then
  begin
    AInfo.Designer := ChangeFileExt(AInfo.PasPath, '.fmx');
    AInfo.FormType := 'fmx';
  end;
  if AInfo.Designer = '' then
    Exit;

  // the designer's root object names the form; the .pas gives the ancestor,
  // read by THE class reader (Lsp.PascalDecl) on its CODE: a commented class
  // ('TViejo = class(TForm)' between braces) is not the form's (censo del
  // lexico, 2-oct-2026)
  U := LeeFuentePascal(Src);
  Mapa := TDictionary<string, string>.Create;
  try
    AnotaAncestros(U, Mapa);
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
      // binary designer: the first designer class of the unit, then its variable
      for var T in U.Tipos do
        if (T.Clase = ctClase) and (T.Contenedor = '') and T.Nombre.StartsWith('T', True) and
           TRegEx.IsMatch(UltimoTrozo(T.Ancestro), '(?i)\AT(?:Form|DataModule|Frame)') then
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
    AInfo.DesignClass := DesignClassOf(Mapa, AInfo.Ancestor);
  finally
    Mapa.Free;
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
  end;

function CabeceraDeUnit(const ASrc: string; out ANombre: string;
  out AInicio: Integer): Boolean;
var
  M: TMatch;
begin
  ANombre := '';
  AInicio := 0;
  M := TRegEx.Match(CodigoPascal(ASrc),
    '^\s*unit\s+([^\s;]+)(?:\s+(?:platform|deprecated|library|experimental)\b[^;]*)?\s*;',
    [roIgnoreCase, roMultiline]);
  Result := M.Success;
  if Result then
  begin
    AInicio := M.Groups[1].Index;
    ANombre := Copy(ASrc, AInicio, M.Groups[1].Length);
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
// Los condicionales (IF, IFDEF, IFNDEF e IFOPT abren; ENDIF e IFEND
// cierran) que quedan ABIERTOS al final de ATexto.
function CondicionalesAbiertos(const ATexto: string): Integer;
begin
  Result := 0;
  for var D in DirectivasPascal(ATexto) do
    if MatchText(D.Nombre, ['IF', 'IFDEF', 'IFNDEF', 'IFOPT']) then
      Inc(Result)
    else if MatchText(D.Nombre, ['ENDIF', 'IFEND']) then
      Dec(Result);
end;

{ Las entradas de las OTRAS ramas de una clausula partida: de ADesde (tras el
  ';' de la primera) al condicional que la cierra. Cada rama acaba en su ';':
  se leen como una lista mas, sin las que solo son directivas. }
function EntradasDeOtrasRamas(const ATexto: string; ADesde, AAbiertos: Integer): TArray<string>;
var
  Prof, Fin: Integer;
begin
  Prof := AAbiertos;
  Fin := Length(ATexto) + 1;
  for var D in DirectivasPascal(Copy(ATexto, ADesde, MaxInt)) do
  begin
    if MatchText(D.Nombre, ['IF', 'IFDEF', 'IFNDEF', 'IFOPT']) then
      Inc(Prof)
    else if MatchText(D.Nombre, ['ENDIF', 'IFEND']) then
      Dec(Prof);
    if Prof <= 0 then
    begin
      Fin := ADesde + D.Inicio - 1;
      Break;
    end;
  end;
  Result := [];
  for var E in SplitEntries(Copy(ATexto, ADesde, Fin - ADesde).Replace(';', ',')) do
    if BlankComments(E).Trim <> '' then
      Result := Result + [E];
end;

function FindUses(const Dpr: string; AFrom: Integer = 0): TUsesClause;
var
  I, N, Start, K: Integer;
  M: TMatch;
  SeenProgram: Boolean;
  Token: string;
begin
  Result := Default(TUsesClause);
  Result.Keyword := 'uses';
  I := 1;
  SeenProgram := True;
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
    M := TRegEx.Match(CodigoPascal(Dpr), '^\s*(program|library|package)\b', [roIgnoreCase, roMultiline]);
    if M.Success then
    begin
      I := M.Index + M.Length;
      if SameText(M.Groups[1].Value, 'package') then
        Result.Keyword := 'contains';
    end;
    SeenProgram := not M.Success;
  end;
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
    if not SeenProgram then
    begin
      if Dpr[I] = ';' then
        SeenProgram := True; // end of `program X;`
      Inc(I);
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
      // Un ';' DENTRO de un condicional abierto cierra una rama, no la
      // clausula: las otras ramas van detras (el uses del nodo de escritorio,
      // Windows y Linux). Se leia solo la primera.
      var Abiertos := CondicionalesAbiertos(Copy(Dpr, Start, I - Start));
      if Abiertos > 0 then
      begin
        Result.EnRamas := True;
        Result.OtrasRamas := EntradasDeOtrasRamas(Dpr, I + 1, Abiertos);
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
  Result := (Length(L) >= 3) and SoloDirectiva(L[0], ['IFDEF', 'IFNDEF', 'IFOPT', 'IF']) and
    SoloDirectiva(L[High(L)], ['ENDIF', 'IFEND']);
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
  // la anterior ('UA, // de UB', medido el 2-oct-2026 con remove-unit) y se
  // queda en una linea suya, como el del ; final de una quitada.
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
  // el comentario que va DETRAS del ; final, en su misma linea, es de la
  // ULTIMA entrada original, y queda fuera de la clausula: con una unit
  // anadida detras se iba a la nueva ('Lsp.NetDrives; // PrefijoSinBarra'
  // salio 'Lsp.Texts; // PrefijoSinBarra', medido el 2-oct-2026 con adduses,
  // y lo mismo add-unit en un .dpr), y quitada su entrada se pegaba a la que
  // quedaba ('// de SysUtils // de Classes'). Se queda con su entrada; si su
  // entrada se fue, en una linea suya, como el de una quitada de en medio:
  // un comentario no se borra
  var Resto := U.EndPos + 1;   // desde donde sigue el texto de detras
  var Suelto := '';            // el de una entrada que ya no esta
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
          Copy(Dpr, U.EndPos + 1, PosCom - U.EndPos - 1), ' ') + Coment
      else
        Suelto := Coment;
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
  Result := Copy(Dpr, 1, U.StartPos - 1) + Body +
    IfThen(Suelto <> '', NL + Indent + Suelto, '') + Copy(Dpr, Resto, MaxInt);
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
  L: TStringList;
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
  L := TStringList.Create;
  try
    L.AddStrings(Lines);
    // right before Application.Run, like the IDE: a CreateForm placed after
    // the last one could land inside that one's conditional block
    if RunAt <> -1 then
    begin
      // la sangria, con el lector de la casa (Lsp.Patch.LeadingWhite):
      // habia cinco copias a mano con TrimLeft, que se lleva tambien los
      // caracteres de control (#0..#31) a la linea nueva (1.15.0)
      Indent := LeadingWhite(Lines[RunAt]);
      L.Insert(RunAt, Indent + CreateFormLine(AInfo));
    end
    else
    begin
      Indent := LeadingWhite(Lines[Last]);
      L.Insert(Last + 1, Indent + CreateFormLine(AInfo));
    end;
    Dpr := string.Join(NL, L.ToStringArray);
  finally
    L.Free;
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
  L: TStringList;
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
  L := TStringList.Create;
  try
    for I := 0 to High(Lines) do
    begin
      M := TRegEx.Match(Vista[I], Pat, [roIgnoreCase]);
      if not M.Success then
      begin
        L.Add(Lines[I]);
        Continue;
      end;
      Inc(Result);
      // la sentencia sola (el grupo): lo de delante en la vista son blancos,
      // y entre ellos puede ir el cierre del comentario de encima (medido:
      // con el match entero se iba la llave)
      var G := M.Groups[1];
      var Resto := Copy(Lines[I], 1, G.Index - 1) + Copy(Lines[I], G.Index + G.Length, MaxInt);
      if Resto.Trim <> '' then
        L.Add(Resto.TrimRight);
    end;
    if Result > 0 then
      Dpr := string.Join(NL, L.ToStringArray);
  finally
    L.Free;
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
  M: TMatch;
  Want, Got: string;
begin
  Result := False;
  Want := AInclude.Replace('/', '\').ToLower;
  for M in TRegEx.Matches(Xml, '[ \t]*<DCCReference\s+Include="([^"]*)"\s*(/>|>.*?</DCCReference>)\s*?(\r?\n|$)',
    [roIgnoreCase, roSingleline]) do
  begin
    Got := XmlUnescape(M.Groups[1].Value).Replace('/', '\').ToLower;
    if Got = Want then
    begin
      AStart := M.Index;
      ALen := M.Length;
      Exit(True);
    end;
  end;
end;

{ Inserts the element after the last DCCReference; else after </DelphiCompile>;
  else before the first <BuildConfiguration; else before the first </ItemGroup>. }
function InsertDccRef(const Xml, AElement: string): string;
var
  M: TMatch;
  At: Integer;
begin
  At := 0;
  for M in TRegEx.Matches(Xml, '[ \t]*<DCCReference\s[^>]*?(/>|>.*?</DCCReference>)[ \t]*\r?\n', [roIgnoreCase, roSingleline]) do
    At := M.Index + M.Length;
  if At = 0 then
  begin
    M := TRegEx.Match(Xml, '</DelphiCompile>[ \t]*\r?\n', [roIgnoreCase]);
    if M.Success then
      At := M.Index + M.Length
    else
    begin
      M := TRegEx.Match(Xml, '[ \t]*<BuildConfiguration\s', [roIgnoreCase]);
      if not M.Success then
        M := TRegEx.Match(Xml, '[ \t]*</ItemGroup>', [roIgnoreCase]);
      if not M.Success then
        Exit(Xml); // no ItemGroup at all: the caller reports "not in .dproj"
      At := M.Index;
    end;
  end;
  Result := Copy(Xml, 1, At - 1) + AElement + Copy(Xml, At, MaxInt);
end;

{ ---- public operations ---- }

function AddProjectUnitNucleo(const AProject, APasPath: string): string;
var
  Dpr, Dproj, Enc, Text, Include, Entry, Note: string;
  Info: TUnitInfo;
  U: TUsesClause;
  E: string;
  Present, Completada, Estrenada: Boolean;
  Entries: TArray<string>;
  S, L: Integer;
begin
  Result := ResolveProjectPair(AProject, Dpr, Dproj);
  if Result <> '' then
    Exit;
  Result := InspectUnit(APasPath, Info);
  if Result <> '' then
    Exit;
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
      var MEnd := TRegEx.Match(CodigoPascal(Text), '(?im)^\s*end\s*\.');
      if not MEnd.Success then
        Exit(MsgFmt(SR_UNIT_NO_USES_FMT, [TPath.GetFileName(Dpr)]));
      var NL := SaltoDominante(Text);
      Text := Copy(Text, 1, MEnd.Index - 1) + 'contains' + NL + '  ' +
        BuildEntry(Info, Include) + ';' + NL + NL + Copy(Text, MEnd.Index, MaxInt);
      PatchSaveText(Dpr, Text, Enc);
      Text := PatchLoadText(Dpr, Enc);
      U := FindUses(Text);
    end
    else
    begin
      // Un programa al que se le quito su ULTIMA unit tampoco la tiene (se va
      // entera: decima revision): la estrena justo tras la cabecera.
      var MCab := TRegEx.Match(CodigoPascal(Text), '(?im)^\s*(program|library)\b[^;]*;');
      if MCab.Success then
      begin
        Estrenada := True;
        var NL := SaltoDominante(Text);
        var Tras := MCab.Index + MCab.Length;
        Text := Copy(Text, 1, Tras - 1) + NL + NL + 'uses' + NL + '  ' +
          BuildEntry(Info, Include) + ';' + Copy(Text, Tras, MaxInt);
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
  if Info.NeedsCreateForm then
  begin
    if not InsertCreateForm(Text, Info) then
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

  if Completada then
    Result := MsgFmt(SN_UNIT_COMPLETED_FMT, [Info.UnitName, TPath.GetFileName(Dpr),
      Info.UnitName, Include])
  else if Present and not Estrenada then
    Result := MsgFmt(SN_UNIT_PRESENT_FMT, [Info.UnitName, TPath.GetFileName(Dpr)])
  else if Info.IsDesigner then
    Result := MsgFmt(SN_UNIT_ADDED_FORM_FMT, [Info.UnitName, Include, Info.FormName,
      Info.ClassName, TPath.GetFileName(Dpr), U.Keyword, TPath.GetFileName(Dpr),
      IfThen(Info.NeedsCreateForm, MsgText(SN_UNIT_CREATEFORM), '')])
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
  Dpr, Dproj, NoVolvio: string;
  Rutas: TArray<string>;
  Foto: TFotoDeFicheros;
begin
  if ResolveProjectPair(AProject, Dpr, Dproj) <> '' then
    Exit(AAccion()); // la accion dira lo que no cuadra; no hay que deshacer
  // AMas: lo que la accion reescribe ADEMAS del par (un rename, las units)
  Rutas := [Dpr, Dproj];
  Rutas := Rutas + AMas;
  Foto.Toma(Rutas);
  try
    Result := AAccion();
  except
    on E: Exception do
    begin
      NoVolvio := Foto.Restaura;
      if NoVolvio <> '' then
        raise Exception.Create(MsgFmt(SR_FOTO_NO_VOLVIO_FMT,
          [NoVolvio, MsgExcepcion(E.ClassName, E.Message)]));
      raise;
    end;
  end;
  if EsFallo(Result) then
  begin
    NoVolvio := Foto.Restaura;
    if NoVolvio <> '' then
      Result := MsgFmt(SR_FOTO_NO_VOLVIO_FMT, [NoVolvio, Result]);
  end;
end;

function ProyectoTodoONada(const AProject: string; const AAccion: TFunc<string>): string; overload;
begin
  Result := ProyectoTodoONada(AProject, [], AAccion);
end;

function AddProjectUnit(const AProject, APasPath: string): string;
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
        Result := AddProjectUnitNucleo(AProject, APasPath);
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
  E, Carry, Prefix, Core: string;
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
      Carry := Prefix; // its directive/comment stays, glued to the next entry
      // ...y las directivas que la entrada lleva DETRAS: 'DebugU{$ENDIF}'
      // perdia su ENDIF y el IFDEF de la de antes quedaba abierto (medido en
      // la revision de la 1.10.0; venia de antes). Por el lector UNICO de
      // directivas, cada una en su linea: aqui se escribio un gemelo suyo
      // (DirectivasDe) y lo encontro el censo del lexico, el mismo dia
      for var D in DirectivasPascal(Core) do
        Carry := IfThen(Carry <> '', Carry + #10, '') + Copy(Core, D.Inicio, D.Largo);
    end;
  if (Carry <> '') and (Length(Result) > 0) then
  begin
    // un // en la primera linea del prefijo iba detras de la coma de la
    // anterior: vuelve a SU linea (ReplaceUses pone el ; delante de el)
    var C := ConSalto(Carry, #10); // tambien el CR suelto (decima revision)
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
  if InspectUnit(APasPath, Info) = '' then
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
  Result := Format(IfThen(AFileGoesToo, MsgText(SN_UNIT_REMOVED_GONE_FMT),
    MsgText(SN_UNIT_REMOVED_FMT)), [UnitName, TPath.GetFileName(Dpr),
    IfThen(InDpr, U.Keyword, '-'), IfThen(N > 0, ' + CreateForm', ''),
    IfThen(InDproj, MsgText(SF_USES_DCCREFERENCE_DEL_DPROJ), ''), TPath.GetFileName(APasPath)]);
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
      Todos := Todos + [TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(Dpr), PU.Include))];
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
  M, MPos: TMatch;
  Nombres, Nuevos: TStringList;
  Existentes: TArray<string>;
  Ya: Boolean;
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
      // la clausula se localiza sobre el texto con los comentarios en blanco
      // (mismas posiciones) y se reescribe entera, un nombre por linea
      M := TRegEx.Match(CodigoPascal(Text), '^[ \t]*requires\b\s*(.*?);', [roIgnoreCase, roMultiline, roSingleline]);
      Existentes := [];
      if M.Success then
        for E in M.Groups[1].Value.Split([',']) do
          if E.Trim <> '' then
            Existentes := Existentes + [E.Trim];
      for N in Nombres do
      begin
        Ya := False;
        for E in Existentes do
          if MismoIdentificador(E, N) then
            Ya := True;
        if not Ya then
        begin
          Existentes := Existentes + [N];
          Nuevos.Add(N);
        end;
      end;
      if Nuevos.Count = 0 then
        Exit(MsgFmt(SN_REQUIRES_PRESENT_FMT, [TPath.GetFileName(Dpr)]));
      Clausula := 'requires' + NL + '  ' + string.Join(',' + NL + '  ', Existentes) + ';';
      if M.Success then
        Text := Copy(Text, 1, M.Index - 1) + Clausula + Copy(Text, M.Index + M.Length, MaxInt)
      else
      begin
        MPos := TRegEx.Match(CodigoPascal(Text), '^[ \t]*(contains\b|end\s*\.)', [roIgnoreCase, roMultiline]);
        if not MPos.Success then
          Exit(MsgFmt(SR_UNIT_NO_USES_FMT, [TPath.GetFileName(Dpr)]));
        Text := Copy(Text, 1, MPos.Index - 1) + Clausula + NL + NL + Copy(Text, MPos.Index, MaxInt);
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

{ adduses de delphi_edit (David, 2026-09-23): una unit entra en el uses de
  OTRA unit, en la seccion que se diga, y la clausula la escribe el motor:
  comas, terminador y, si no existia, la clausula entera bajo la palabra de
  seccion. Es el espejo de add-unit para el .dpr: alli membresia de
  proyecto, aqui una dependencia entre units. Idempotente. Un solo escritor
  del formato: FindUses/ReplaceUses, los mismos del .dpr y el .dpk. }
function AddUsesToUnit(const APasPath: string; const ANames: TArray<string>;
  const ASection: string): string;
var
  Text, Enc, Sec, OtraSec, NL, Nombre, E, Clausula, Blank: string;
  M, MO: TMatch;
  U, UOtra: TUsesClause;
  Names, Entries, Faltan, YaEstan, EnOtra: TArray<string>;
  PosSec, FinLinea: Integer;
  Creada: Boolean;
begin
  if not SameText(TPath.GetExtension(APasPath), '.pas') then
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
    M := TRegEx.Match(Blank, '^[ \t]*' + Sec + '\b', [roIgnoreCase, roMultiline]);
    if not M.Success then
      Exit(MsgFmt(SR_ADDUSES_NO_SECTION_FMT, [Sec, TPath.GetFileName(APasPath)]));
    PosSec := M.Index + M.Length;
    NL := SaltoDominante(Text);
    U := FindUses(Text, PosSec);
    if U.Found and U.EnRamas then
      Exit(MsgFmt(SR_USES_EN_RAMAS_FMT, [U.Keyword, TPath.GetFileName(APasPath)]));
    Creada := not U.Found;
    Faltan := [];
    YaEstan := [];
    Entries := U.Entries;
    // La OTRA seccion tambien cuenta: una unit no puede ir en interface e
    // implementation a la vez (E2004 Identifier redeclared; Hermes lo midio
    // el 2026-09-23 con UPkgA en las dos).
    OtraSec := IfThen(Sec = 'interface', 'implementation', 'interface');
    UOtra := Default(TUsesClause);
    MO := TRegEx.Match(Blank, '^[ \t]*' + OtraSec + '\b', [roIgnoreCase, roMultiline]);
    if MO.Success then
      UOtra := FindUses(Text, MO.Index + MO.Length);
    EnOtra := [];
    for Nombre in Names do
      if U.Found and LocateEntry(U, Nombre, E) then
        YaEstan := YaEstan + [Nombre]
      else if UOtra.Found and LocateEntry(UOtra, Nombre, E) then
        EnOtra := EnOtra + [Nombre]
      else
      begin
        Faltan := Faltan + [Nombre];
        Entries := Entries + [Nombre];
      end;
    if (Length(Faltan) = 0) and (Length(EnOtra) > 0) then
      Exit(MsgFmt(SN_ADDUSES_PRESENT_OTHER_FMT, [string.Join(', ', EnOtra), OtraSec,
        TPath.GetFileName(APasPath)]));
    if Length(Faltan) = 0 then
      Exit(MsgFmt(SN_ADDUSES_PRESENT_FMT, [string.Join(', ', Names), Sec,
        TPath.GetFileName(APasPath)]));
    if U.Found then
      Text := ReplaceUses(Text, U, Entries)
    else
    begin
      // sin clausula: nace justo debajo de la palabra de seccion, con su
      // linea en blanco, como la escribe el IDE; debajo de donde ACABA esa
      // linea, que un comentario abierto en ella se la llevaba dentro
      // (revision de la 1.10.0, medido)
      FinLinea := FinDeLinea(Text, PosSec);
      Text := Copy(Text, 1, FinLinea - 1) + NL + NL + 'uses' + NL + '  ' +
        string.Join(', ', Faltan) + ';' + Copy(Text, FinLinea, MaxInt);
    end;
    PatchSaveText(APasPath, Text, Enc);
    // el eco, releido del disco: la clausula tal y como ha quedado
    Text := PatchLoadText(APasPath, Enc);
    Blank := CodigoPascal(Text);
    M := TRegEx.Match(Blank, '^[ \t]*' + Sec + '\b', [roIgnoreCase, roMultiline]);
    Clausula := '(?)';
    if M.Success then
    begin
      U := FindUses(Text, M.Index + M.Length);
      if U.Found then
        Clausula := Copy(Text, U.StartPos, U.EndPos - U.StartPos + 1);
    end;
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

{ removeuses: la inversa de adduses. Si la clausula se queda vacia se va
  entera, con el salto de linea que la seguia: un `uses ;` no compila. }
function RemoveUsesFromUnit(const APasPath: string; const ANames: TArray<string>;
  const ASection: string): string;
var
  Text, Enc, Sec, Nombre, E, Clausula, Blank: string;
  M: TMatch;
  U: TUsesClause;
  Names, Entries, Quitadas, NoEstaban: TArray<string>;
  PosSec: Integer;
begin
  if not SameText(TPath.GetExtension(APasPath), '.pas') then
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
    M := TRegEx.Match(Blank, '^[ \t]*' + Sec + '\b', [roIgnoreCase, roMultiline]);
    if not M.Success then
      Exit(MsgFmt(SR_ADDUSES_NO_SECTION_FMT, [Sec, TPath.GetFileName(APasPath)]));
    PosSec := M.Index + M.Length;
    U := FindUses(Text, PosSec);
    if not U.Found then
      Exit(MsgFmt(SN_REMOVEUSES_NO_CLAUSE_FMT, [Sec, TPath.GetFileName(APasPath)]));
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
        TPath.GetFileName(APasPath)]));
    Text := ReplaceUses(Text, U, Entries); // vacia: la clausula entera fuera
    PatchSaveText(APasPath, Text, Enc);
    // el eco, releido del disco
    Text := PatchLoadText(APasPath, Enc);
    Blank := CodigoPascal(Text);
    M := TRegEx.Match(Blank, '^[ \t]*' + Sec + '\b', [roIgnoreCase, roMultiline]);
    Clausula := MsgFmt(SN_REMOVEUSES_GONE_FMT, [Sec]);
    if M.Success then
    begin
      U := FindUses(Text, M.Index + M.Length);
      if U.Found then
        Clausula := Copy(Text, U.StartPos, U.EndPos - U.StartPos + 1);
    end;
    Result := MsgFmt(SN_REMOVEUSES_REMOVED_FMT, [Sec, TPath.GetFileName(APasPath),
      string.Join(', ', Quitadas),
      IfThen(Length(NoEstaban) > 0, MsgFmt(SN_REMOVEUSES_SOME_ABSENT_FMT, [string.Join(', ', NoEstaban)]), ''),
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

function WorkspacePackagesWithUnit(const ADpkPath, AUnitName: string): TArray<string>;
var
  Dirs: TArray<string>;
  D, F: string;
  P: TProjectUnit;
begin
  Result := [];
  Dirs := [];
  SubeCarpetas(TPath.GetDirectoryName(TPath.GetFullPath(ADpkPath)), Dirs);
  // Dos paquetes de un mismo trabajo viven en carpetas HERMANAS (pkgA\ y
  // pkgB\), no una encima de otra: a cada nivel de la subida se miran
  // tambien sus subcarpetas inmediatas. Un listado por carpeta, sin recursion.
  var Sitios: TArray<string> := [];
  for D in Dirs do
  begin
    if not TDirectory.Exists(D) then
      Continue;
    Sitios := Sitios + [D];
    try
      for var Sub in TDirectory.GetDirectories(D) do
        if not MatchText(Sub, Dirs) then
          Sitios := Sitios + [Sub];
    except
      // una carpeta que no se deja listar no es motivo para no mirar el resto
    end;
  end;
  for D in Sitios do
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

function ProjectsUsingUnit(const APasPath: string; const AAlsoDir: string): TArray<string>;
var
  Dir, D, F, Stem: string;
  Dirs: TArray<string>;
  P: TProjectUnit;
begin
  Result := [];
  // el nombre de la unit sale del nombre LARGO: el de UPROVE~1.PAS no es UPROVE~1
  Stem := TPath.GetFileNameWithoutExtension(LongCanonical(APasPath));
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
  for D in Dirs do
  begin
    if not TDirectory.Exists(D) then
      Continue;
    for F in TDirectory.GetFiles(D, '*.dp?') do // .dpr y .dpk, no .dproj
      if MatchText(TPath.GetExtension(F), ['.dpr', '.dpk']) then
      for P in UnitsParaBuscar(F, Stem) do // the .dpr decides; no .dproj read
        if MismoIdentificador(P.UnitName, Stem) and
          (NormPath(TPath.Combine(TPath.GetDirectoryName(F), P.Include)) = NormPath(APasPath)) then
        begin
          Result := Result + [F];
          Break;
        end;
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
  Vistas := SplitToLinesConSalto(CodigoPascal(Texto), SaltosVista);
  for I := 0 to High(Lineas) do
  begin
    Linea := Lineas[I];
    if Vistas[I].TrimLeft.StartsWith('unit ', True) then
      Continue;
    Partes := TStringBuilder.Create;
    try
      Ultimo := 0; // 0-based: hasta donde se ha copiado ya la linea
      for M in Re.Matches(Vistas[I]) do
      begin
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
  G, Tok: string;
  P, Q, Maximo: Integer;
  Comilla: Char;
begin
  Result := [];
  // por el lector UNICO de directivas: una comentada (tambien con //) o
  // dentro de una cadena ya no cuenta, y la forma parentesis-asterisco si
  for var X in DirectivasPascal(ATexto) do
  begin
    if not MatchText(X.Nombre, ['I', 'INCLUDE', 'R', 'RESOURCE', 'L', 'LINK']) then
      Continue;
    G := X.Argumento;
    // {$R a.res a.rc}: el .rc del que sale el .res es la SEGUNDA ruta de la
    // misma directiva, y tambien es un fichero (revision 26-sep-2026)
    Maximo := 1;
    if MatchText(X.Nombre, ['R', 'RESOURCE']) then
      Maximo := 2;
    P := 1;
    for var N := 1 to Maximo do
    begin
      while (P <= Length(G)) and CharInSet(G[P], [' ', #9, #13, #10]) do
        Inc(P);
      if P > Length(G) then
        Break;
      Comilla := #0;
      if CharInSet(G[P], ['''', '"']) then
      begin
        Comilla := G[P];
        Inc(P);
        Q := P;
        while (Q <= Length(G)) and (G[Q] <> Comilla) do
          Inc(Q);
      end
      else
      begin
        Q := P;
        while (Q <= Length(G)) and not CharInSet(G[Q], [' ', #9, #13, #10]) do
          Inc(Q);
      end;
      Tok := Copy(G, P, Q - P);
      // Un comodin es el andamiaje del IDE ({$R *.res}, {$R *.dfm}); un
      // caracter suelto, un interruptor ({$I +}), no un fichero.
      if not ((Tok = '') or Tok.Contains('*') or
         ((Comilla = #0) and ((Length(Tok) <= 1) or CharInSet(Tok[1], ['+', '-'])))) then
      begin
        D.Texto := Copy(ATexto, X.Inicio, X.Largo);
        D.Ruta := Tok;
        D.Comilla := Comilla;
        D.Inicio := X.InicioArg + P - 1;
        D.Largo := Length(Tok);
        Result := Result + [D];
      end;
      P := Q;
      if Comilla <> #0 then
        Inc(P);
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
  por RutaReapuntada: solo se reescriben los trozos que cambian (XmlEscape del
  nuevo) y el resto queda byte a byte. '' si no cambia ninguno; ACuenta suma
  los que cambian. }
function ListaReapuntada(const AEscrito, ABaseVieja, AFichero: string;
  const AMapa: TFunc<string, string>; var ACuenta: Integer): string;
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
      Partes[I] := XmlEscape(R);
      Cambiado := True;
      Inc(ACuenta);
    end;
  end;
  if Cambiado then
    Result := string.Join(';', Partes);
end;

{ EL esqueleto de las reescrituras de XML de la mudanza: en AFichero, el
  grupo 1 de cada patron es una lista escrita de rutas relativas a AFichero,
  y se re-apuntan las que cruzan el borde; se guarda UNA vez. Era el mismo
  bucle en el .dproj y en el grupo (revision 26-sep-2026). Devuelve cuantas
  rutas cambio. }
function ReapuntaPatrones(const AFichero, ABaseVieja: string;
  const APatrones: TArray<string>; const AMapa: TFunc<string, string>): Integer;
var
  Enc, Texto: string;
  Cambios: TArray<TCambioTexto>;
begin
  Result := 0;
  Texto := PatchLoadText(AFichero, Enc);
  Cambios := [];
  for var Patron in APatrones do
    for var M in TRegEx.Matches(Texto, Patron, [roIgnoreCase]) do
    begin
      var Nueva := ListaReapuntada(M.Groups[1].Value, ABaseVieja, AFichero, AMapa, Result);
      if Nueva <> '' then
      begin
        var C: TCambioTexto;
        C.Inicio := M.Groups[1].Index;
        C.Largo := M.Groups[1].Length;
        C.Texto := Nueva;
        Cambios := Cambios + [C];
      end;
    end;
  if Result > 0 then
    PatchSaveText(AFichero, AplicaCambios(Texto, Cambios), Enc);
end;

{ Los sitios de un .dproj que son RUTAS: las listas de busqueda y las de
  salida (BUILD_OUTPUT_TAGS: la misma lista que la puerta del build), el
  icono, el manifiesto, los .rc que compila, los ficheros que despliega y
  los .optset que importa (David, 26-sep-2026: que "sigue compilando" sea
  verdad tambien con recursos e iconos). }
function PatronesDeDproj: TArray<string>;
begin
  Result := [];
  for var E in TArray<string>.Create('DCC_UnitSearchPath', 'DCC_IncludePath',
    'DCC_ResourcePath', 'DCC_ObjPath', 'Icon_MainIcon', 'Manifest_File',
    'CfgDependentOn') do
    Result := Result + ['<' + E + '(?:\s[^>]*)?>([^<]*)</' + E + '>'];
  for var E in BUILD_OUTPUT_TAGS do
    Result := Result + ['<' + E + '(?:\s[^>]*)?>([^<]*)</' + E + '>'];
  Result := Result + ['<RcCompile\s+Include="([^"]*)"', '<RcItem\s+Include="([^"]*)"',
    '<DeployFile\s+LocalName="([^"]*)"', '<Import\s[^>]*?\bProject="([^"]*\.optset)"',
    'Exists\(''([^'']*\.optset)''\)'];
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
  Result := ReapuntaPatrones(AGroup, ABaseVieja, ['<Projects\s+Include="([^"]*)"',
    '<MSBuild\s+Projects="([^"]*)"', '<Dependencies>([^<]*)</Dependencies>'], AMapa);
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
      // La ruta VIEJA de verdad: RenameProjectUnit busca en el .dpr por el
      // nombre que sale de ella, y en un rename no es el nuevo. Se pasaba la
      // nueva dos veces: el rename no encontraba nada y se contaba como hecho
      // (revision 26-sep-2026). Solo cuenta lo que dice REAPUNTADA.
      var Viejo := TPath.GetFullPath(TPath.Combine(ABaseVieja, PU.Include));
      var Resp := RenameProjectUnit(AProyecto, Viejo, Nuevo);
      if Reapuntada(Resp) then
        Inc(Result)
      else
        AFallos := AFallos + [TPath.GetFileName(AProyecto) + ': ' + Resp.Split([#10])[0]];
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

function ReubicaArbol(const AViejo, ANuevo: string; ACopia: Boolean): string;
var
  Viejo, Nuevo: string;
  NUnits, NRutas, NDirect, NGrupos, NFuera: Integer;
  Tocados, Fallos, Saltadas: TArray<string>;
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
    Ext: string;
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
      try
        Anota(AFichero, ReapuntaPatrones(AFichero, ABase, PatronesDeDproj, AMapa), ARutas);
      except
        on E: Exception do
          Falla(AFichero, E);
      end;
    if Ext = '.deployproj' then
      try
        Anota(AFichero, ReapuntaPatrones(AFichero, ABase,
          ['<DeployFile\s+Include="([^"]*)"'], AMapa), ARutas);
      except
        on E: Exception do
          Falla(AFichero, E);
      end;
    if MatchText(Ext, ['.dpr', '.dpk', '.pas', '.inc']) then
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

{ El .dproj de lo que nombra el agente (el .dproj, o su .dpr/.dpk al lado). }
function DprojDe(const AProject: string): string;
begin
  Result := TPath.GetFullPath(AProject);
  if MatchText(TPath.GetExtension(Result), ['.dpr', '.dpk']) then
    Result := TPath.ChangeExtension(Result, '.dproj');
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
  M: TMatch;
  P: Integer;

  { Donde entra lo que el grupo no tiene: delante de su Import, o de su
    cierre, como lo pone el IDE. 0 si el fichero no tiene forma de grupo.
    Estaba escrito dos veces. }
  function AlFinal: Integer;
  var
    MI: TMatch;
  begin
    MI := TRegEx.Match(Texto, '[ \t]*<Import\s');
    if MI.Success then
      Result := MI.Index
    else
      Result := Pos('</Project>', Texto);
  end;

begin
  Proj := DprojDe(AProject);
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
  if TRegEx.IsMatch(Texto, '<Target\s+Name="' + TRegEx.Escape(XmlEscape(Nombre)) + '"', [roIgnoreCase]) then
    Exit(MsgFmt(SR_GRUPO_TARGET_DUP_FMT, [Nombre, TPath.GetFileName(AGroup)]));
  Incl := IncludeFor(AGroup, Proj);
  // 1. el item, detras del ultimo <Projects> (o en un ItemGroup nuevo)
  var Item := '        <Projects ' + XmlAtributo('Include', Incl) + '>' + NL +
    '            <Dependencies/>' + NL + '        </Projects>' + NL;
  M := TRegEx.Match(Texto, '</Projects>[ \t]*\r?\n', [roIgnoreCase]);
  var Ultimo := -1;
  while M.Success do
  begin
    Ultimo := M.Index + M.Length;
    M := M.NextMatch;
  end;
  if Ultimo > 0 then
    Insert(Item, Texto, Ultimo)
  else
  begin
    P := Pos('</PropertyGroup>', Texto);
    if P = 0 then
      Exit(MsgFmt(SR_GRUPO_FORMA_FMT, [TPath.GetFileName(AGroup), MsgText(SF_GRUPO_SIN_SITIO_PROYECTO)]));
    P := P + Length('</PropertyGroup>');
    Insert(NL + '    <ItemGroup>' + NL + Item + '    </ItemGroup>', Texto, P);
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
  M := TRegEx.Match(Texto, '[ \t]*<Target\s+Name="Build"');
  if M.Success then
    P := M.Index
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
    M := TRegEx.Match(Texto, '(<Target\s+Name="' + Agregado + '"[^>]*>\s*<CallTarget\s+Targets=")([^"]*)(")');
    if M.Success then
    begin
      var Lista := M.Groups[2].Value;
      if Lista <> '' then
        Lista := Lista + ';';
      Texto := Copy(Texto, 1, M.Groups[2].Index - 1) + Lista + XmlEscape(Nombre + Suf) +
        Copy(Texto, M.Groups[2].Index + M.Groups[2].Length, MaxInt);
    end
    else if TRegEx.IsMatch(Texto, '<Target\s+Name="' + Agregado + '"') then
      SinAgregado := SinAgregado + [Agregado]
    else
    begin
      P := AlFinal;
      if P = 0 then
        Exit(MsgFmt(SR_GRUPO_FORMA_FMT, [TPath.GetFileName(AGroup), MsgText(SF_GRUPO_SIN_FINAL)]));
      Insert('    <Target Name="' + Agregado + '">' + NL + '        <CallTarget ' +
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
  M: TMatch;
  NDeps: Integer;

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

begin
  Proj := DprojDe(AProject);
  Texto := PatchLoadText(AGroup, Enc);
  Cambios := [];
  // 1. el item <Projects> (con su linea)
  for M in TRegEx.Matches(Texto,
    '[ \t]*<Projects\s+Include="([^"]*)"\s*(/>|>.*?</Projects>)[ \t]*\r?\n?', [roSingleLine]) do
    if MismoProyecto(AGroup, XmlUnescape(M.Groups[1].Value), Proj) then
      Cambia(M.Index, M.Length, '');
  if Length(Cambios) = 0 then
    Exit(MsgFmt(SN_GRUPO_NO_ESTABA_FMT, [TPath.GetFileName(Proj), TPath.GetFileName(AGroup)]));
  // 2. sus targets -los que construyen ESE proyecto, con o sin
  //    DependsOnTargets: el IDE lo escribe en los que dependen de otro, y la
  //    regex lo exigia sin nada-, y se apuntan sus nombres
  Nombres := [];
  for M in TRegEx.Matches(Texto,
    '[ \t]*<Target\s+Name="([^"]*)"[^>]*>\s*<MSBuild\s+Projects="([^"]*)"[^>]*/>\s*</Target>[ \t]*\r?\n?') do
    if MismoProyecto(AGroup, XmlUnescape(M.Groups[2].Value), Proj) then
    begin
      Cambia(M.Index, M.Length, '');
      Nombres := Nombres + [XmlUnescape(M.Groups[1].Value)];
    end;
  // 3. esos nombres fuera de las listas de targets: los CallTarget de los
  //    agregados y el DependsOnTargets de los que dependian de el (si se
  //    queda, msbuild falla: el target no existe)
  for M in TRegEx.Matches(Texto, '(\s+DependsOnTargets|<CallTarget\s+Targets)="([^"]*)"') do
  begin
    if Borrado(M.Index) then
      Continue;
    var Quedan: TArray<string> := [];
    var Quitados := 0;
    for var N in TrozosEscritos(M.Groups[2].Value) do
      if N.Trim = '' then
        Continue
      else if MatchText(XmlUnescape(N.Trim), Nombres) then
        Inc(Quitados)
      else
        Quedan := Quedan + [N.Trim];
    if Quitados = 0 then
      Continue;
    if (Length(Quedan) = 0) and not M.Groups[1].Value.Contains('CallTarget') then
      Cambia(M.Index, M.Length, '') // sin dependencias: fuera el atributo entero
    else
      Cambia(M.Groups[2].Index, M.Groups[2].Length, string.Join(';', Quedan));
  end;
  // 4. y su ruta fuera de las <Dependencies> de los demas proyectos
  NDeps := 0;
  for M in TRegEx.Matches(Texto, '<Dependencies>([^<]*)</Dependencies>') do
  begin
    if Borrado(M.Index) then
      Continue;
    var Quedan: TArray<string> := [];
    var Quitados := 0;
    for var D in TrozosEscritos(M.Groups[1].Value) do
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
      Cambia(M.Index, M.Length, '<Dependencies/>')
    else
      Cambia(M.Groups[1].Index, M.Groups[1].Length, string.Join(';', Quedan));
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
          Fallidas := Fallidas + [PU.Include + ': ' + Resp.Split([#10])[0]];
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
