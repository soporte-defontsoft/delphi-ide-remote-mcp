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

// The Pascal text with every comment (brace, paren-star, slash-slash) and
// compiler directive replaced by spaces - same length, same line breaks, so
// positions and line numbers survive. String literals are left intact. For
// scanners that must not read commented-out code (field 2026-08-23: a
// StyleLookup mentioned in a comment became a lint "finding").
function BlankComments(const S: string): string;

type
  // Una directiva de compilacion DE VERDAD de un texto Pascal, en sus dos
  // formas (llave-dolar y parentesis-asterisco-dolar): nunca la que va dentro
  // de un comentario (llaves, parentesis-asterisco o //) ni de una cadena.
  TDirectivaPascal = record
    Nombre: string;         // en mayusculas: I, INCLUDE, IFDEF, APPTYPE...
    Argumento: string;      // lo que va detras del nombre, tal cual
    Inicio, Largo: Integer; // la directiva entera en el texto (1-based)
    InicioArg: Integer;     // donde empieza Argumento en el texto
  end;

// LAS directivas reales de ATexto, en orden: el UNICO lector de directivas
// (las de fichero I/R/L de la mudanza y de la puerta del build, los
// condicionales de un uses partido en ramas, el detector de tests). Con el
// mismo lexico que el resto (CommentLen/QuoteLen): cuatro lectores con su
// regex sobre el texto crudo veian una directiva COMENTADA -tambien con //- o
// dentro de una cadena, y no la forma parentesis-asterisco (revision del
// 27-sep-2026, David: "incluso //").
function DirectivasPascal(const ATexto: string): TArray<TDirectivaPascal>;

// Las lineas (1-based) de ATexto donde empieza un comentario de LLAVE que
// lleva otra llave abierta dentro. Pascal no anida llaves: el primer cierre
// acaba el comentario y lo que sigue es codigo, o una directiva de verdad
// si citaba una de llave-dolar (la trampa en la que se cayo cuatro veces
// entre el 25 y el 27-sep-2026). Solo lo mira; quien lo usa decide.
function LlavesAnidadas(const ATexto: string): TArray<Integer>;

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
  Lsp.References;  // SkipIdeArtifacts: una mudanza no entra en artefactos

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
  Result := TPath.GetFullPath(P).Replace('/', '\').ToLower;
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
  Enc, Line: string;
  Lines: TArray<string>;
  M: TMatch;
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
    Lines := Enc.Replace(#13#10, #10).Split([#10]);
  end
  else
    Lines := PatchLoadText(ADesigner, Enc).Replace(#13#10, #10).Split([#10]);
  for Line in Lines do
  begin
    M := TRegEx.Match(Line, '^\s*(object|inherited)\s+(\w+)\s*:\s*(\w+)', [roIgnoreCase]);
    if M.Success then
    begin
      AName := M.Groups[2].Value;
      AClass := M.Groups[3].Value;
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
  DesignClass on a data module only changes the IDE's icon). }
function DesignClassOf(const ASrc, AAncestor: string): string;
var
  Name: string;
  M: TMatch;
  Hops: Integer;
begin
  Result := '';
  Name := AAncestor;
  Hops := 0;
  while (Name <> '') and (Hops < 8) do
  begin
    if Name.Contains('.') then
      Name := Name.Substring(Name.LastIndexOf('.') + 1);
    if SameText(Name, 'TFrame') or SameText(Name, 'TCustomFrame') then
      Exit('TFrame');
    if SameText(Name, 'TDataModule') then
      Exit('TDataModule');
    if SameText(Name, 'TForm') or SameText(Name, 'TCustomForm') or SameText(Name, 'TForm3D') then
      Exit('');
    // declared in this unit? follow its ancestor
    M := TRegEx.Match(ASrc, '\b' + TRegEx.Escape(Name) + '\s*=\s*class\s*\(\s*([\w.]+)', [roIgnoreCase]);
    if not M.Success then
      Break;
    Name := M.Groups[1].Value;
    Inc(Hops);
  end;
  if Name.EndsWith('Frame', True) then
    Result := 'TFrame'
  else if Name.EndsWith('DataModule', True) then
    Result := 'TDataModule';
end;

function InspectUnit(const APasPath: string; out AInfo: TUnitInfo): string;
var
  Enc, Src, Stem, DName, DClass: string;
  M: TMatch;
begin
  Result := '';
  AInfo := Default(TUnitInfo);
  if not TFile.Exists(APasPath) then
    Exit(NoEsFichero(APasPath, MsgFmt(SR_UNIT_PAS_MISSING_FMT, [APasPath])));
  if TPath.GetExtension(APasPath).ToLower <> '.pas' then
    Exit(MsgFmt(SR_UNIT_NOT_PAS_FMT, [TPath.GetFileName(APasPath)]));
  AInfo.PasPath := TPath.GetFullPath(APasPath);
  Src := PatchLoadText(AInfo.PasPath, Enc);
  M := TRegEx.Match(Src, '^\s*unit\s+([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*;', [roIgnoreCase, roMultiline]);
  if not M.Success then
  begin
    // Hay cabecera, pero con letras fuera de A-Z/0-9/_ (acentos): dcc la
    // compila (medido 2026-09-23 con RAD Studio 13) y este servidor aun no
    // la maneja. Decir "no tiene cabecera" era falso y mandaba al agente a
    // buscar un fallo que no existia (Hermes, bateria 1.2).
    M := TRegEx.Match(Src, '^\s*unit\s+([^\s;]+)\s*;', [roIgnoreCase, roMultiline]);
    if M.Success then
      Exit(MsgFmt(SR_UNIT_HEADER_NONASCII_FMT, [TPath.GetFileName(APasPath), M.Groups[1].Value]));
    Exit(MsgFmt(SR_UNIT_NO_HEADER_FMT, [TPath.GetFileName(APasPath)]));
  end;
  AInfo.UnitName := M.Groups[1].Value;
  Stem := TPath.GetFileNameWithoutExtension(AInfo.PasPath);
  if not SameText(Stem, AInfo.UnitName) then
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

  // the designer's root object names the form; the .pas gives the ancestor
  if DesignerHeaderName(AInfo.Designer, DName, DClass) then
  begin
    AInfo.FormName := DName;
    AInfo.ClassName := DClass;
    M := TRegEx.Match(Src, '\b' + TRegEx.Escape(DClass) + '\s*=\s*class\s*\(\s*([\w.]+)', [roIgnoreCase]);
  end
  else
  begin
    // binary designer: the first designer class in the .pas, then its variable
    M := TRegEx.Match(Src, '\b(T\w+)\s*=\s*class\s*\(\s*((?:\w+\.)*T(?:Form|DataModule|Frame)\w*)', [roIgnoreCase]);
    if M.Success then
    begin
      AInfo.ClassName := M.Groups[1].Value;
      var V := TRegEx.Match(Src, '^\s*(\w+)\s*:\s*' + TRegEx.Escape(AInfo.ClassName) + '\s*;',
        [roIgnoreCase, roMultiline]);
      if V.Success then
        AInfo.FormName := V.Groups[1].Value;
    end;
  end;
  if M.Success then
    AInfo.Ancestor := M.Groups[M.Groups.Count - 1].Value;
  AInfo.DesignClass := DesignClassOf(Src, AInfo.Ancestor);
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

// Length of the comment or directive starting at S[I] (0 when none): the
// slash-slash line comment, the paren-star block and the brace block
// (compiler directives included - the compiler treats them as comments
// inside a uses clause).
function CommentLen(const S: string; I: Integer): Integer;
var
  J: Integer;
begin
  Result := 0;
  if I > Length(S) then
    Exit;
  if (S[I] = '/') and (I < Length(S)) and (S[I + 1] = '/') then
  begin
    J := I;
    while (J <= Length(S)) and (S[J] <> #10) and (S[J] <> #13) do
      Inc(J);
    Exit(J - I);
  end;
  if (S[I] = '(') and (I < Length(S)) and (S[I + 1] = '*') then
  begin
    J := Pos('*)', S, I + 2);
    if J = 0 then
      Exit(Length(S) - I + 1);
    Exit(J + 2 - I);
  end;
  if S[I] = '{' then
  begin
    J := Pos('}', S, I + 1);
    if J = 0 then
      Exit(Length(S) - I + 1);
    Exit(J + 1 - I);
  end;
end;

{ Length of the quoted string starting at S[I] ('' escapes), 0 when none. }
function QuoteLen(const S: string; I: Integer): Integer;
var
  J: Integer;
begin
  Result := 0;
  if (I > Length(S)) or (S[I] <> '''') then
    Exit;
  J := I + 1;
  while J <= Length(S) do
  begin
    if S[J] = '''' then
    begin
      if (J < Length(S)) and (S[J + 1] = '''') then
        Inc(J, 2)
      else
        Exit(J + 1 - I);
    end
    else
      Inc(J);
  end;
  Result := Length(S) - I + 1;
end;

function BlankComments(const S: string): string;
var
  I, N, K: Integer;
  Sb: TStringBuilder;
begin
  Sb := TStringBuilder.Create(Length(S));
  try
    I := 1;
    while I <= Length(S) do
    begin
      N := QuoteLen(S, I);
      if N > 0 then
      begin
        Sb.Append(S, I - 1, N);
        Inc(I, N);
        Continue;
      end;
      N := CommentLen(S, I);
      if N > 0 then
      begin
        for K := I to I + N - 1 do
          if CharInSet(S[K], [#10, #13]) then
            Sb.Append(S[K])
          else
            Sb.Append(' ');
        Inc(I, N);
        Continue;
      end;
      Sb.Append(S[I]);
      Inc(I);
    end;
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

function DirectivasPascal(const ATexto: string): TArray<TDirectivaPascal>;
var
  I, N, P, Q, Fin: Integer;
  D: TDirectivaPascal;
begin
  Result := [];
  I := 1;
  while I <= Length(ATexto) do
  begin
    N := QuoteLen(ATexto, I);
    if N > 0 then
    begin
      Inc(I, N); // una cadena: nada de dentro es una directiva
      Continue;
    end;
    N := CommentLen(ATexto, I);
    if N = 0 then
    begin
      Inc(I);
      Continue;
    end;
    // un comentario de llave o de parentesis-asterisco que empieza por $ es
    // una directiva; uno de // nunca lo es, y lo de dentro de un comentario
    // tampoco
    P := 0;
    if (ATexto[I] = '{') and (I < Length(ATexto)) and (ATexto[I + 1] = '$') then
      P := I + 2
    else if (ATexto[I] = '(') and (I + 2 <= Length(ATexto)) and (ATexto[I + 2] = '$') then
      P := I + 3;
    if P > 0 then
    begin
      Q := P;
      while (Q <= Length(ATexto)) and
            CharInSet(ATexto[Q], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
        Inc(Q);
      // el contenido acaba antes del cierre: la llave, o el '*' de '*)'
      Fin := I + N - 1;
      if (ATexto[I] = '(') and (Fin > I) and (ATexto[Fin] = ')') then
        Dec(Fin)
      else if (ATexto[I] = '{') and (ATexto[Fin] <> '}') then
        Inc(Fin); // sin cerrar: hasta el final
      D.Nombre := UpperCase(Copy(ATexto, P, Q - P));
      D.InicioArg := Q;
      D.Argumento := Copy(ATexto, Q, Fin - Q);
      D.Inicio := I;
      D.Largo := N;
      Result := Result + [D];
    end;
    Inc(I, N);
  end;
end;

function LlavesAnidadas(const ATexto: string): TArray<Integer>;
var
  I, N, Dentro, Linea: Integer;
begin
  Result := [];
  I := 1;
  while I <= Length(ATexto) do
  begin
    N := QuoteLen(ATexto, I);
    if N = 0 then
      N := CommentLen(ATexto, I);
    if N = 0 then
    begin
      Inc(I);
      Continue;
    end;
    if ATexto[I] = '{' then
    begin
      // otra llave abierta ANTES del cierre de esta
      Dentro := Pos('{', ATexto, I + 1);
      if (Dentro > 0) and (Dentro < I + N - 1) then
      begin
        Linea := 1;
        for var K := 1 to I - 1 do
          if ATexto[K] = #10 then
            Inc(Linea);
        Result := Result + [Linea];
      end;
    end;
    Inc(I, N);
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

function IsIdentChar(C: Char): Boolean;
begin
  Result := C.IsLetterOrDigit or (C = '_');
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
    M := TRegEx.Match(Dpr, '^\s*(program|library|package)\b', [roIgnoreCase, roMultiline]);
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
      if ((I = 1) or not IsIdentChar(Dpr[I - 1])) and (I + K - 1 <= Length(Dpr)) and
         SameText(Copy(Dpr, I, K), Result.Keyword) and
         ((I + K > Length(Dpr)) or not IsIdentChar(Dpr[I + K])) then
      begin
        Start := I;
        Inc(I, K);
        Continue;
      end;
      if IsIdentChar(Dpr[I]) then
      begin
        // another token before the clause (const, type, begin...): no clause.
        // Except `requires ...;` in a package, which comes BEFORE contains
        // and is skipped whole.
        Token := '';
        while (I <= Length(Dpr)) and IsIdentChar(Dpr[I]) do
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
  M := TRegEx.Match(Core, '^([A-Za-z_][\w.]*)');
  if M.Success then
    Result := M.Groups[1].Value
  else
    Result := Core;
end;

function EntryInclude(const Entry: string): string;
var
  M: TMatch;
begin
  M := TRegEx.Match(Entry, '^\s*[A-Za-z_][\w.]*\s+in\s*''([^'']+)''', [roIgnoreCase]);
  if not M.Success then
  begin
    var Prefix, Core: string;
    SplitEntryPrefix(Entry, Prefix, Core);
    M := TRegEx.Match(Core, '^[A-Za-z_][\w.]*\s+in\s*''([^'']+)''', [roIgnoreCase]);
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
  M := TRegEx.Match(Core, '''\s*\{\s*(\w+)');
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

{ Rewrites the clause with AEntries, keeping the text before/after intact.
  Entries go one per line with the indent the clause already used (the IDE's
  two spaces when it had none). Measured 2026-08-23: the indent was applied
  TWICE (join + a second replace) and every add/remove-unit re-indented the
  whole clause to four spaces - a 40-line cosmetic diff on a real project. }
{ Donde empieza el comentario // de una linea (1-based), fuera de comillas;
  0 si no tiene. }
function ComentarioDeLinea(const ALinea: string): Integer;
var
  EnCadena: Boolean;
begin
  EnCadena := False;
  for var I := 1 to Length(ALinea) - 1 do
    if ALinea[I] = '''' then
      EnCadena := not EnCadena
    else if not EnCadena and (ALinea[I] = '/') and (ALinea[I + 1] = '/') then
      Exit(I);
  Result := 0;
end;

function ReplaceUses(const Dpr: string; const U: TUsesClause; const AEntries: TArray<string>): string;
var
  Body, NL, Indent, Clause, E: string;
  M: TMatch;
  Parts: TArray<string>;
  I: Integer;
begin
  // EL escritor pregunta el mismo, como AtomicWrite: una clausula partida en
  // ramas no se reescribe - la unit caeria en la rama que no toca, o la
  // clausula perderia su forma. Los llamadores lo dicen antes, con el fichero.
  if U.EnRamas then
    raise Exception.Create(MsgFmt(SR_USES_EN_RAMAS_FMT, [U.Keyword, MsgText(SF_USES_EL_FICHERO)]));
  NL := IfThen(Dpr.Contains(#13#10), #13#10, #10);
  // the indent of the first entry line of the existing clause
  Clause := Copy(Dpr, U.StartPos, U.EndPos - U.StartPos + 1);
  M := TRegEx.Match(Clause, '\n([ \t]+)\S');
  if M.Success then
    Indent := M.Groups[1].Value
  else
    Indent := '  ';
  SetLength(Parts, Length(AEntries));
  // un // que va detras de la coma es de la entrada de ANTES (esta en su
  // misma linea), aunque el troceo por comas lo deje al principio de la
  // siguiente: se le devuelve a su dueno, y el separador (la coma o el ;)
  // va DELANTE de el. Si no, quitar la ultima entrada dejaba el ; dentro
  // del comentario y la clausula sin cerrar, y cada reescritura bajaba el
  // comentario a una linea suya (medido 27-sep con removeuses).
  var Entradas := Copy(AEntries);
  var Colas: TArray<string>;
  SetLength(Colas, Length(Entradas));
  for I := 1 to High(Entradas) do
  begin
    var Texto := Entradas[I].Replace(#13#10, #10);
    var P := Texto.IndexOf(#10);
    var Primera := IfThen(P >= 0, Copy(Texto, 1, P), '').Trim;
    // solo si en el original iba detras de SU coma: uno que estaba en una
    // linea suya no sube; y con el hueco que tenia (las entradas llegan
    // recortadas: el hueco sale del texto original de la clausula)
    var MC := TRegEx.Match(Clause, ',([ \t]*)' + TRegEx.Escape(Primera));
    if Primera.StartsWith('//') and MC.Success then
    begin
      Colas[I - 1] := IfThen(MC.Groups[1].Value <> '', MC.Groups[1].Value, ' ') + Primera;
      Entradas[I] := Copy(Texto, P + 2, MaxInt);
    end;
  end;
  for I := 0 to High(Entradas) do
  begin
    // a multi-line entry (directives around it) keeps its lines indented too:
    // cada linea se reindenta desde cero, que la que venia con su sangria
    // propia (la vecina de una entrada quitada) salia con las dos (medido
    // en vivo con removeuses, 2026-09-23)
    var Lineas := Entradas[I].Replace(#13#10, #10).Split([#10]);
    for var J := 0 to High(Lineas) do
      Lineas[J] := Lineas[J].Trim;
    // el separador, detras de la ultima linea con codigo y delante de su //
    var K := High(Lineas);
    while (K > 0) and Lineas[K].StartsWith('//') do
      Dec(K);
    var Sep := IfThen(I < High(Entradas), ',', ';');
    var C := ComentarioDeLinea(Lineas[K]);
    if C > 0 then
    begin
      var Codigo := Copy(Lineas[K], 1, C - 1);
      var Hueco := Copy(Codigo, Length(Codigo.TrimRight) + 1, MaxInt);
      if Hueco = '' then
      begin
        // el que tenia en el original, detras de su separador
        var MH := TRegEx.Match(Clause, '[,;]([ \t]*)' + TRegEx.Escape(Copy(Lineas[K], C, MaxInt)));
        Hueco := IfThen(MH.Success and (MH.Groups[1].Value <> ''), MH.Groups[1].Value, ' ');
      end;
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
  Result := Copy(Dpr, 1, U.StartPos - 1) + Body + Copy(Dpr, U.EndPos + 1, MaxInt);
end;

function CreateFormLine(const AInfo: TUnitInfo): string;
begin
  Result := 'Application.CreateForm(' + AInfo.ClassName + ', ' + AInfo.FormName + ');';
end;

{ Inserts the CreateForm after the last existing CreateForm, else right
  before Application.Run. Returns False when neither anchor exists. }
function InsertCreateForm(var Dpr: string; const AInfo: TUnitInfo): Boolean;
var
  Lines: TArray<string>;
  I, Last, RunAt: Integer;
  NL, Indent: string;
  L: TStringList;
begin
  Result := False;
  if TRegEx.IsMatch(Dpr, '\bCreateForm\s*\(\s*' + TRegEx.Escape(AInfo.ClassName) + '\s*,', [roIgnoreCase]) then
    Exit(True); // already there
  NL := IfThen(Dpr.Contains(#13#10), #13#10, #10);
  Lines := Dpr.Replace(#13#10, #10).Split([#10]);
  Last := -1;
  RunAt := -1;
  for I := 0 to High(Lines) do
  begin
    if TRegEx.IsMatch(Lines[I], '^\s*Application\.CreateForm\s*\(', [roIgnoreCase]) then
      Last := I;
    if (RunAt = -1) and TRegEx.IsMatch(Lines[I], '^\s*Application\.Run\b', [roIgnoreCase]) then
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
      Indent := Copy(Lines[RunAt], 1, Length(Lines[RunAt]) - Length(Lines[RunAt].TrimLeft));
      L.Insert(RunAt, Indent + CreateFormLine(AInfo));
    end
    else
    begin
      Indent := Copy(Lines[Last], 1, Length(Lines[Last]) - Length(Lines[Last].TrimLeft));
      L.Insert(Last + 1, Indent + CreateFormLine(AInfo));
    end;
    Dpr := string.Join(NL, L.ToStringArray);
  finally
    L.Free;
  end;
  Result := True;
end;

{ Drops every Application.CreateForm line naming AClass or AVar. }
function RemoveCreateForm(var Dpr: string; const AClassName, AFormName: string): Integer;
var
  Lines: TArray<string>;
  I: Integer;
  NL: string;
  L: TStringList;
  Pat: string;
begin
  Result := 0;
  NL := IfThen(Dpr.Contains(#13#10), #13#10, #10);
  Lines := Dpr.Replace(#13#10, #10).Split([#10]);
  if AClassName <> '' then
    Pat := '^\s*Application\.CreateForm\s*\(\s*' + TRegEx.Escape(AClassName) + '\s*,'
  else if AFormName <> '' then
    Pat := '^\s*Application\.CreateForm\s*\(\s*\w+\s*,\s*' + TRegEx.Escape(AFormName) + '\s*\)'
  else
    Exit;
  L := TStringList.Create;
  try
    for I := 0 to High(Lines) do
      if TRegEx.IsMatch(Lines[I], Pat, [roIgnoreCase]) then
        Inc(Result)
      else
        L.Add(Lines[I]);
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
  Dpr, Dproj, Enc, Text, Include, Entry, Note, Prefix, Core: string;
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
      var MEnd := TRegEx.Match(Text, '(?im)^\s*end\s*\.');
      if not MEnd.Success then
        Exit(MsgFmt(SR_UNIT_NO_USES_FMT, [TPath.GetFileName(Dpr)]));
      var NL := IfThen(Text.Contains(#13#10), #13#10, #10);
      Text := Copy(Text, 1, MEnd.Index - 1) + 'contains' + NL + '  ' +
        BuildEntry(Info, Include) + ';' + NL + NL + Copy(Text, MEnd.Index, MaxInt);
      PatchSaveText(Dpr, Text, Enc);
      Text := PatchLoadText(Dpr, Enc);
      U := FindUses(Text);
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
    if SameText(EntryUnitName(Entries[I]), Info.UnitName) then
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
        SplitEntryPrefix(Entries[I], Prefix, Core);
        Entries[I] := IfThen(Prefix <> '', Prefix + #10, '') + BuildEntry(Info, Include);
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
    PatchSaveText(Dproj, Text, Enc);
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

function AddProjectUnit(const AProject, APasPath: string): string;
begin
  // Registrar una unidad es leer el .dpr, modificarlo y escribirlo: dos
  // agentes creando unidades en el MISMO proyecto a la vez perdian entradas
  // dando exito (medido 2026-09-20, bateria de concurrencia). Con el cerrojo
  // de escritura por delante, el .dpr deja de ser una carrera.
  EnterFileEdit;
  try
    Result := AddProjectUnitNucleo(AProject, APasPath);
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
    if SameText(EntryUnitName(E), AUnitName) then
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
    if not SameText(EntryUnitName(E), AUnitName) then
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
    end;
  if (Carry <> '') and (Length(Result) > 0) then
  begin
    // un // en la primera linea del prefijo iba detras de la coma de la
    // anterior: vuelve a SU linea (ReplaceUses pone el ; delante de el)
    var C := Carry.Replace(#13#10, #10);
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
      PatchSaveText(Dproj, Text, Enc);
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
    Result := RemoveProjectUnitNucleo(AProject, APasPath, AFileGoesToo);
  finally
    LeaveFileEdit;
  end;
end;

function RenameProjectUnitNucleo(const AProject, AOldPasPath, ANewPasPath: string): string;
var
  Dpr, Dproj, Enc, Text, OldName, OldInclude, Entry, NewInclude, Prefix, Core: string;
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
    if SameText(EntryUnitName(Entries[I]), OldName) then
    begin
      SplitEntryPrefix(Entries[I], Prefix, Core);
      Entries[I] := BuildEntry(Info, NewInclude);
      if Prefix <> '' then
        Entries[I] := Prefix + #10 + Entries[I];
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
    PatchSaveText(Dproj, Text, Enc);
  end;
  // Las OTRAS units del proyecto y el propio .dpr: sus uses y toda referencia
  // CUALIFICADA (UnitVieja.Identificador) seguian nombrando la unit vieja y
  // el build caia con E2003 (Hermes, 2026-09-22, test 19). Se reescribe el
  // nombre como identificador entero, fuera de cadenas, en cada fichero que
  // el proyecto lista, y la respuesta cuenta cuantas y donde.
  var NRefs := 0;
  var NFich := 0;
  var Ficheros: TArray<string> := [Dpr];
  for var PU in ProjectUnits(AProject, False) do
    if PU.Include <> '' then
      Ficheros := Ficheros + [TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(Dpr), PU.Include))];
  // Mismo nombre (move de carpeta sin renombrar): no hay nada que reescribir
  // y la cuenta decia "1 en 1 fichero" por sustituir X por X (medido en
  // vivo, 2026-09-23).
  // El .dpr puede listar ficheros de FUERA (..\Common, una referencia): se
  // reescribe solo lo que esta sesion puede escribir, y lo demas se dice.
  // El escritor tambien lo comprueba (EscrituraDenegada): esto es para
  // contestarlo en vez de lanzar a mitad (auditoria 25-sep-2026).
  var NoEscritos: TArray<string> := [];
  if not SameText(OldName, Info.UnitName) then
  for var Fich in Ficheros do
    if TFile.Exists(Fich) then
    begin
      if EscrituraDenegada(Fich) <> '' then
      begin
        NoEscritos := NoEscritos + [TPath.GetFileName(Fich)];
        Continue;
      end;
      var N := RenombrarIdentificadorUnit(Fich, OldName, Info.UnitName);
      if N > 0 then
      begin
        Inc(NRefs, N);
        Inc(NFich);
      end;
    end;
  Result := MsgFmt(SN_UNIT_RENAMED_FMT, [OldName, OldInclude, Info.UnitName, NewInclude,
    TPath.GetFileName(Dpr), U.Keyword, NRefs, NFich]);
  if Length(NoEscritos) > 0 then
    Result := Result + #10 + MsgFmt(SN_UNIT_RENAME_NOT_WRITTEN_FMT,
      [Length(NoEscritos), string.Join(', ', NoEscritos)]);
end;

function RenameProjectUnit(const AProject, AOldPasPath, ANewPasPath: string): string;
begin
  EnterFileEdit;
  try
    Result := RenameProjectUnitNucleo(AProject, AOldPasPath, ANewPasPath);
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
        if not TRegEx.IsMatch(N.Trim, '^[A-Za-z_]\w*(\.[A-Za-z_]\w*)*$') then
          Exit(MsgFmt(SR_REQUIRES_BAD_NAME_FMT, [N.Trim]));
        Nombres.Add(N.Trim);
      end;
    if Nombres.Count = 0 then
      Exit(MsgText(SR_REQUIRES_NEED_NAMES));
    EnterFileEdit;
    try
      Text := PatchLoadText(Dpr, Enc);
      NL := IfThen(Text.Contains(#13#10), #13#10, #10);
      // la clausula se localiza sobre el texto con los comentarios en blanco
      // (mismas posiciones) y se reescribe entera, un nombre por linea
      M := TRegEx.Match(BlankComments(Text), '^[ \t]*requires\b\s*(.*?);', [roIgnoreCase, roMultiline, roSingleline]);
      Existentes := [];
      if M.Success then
        for E in M.Groups[1].Value.Split([',']) do
          if E.Trim <> '' then
            Existentes := Existentes + [E.Trim];
      for N in Nombres do
      begin
        Ya := False;
        for E in Existentes do
          if SameText(E, N) then
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
        MPos := TRegEx.Match(Text, '^[ \t]*(contains\b|end\s*\.)', [roIgnoreCase, roMultiline]);
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
    if not TRegEx.IsMatch(Nombre, '^[A-Za-z_]\w*(\.[A-Za-z_]\w*)*$') then
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
    Blank := BlankComments(Text);
    M := TRegEx.Match(Blank, '^[ \t]*' + Sec + '\b', [roIgnoreCase, roMultiline]);
    if not M.Success then
      Exit(MsgFmt(SR_ADDUSES_NO_SECTION_FMT, [Sec, TPath.GetFileName(APasPath)]));
    PosSec := M.Index + M.Length;
    NL := IfThen(Text.Contains(#13#10), #13#10, #10);
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
      // linea en blanco, como la escribe el IDE
      FinLinea := PosSec;
      while (FinLinea <= Length(Text)) and not CharInSet(Text[FinLinea], [#10, #13]) do
        Inc(FinLinea);
      Text := Copy(Text, 1, FinLinea - 1) + NL + NL + 'uses' + NL + '  ' +
        string.Join(', ', Faltan) + ';' + Copy(Text, FinLinea, MaxInt);
    end;
    PatchSaveText(APasPath, Text, Enc);
    // el eco, releido del disco: la clausula tal y como ha quedado
    Text := PatchLoadText(APasPath, Enc);
    Blank := BlankComments(Text);
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
  PosSec, Fin: Integer;
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
    if not TRegEx.IsMatch(Nombre, '^[A-Za-z_]\w*(\.[A-Za-z_]\w*)*$') then
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
    Blank := BlankComments(Text);
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
    if Length(Entries) = 0 then
    begin
      Fin := U.EndPos + 1;
      while (Fin <= Length(Text)) and CharInSet(Text[Fin], [#10, #13]) do
        Inc(Fin);
      Text := Copy(Text, 1, U.StartPos - 1) + Copy(Text, Fin, MaxInt);
    end
    else
      Text := ReplaceUses(Text, U, Entries);
    PatchSaveText(APasPath, Text, Enc);
    // el eco, releido del disco
    Text := PatchLoadText(APasPath, Enc);
    Blank := BlankComments(Text);
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
      for P in ProjectUnits(F, False) do // el .dpk decide; sin leer .dproj
        if SameText(P.UnitName, AUnitName) then
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
  Stem := TPath.GetFileNameWithoutExtension(APasPath);
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
      for P in ProjectUnits(F, False) do // the .dpr decides; no .dproj read
        if SameText(P.UnitName, Stem) and
          (NormPath(TPath.Combine(TPath.GetDirectoryName(F), P.Include)) = NormPath(APasPath)) then
        begin
          Result := Result + [F];
          Break;
        end;
  end;
end;

{ Reescribe el NOMBRE de una unit como identificador entero en un fuente: las
  entradas de sus uses (interface e implementation) y las referencias
  cualificadas UnitVieja.Identificador. Fuera de cadenas (comillas impares
  antes del match en su linea = dentro de una cadena, no se toca); los
  comentarios si se reescriben, que un comentario que nombra la unit vieja
  tambien miente. La cabecera "unit X;" no se toca: la reescribe el que mueve
  el fichero. Devuelve cuantas ocurrencias cambio (0 = fichero intacto, no se
  reescribe). Medido por Hermes el 2026-09-22 (test 19): tras el rename el
  .dpr conservaba UBatHelper.Bat11Sum y el build caia con E2003. }
function RenombrarIdentificadorUnit(const APath, AViejo, ANuevo: string): Integer;
var
  Enc, Texto, Linea: string;
  Lineas: TArray<string>;
  Re: TRegEx;
  M: TMatch;
  I, J, Comillas, Ultimo: Integer;
  Partes: TStringBuilder;
begin
  Result := 0;
  Texto := PatchLoadText(APath, Enc);
  Re := TRegEx.Create('(?<![\w.])' + TRegEx.Escape(AViejo) + '(?![\w])', [roIgnoreCase]);
  Lineas := Texto.Split([#10]); // el #13 de un CRLF se queda en cada linea y vuelve intacto
  for I := 0 to High(Lineas) do
  begin
    Linea := Lineas[I];
    if Linea.TrimLeft.StartsWith('unit ', True) then
      Continue;
    Partes := TStringBuilder.Create;
    try
      Ultimo := 0; // 0-based: hasta donde se ha copiado ya la linea
      for M in Re.Matches(Linea) do
      begin
        Comillas := 0;
        for J := 1 to M.Index - 1 do
          if Linea[J] = '''' then
            Inc(Comillas);
        if Odd(Comillas) then
          Continue; // dentro de una cadena
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
    PatchSaveText(APath, string.Join(#10, Lineas), Enc);
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
    Viejo := ExcludeTrailingPathDelimiter(TPath.GetFullPath(TPath.Combine(ABaseVieja, V)));
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
  Viejo := ExcludeTrailingPathDelimiter(TPath.GetFullPath(AViejo));
  Nuevo := ExcludeTrailingPathDelimiter(TPath.GetFullPath(ANuevo));
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
  if Texto.Contains(#13#10) then
    NL := #13#10
  else
    NL := #10;
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
      Exit(MsgFmt(SR_GRUPO_FORMA_FMT, [TPath.GetFileName(AGroup)]));
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
    Exit(MsgFmt(SR_GRUPO_FORMA_FMT, [TPath.GetFileName(AGroup)]));
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
        Exit(MsgFmt(SR_GRUPO_FORMA_FMT, [TPath.GetFileName(AGroup)]));
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
