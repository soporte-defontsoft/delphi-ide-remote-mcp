unit Lsp.References;

{ Hybrid find-references. DelphiLSP does not implement textDocument/references
  (-32601, measured), so we combine a text scan with compiler-grade
  validation:

    1. resolve the target: definition() at the requested position;
    2. text-scan the project tree for word-boundary candidates of the
       identifier (case-insensitive - it's Pascal), skipping IDE artifacts;
    3. for each candidate, ask definition() at that exact spot: only the
       candidates that resolve to the SAME location as the target are
       confirmed - homonyms die here, killed by the compiler engine itself.

  Bounded: at most AMaxFiles files are opened for validation; candidates in
  files beyond that are reported as unverified rather than silently dropped. }

interface

uses
  System.JSON;

function FindDelphiReferences(const AFilePath: string;
  ALine, ACharacter: Integer; AMaxFiles: Integer = 40;
  AMaxCandidates: Integer = 400): TJSONObject;

const
  // los campos de un uso (references, rename_symbol) que son la LINEA del
  // fichero tal cual: contenido, no van enmascarados (Lsp.Guard.
  // EnmascaraJsonSalvo); un ancla copiada de ahi casaba con 'srvd:' y no con
  // el disco (revision del 4-oct-2026)
  CONTENIDO_DE_UN_USO: array [0 .. 1] of string = ('text', 'anchor');

{ True for IDE artifacts that must never be scanned/edited/reasoned about. }
function SkipIdeArtifacts(const APath: string): Boolean; overload;

{ WHY a path is skipped: 'artifacts' (build output, __history), 'temp' (the
  server's own __delphi-temp), 'git' (the repository's own plumbing),
  'trash' (this tool's recoverable copies) or '' when it is not skipped at
  all - the SKIP_* constants below. delphi_list used to count every one of them
  as "IDE build/artifact folders", so a listing that hid 42 files of .git
  sent the reader looking for build output that did not exist (2026-08-25). }
function SkipReason(const APath: string; AAllowTrash: Boolean): string;

{ Same, but when AAllowTrash the recoverable-trash folders (__delphi-patch /
  __pascal-patch) are NOT treated as skip reasons - so delphi_list can, on
  explicit request, show what was deleted for a restore (field round 6, R6-B).
  Every other artifact (__history, Win32/Win64, .git...) is still skipped. }
function SkipIdeArtifacts(const APath: string; AAllowTrash: Boolean): Boolean; overload;

const
  SKIP_ARTIFACTS = 'artifacts';
  SKIP_TEMP = 'temp';
  SKIP_GIT = 'git';
  SKIP_TRASH = 'trash';
  { No sale de SkipReason: son las carpetas de otras herramientas (.vs,
    .github, __pycache__) que solo esconde el modo dirs de delphi_list. }
  SKIP_FOLDERS = 'folders';

type
  { Lo que un recorrido NO ensena, contado POR MOTIVO (los SKIP_*), y UNA
    cosa que lo cuenta y se lo dice al lector. delphi_list llevaba dos
    cuentas a mano (dirs y ficheros) y ninguna acertaba del todo:
    __delphi-temp salia como "carpeta de compilacion" con el consejo de
    pasarla como root, __history como papelera, .vs como git y Win64 en
    ningun cajon; y delphi_search escondia lo mismo sin decirlo (revision
    de baterias, 26-sep-2026). Se empieza con Default(THiddenCount). }
  THiddenCount = record
    Artifacts, Temp, Git, Trash, Folders: Integer;
    procedure Add(const AReason: string);
    function Total: Integer;
    { hidden, un campo por cada motivo que no sea cero y la nota que dice
      que es cada cosa y como verla. Si no se escondio nada, nada. }
    procedure Report(AObj: TJSONObject);
  end;

  { UNA pagina de una lista recorrida entera. delphi_search y delphi_projects
    contaban, cortaban y escribian total/shown/offset/hasMore/nextOffset cada
    una a mano, y delphi_list ni paginaba: cortaba en 500 y lo de detras no
    se alcanzaba (Hermes en la raiz de referencia de un ERP, 5-oct-2026: las
    500 primeras entradas eran copias de backups\). Se empieza con PaginaDe. }
  TPagina = record
    Desde, Max, Total, Mostrados: Integer;
    { uno mas de la lista: True si cae en ESTA pagina (y ya cuenta como
      mostrado) }
    function Entra: Boolean;
    function HayMas: Boolean;
    function Siguiente: Integer;
    { total, shown, offset (si no es 0), hasMore y nextOffset (si hay mas):
      lo que hace falta para pedir la siguiente sin adivinar }
    procedure Report(AObj: TJSONObject);
  end;

  { DONDE esta una lista que no cabe, no solo cuanto: la carpeta de cada
    entrada a dos niveles bajo la raiz ('.' la propia raiz), y las que mas
    acumulan. Con eso el agente elige root en vez de pasear paginas: en una
    maquina de trabajo las listas las copan las copias de seguridad y los
    componentes (delphi_projects lo hacia a mano: 7.025 proyectos, 6.420
    eran copias; 20-sep-2026). Se empieza con Default(TPorCarpeta). }
  TPorCarpeta = record
    Carpetas: TArray<string>;
    Cuentas: TArray<Integer>;
    Ultima: Integer; // un paseo da seguidas las de una carpeta
    procedure Add(const AFichero, ARaiz: string);
    { byFolder: las ACuantas que mas, "carpeta = N", de mas a menos }
    procedure Report(AObj: TJSONObject; ACuantas: Integer = 10);
  end;

{ La pagina que pide quien llama: un offset negativo es 0, un maximo que no
  es positivo es APorDefecto y uno mayor que ATope es ATope. }
function PaginaDe(AOffset, AMax, APorDefecto, ATope: Integer): TPagina;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.Generics.Collections,
  Lsp.Client,
  Lsp.Session,
  Lsp.Guard,
  Lsp.Texts,
  System.RegularExpressions,
  Lsp.Dproj,        // RutasDeBusqueda: el search path de un .dproj, resuelto
  Lsp.ProjectUnits,
  Lsp.Pascal,
  Lsp.PascalDecl, // EL lector de clases y LA cadena de ancestros
  Lsp.NetDrives;  // SinBarraFinal

type
  TCandidate = record
    Path: string;
    Line, Col: Integer;
    Text: string;
  end;

function IdentifierAt(const ALineText: string; ACol: Integer): string;
var
  S, E: Integer;
begin
  // ACol is 0-based; string is 1-based. EL identificador (Lsp.Pascal): con
  // A-Z a mano, el de debajo del cursor en un nombre con enye era un trozo
  // (censo del 4-oct-2026)
  S := ACol + 1;
  if (S < 1) or (S > Length(ALineText)) or not EsCaracterDeIdent(ALineText[S]) then
    Exit('');
  while (S > 1) and EsCaracterDeIdent(ALineText[S - 1]) do
    Dec(S);
  E := ACol + 1;
  while (E < Length(ALineText)) and EsCaracterDeIdent(ALineText[E + 1]) do
    Inc(E);
  Result := Copy(ALineText, S, E - S + 1);
end;

{ Folders of projects whose SEARCH PATH points at ADir - i.e. projects that
  compile against the units living there, even though they do not list them.
  A test project beside the code it exercises is the everyday case. }
function ProjectsSearching(const ADir: string): TArray<string>;
var
  L: TStringList;
  Target, Root, Xml: string;
begin
  Result := nil;
  if ADir = '' then
    Exit;
  Target := IncludeTrailingPathDelimiter(TPath.GetFullPath(ADir)).ToLower;
  L := TStringList.Create;
  try
    L.Duplicates := dupIgnore;
    L.Sorted := True;
    for Root in WorkspaceRoots do
    begin
      if (Root.Trim = '') or not TDirectory.Exists(Root.Trim) then
        Continue;
      for var Dproj in WalkFiles(Root.Trim, '*.dproj') do
      begin
        if SkipIdeArtifacts(Dproj) then
          Continue;
        try
          Xml := TFile.ReadAllText(Dproj);
        except
          Continue;
        end;
        for var R in RutasDeBusqueda(Dproj, Xml) do
          if (R.Carpeta <> '') and
             (IncludeTrailingPathDelimiter(R.Carpeta).ToLower = Target) then
            L.Add(TPath.GetDirectoryName(Dproj));
      end;
    end;
    Result := L.ToStringArray;
  finally
    L.Free;
  end;
end;

{ LAS CARPETAS QUE NO SON CODIGO, en UN solo sitio.

  Estaban escritas dos veces, identicas, en las dos funciones de aqui abajo:
  el mismo olor que todo lo demas de este repo una talla mas pequena. Anadir
  una carpeta nueva obligaba a acordarse de las dos, y la que se olvidase
  haria que delphi_list la ocultase y delphi_search la ensenase (o al reves).

  Y no son una lista, porque no se tratan igual:

    ARTEFACTO  se salta SIEMPRE. Compilacion, historicos del IDE...
    TEMPORAL   tambien SIEMPRE: los temporales del servidor cuando caen
               dentro de un workspace (una captura que el agente tiene que
               poder bajarse con delphi_fetch). De un temporal no se
               restaura nada, asi que ni con includeTrash tiene sentido
               ensenarlo. Va APARTE de los artefactos porque quien lee el
               recuento tiene que saber cual de los dos es: la nota lo
               llamaba carpeta de compilacion (26-sep-2026).
    PAPELERA   se salta salvo que te lo pidan (includeTrash=true), porque de
               ahi SI se restaura.

  El nombre de la carpeta de temporales lo pone TempFolderName (Lsp.Guard), y
  el de la papelera TrashFolderName (Lsp.Patch); aqui van literales porque un
  array const no puede llamar a una funcion. Que digan lo mismo no se deja a
  la buena fe: lo comprueba la bateria (test_round44 T6c y T6d). }
const
  CARPETAS_ARTEFACTO: array [0 .. 6] of string = (
    '\__history\', '\__recovery\', '\win32\', '\win64\', '\debug\',
    '\release\', '\dcu\');
  CARPETA_TEMPORAL = '\__delphi-temp\';
  CARPETAS_PAPELERA: array [0 .. 1] of string = (
    '\__pascal-patch\', '\__delphi-patch\');

{ Saltar y el motivo de saltar son UNA decision: la toma SkipReason. }
function SkipIdeArtifacts(const APath: string; AAllowTrash: Boolean): Boolean;
begin
  Result := SkipReason(APath, AAllowTrash) <> '';
end;

function SkipIdeArtifacts(const APath: string): Boolean;
begin
  Result := SkipIdeArtifacts(APath, False);
end;

function SkipReason(const APath: string; AAllowTrash: Boolean): string;
var
  B, Low: string;
begin
  Result := '';
  Low := APath.ToLower;
  if Low.Contains('\.git\') then
    Exit(SKIP_GIT);
  if Low.Contains(CARPETA_TEMPORAL) then
    Exit(SKIP_TEMP);
  for B in CARPETAS_ARTEFACTO do
    if Low.Contains(B) then
      Exit(SKIP_ARTIFACTS);
  if not AAllowTrash then
    for B in CARPETAS_PAPELERA do
      if Low.Contains(B) then
        Exit(SKIP_TRASH);
end;

{ TPagina }

function PaginaDe(AOffset, AMax, APorDefecto, ATope: Integer): TPagina;
begin
  Result := Default(TPagina);
  if AOffset > 0 then
    Result.Desde := AOffset;
  if AMax <= 0 then
    AMax := APorDefecto;
  if AMax > ATope then
    AMax := ATope;
  Result.Max := AMax;
end;

function TPagina.Entra: Boolean;
begin
  Inc(Total);
  Result := (Total > Desde) and (Mostrados < Max);
  if Result then
    Inc(Mostrados);
end;

function TPagina.HayMas: Boolean;
begin
  Result := Total > Desde + Mostrados;
end;

function TPagina.Siguiente: Integer;
begin
  Result := Desde + Mostrados;
end;

procedure TPagina.Report(AObj: TJSONObject);
begin
  AObj.AddPair('total', TJSONNumber.Create(Total));
  AObj.AddPair('shown', TJSONNumber.Create(Mostrados));
  if Desde > 0 then
    AObj.AddPair('offset', TJSONNumber.Create(Desde));
  // Truncated lists used to be a wall: the cap hit, no way to ask for the
  // rest (hermes, release audit 2026-08-26). hasMore + nextOffset make the
  // next page one deterministic call away.
  AObj.AddPair('hasMore', TJSONBool.Create(HayMas));
  if HayMas then
    AObj.AddPair('nextOffset', TJSONNumber.Create(Siguiente));
end;

{ TPorCarpeta }

procedure TPorCarpeta.Add(const AFichero, ARaiz: string);
var
  Carpeta, Raiz, Rel: string;
  I: Integer;
begin
  Carpeta := SinBarraFinal(TPath.GetDirectoryName(AFichero));
  Raiz := SinBarraFinal(ARaiz);
  if SameText(Carpeta, Raiz) then
    // en la propia raiz: decia la raiz recortada a dos segmentos y parecia
    // OTRA carpeta
    Rel := '.'
  else if StartsText(IncludeTrailingPathDelimiter(Raiz), Carpeta) then
  begin
    Rel := Carpeta.Substring(Length(IncludeTrailingPathDelimiter(Raiz)));
    var Trozos := Rel.Split([TPath.DirectorySeparatorChar]);
    if Length(Trozos) > 2 then
      Rel := Trozos[0] + TPath.DirectorySeparatorChar + Trozos[1];
  end
  else
    Rel := Carpeta;
  if (Ultima < Length(Carpetas)) and SameText(Carpetas[Ultima], Rel) then
  begin
    Inc(Cuentas[Ultima]);
    Exit;
  end;
  for I := 0 to High(Carpetas) do
    if SameText(Carpetas[I], Rel) then
    begin
      Inc(Cuentas[I]);
      Ultima := I;
      Exit;
    end;
  Carpetas := Carpetas + [Rel];
  Cuentas := Cuentas + [1];
  Ultima := High(Carpetas);
end;

procedure TPorCarpeta.Report(AObj: TJSONObject; ACuantas: Integer);
var
  Quedan: TArray<Integer>;
  Arr: TJSONArray;
  I, J, Mejor, MejorN: Integer;
begin
  Quedan := Copy(Cuentas);
  Arr := TJSONArray.Create;
  AObj.AddPair('byFolder', Arr);
  for I := 1 to ACuantas do
  begin
    Mejor := -1;
    MejorN := 0;
    for J := 0 to High(Quedan) do
      if Quedan[J] > MejorN then
      begin
        MejorN := Quedan[J];
        Mejor := J;
      end;
    if Mejor < 0 then
      Break;
    Arr.Add(Format('%s = %d', [Carpetas[Mejor], MejorN]));
    Quedan[Mejor] := 0;
  end;
end;

{ THiddenCount }

procedure THiddenCount.Add(const AReason: string);
begin
  if AReason = SKIP_ARTIFACTS then
    Inc(Artifacts)
  else if AReason = SKIP_TEMP then
    Inc(Temp)
  else if AReason = SKIP_GIT then
    Inc(Git)
  else if AReason = SKIP_TRASH then
    Inc(Trash)
  else if AReason = SKIP_FOLDERS then
    Inc(Folders)
  else
    // Un motivo nuevo en SkipReason sin su cajon aqui se perderia de la
    // cuenta en silencio: mejor que se vea en la primera bateria.
    raise Exception.Create(MsgFmt(SE_LSP_THIDDENCOUNT_MOTIVO_SIN_CAJON_FMT, [AReason]));
end;

function THiddenCount.Total: Integer;
begin
  Result := Artifacts + Temp + Git + Trash + Folders;
end;

procedure THiddenCount.Report(AObj: TJSONObject);
var
  Partes: TArray<string>;

  procedure Motivo(ACuantos: Integer; const ACampo, AFmt: string);
  begin
    if ACuantos = 0 then
      Exit;
    AObj.AddPair(ACampo, TJSONNumber.Create(ACuantos));
    Partes := Partes + [Format(AFmt, [ACuantos])];
  end;

begin
  if Total = 0 then
    Exit;
  AObj.AddPair('hidden', TJSONNumber.Create(Total));
  Motivo(Artifacts, 'hiddenBuildArtifacts', MsgText(SN_HIDDEN_ARTIFACTS_FMT));
  Motivo(Temp, 'hiddenServerTemp', MsgText(SN_HIDDEN_TEMP_FMT));
  Motivo(Git, 'hiddenGitInternals', MsgText(SN_HIDDEN_GIT_FMT));
  Motivo(Trash, 'hiddenTrash', MsgText(SN_HIDDEN_TRASH_FMT));
  Motivo(Folders, 'hiddenToolFolders', MsgText(SN_HIDDEN_FOLDERS_FMT));
  AObj.AddPair('note', MsgFmt(SN_HIDDEN_HEAD_FMT, [Total]) + ' ' +
    string.Join('; ', Partes) + '.');
end;

function SkipPath(const APath: string): Boolean;
begin
  Result := SkipIdeArtifacts(APath);
end;

{ ------------------------------------------------- codigo, o solo prosa - }

{ Un candidato dentro de un COMENTARIO o de un LITERAL de cadena no es una
  referencia. El motor contesta ahi lo mismo que cuando la validacion se
  queda sin presupuesto -nada- y los dos acababan en el mismo saco,
  "unverified". Pero "no lo se" y "se que no" no son lo mismo, y confundirlos
  se pagaba caro: delphi_rename_symbol bloquea el rename con UN solo
  unverified, asi que cualquier identificador nombrado en un comentario -en
  codigo documentado, casi todos- dejaba esa tool inservible. Medido el
  2026-09-21 sobre MaskDriveText de este mismo repo: 18 confirmadas y 6
  unverified, las SEIS comentarios.

  Se decide por lexico y no preguntando al motor, porque el motor ya ha dicho
  lo unico que sabe decir: por EL lexico de la casa (Lsp.Pascal), sobre el
  fichero entero, porque un comentario de bloque cruza lineas y el estado
  tiene que viajar con ellas. Aqui vivia su propia copia (MarcaCodigo); el
  censo del 2-oct-2026 las junto en una. }

{ LA SEGUNDA CLASE DE GEMELO.

  Un metodo virtual y el que lo sobrescribe no son homonimos: son el MISMO
  metodo visto desde dos alturas de la jerarquia, y una llamada a traves de
  una variable de la hija resuelve SIEMPRE a la hija. Preguntando por
  TBase.Pinta, la tool contestaba "no lo llama nadie" y mandaba a la lista de
  homonimos el override y LAS DOS LLAMADAS REALES (medido 2026-09-20). Un
  agente lee eso, concluye que el virtual es codigo muerto y borra la base de
  la jerarquia: el mismo desenlace que el bug de la v1.0.4, un nivel mas
  arriba.

  Se resuelve con lo que ya esta en la mano -los fuentes que el escaneo lee de
  todas formas- y con una condicion estricta: mismo identificador Y clases
  emparentadas por herencia. Sin parentesco no se junta nada. }

{ La clase a la que pertenece un metodo en ALine. '' cuando es una rutina
  global. Dos formas: "procedure TBase.Pinta;" lo dice en su propia linea, y
  "procedure Pinta; virtual;" vive DENTRO de la clase: el tipo que contiene
  esa linea, de EL lector de clases (AUnidad, leida de ALines; un record no
  tiene familia). Se subia linea a linea hasta un "X = class" y se paraba en
  un "end;" de cuatro espacios: un record anidado o una clase de una linea lo
  enganaban (censo del 4-oct-2026). }
function ClaseDeMetodo(const ALines: TStringList; AUnidad: TUnidadPas; ALine: Integer;
  const AIdent: string): string;
var
  T: TTipoPas;
begin
  Result := '';
  if (ALine < 0) or (ALine >= ALines.Count) or (AIdent = '') then
    Exit;
  // la cabecera cualificada, por SU lector (Lsp.PascalDecl): con un solo
  // identificador delante del punto, la de un metodo de una generica
  // (THija<T>.Pinta) o de una anidada no casaba, y la llamada a un override
  // suyo salia rechazada como homonimo (medido el 4-oct-2026)
  Result := ClaseDeImplementacion(ALines[ALine], AIdent);
  if Result <> '' then
    Exit;
  T := AUnidad.TipoEnLinea(ALine, [ctClase, ctInterfaz, ctRegistro, ctAyudante]);
  if (T <> nil) and (T.Clase <> ctRegistro) then
    Result := T.Nombre;
end;

{ true si una de las dos clases desciende de la otra, por LA cadena de
  ancestros (Lsp.PascalDecl) sobre lo que el escaneo leyo (AnotaAncestros de
  cada fuente). El tope de 20 saltos es contra una jerarquia circular en
  fuentes a medio escribir. }
function MismaFamilia(const AMapa: TDictionary<string, string>;
  const A, B: string): Boolean;

  function Desciende(const AHijo, AAbuelo: string): Boolean;
  var
    Sale: Boolean;
  begin
    for var C in CadenaDeAncestros(AMapa, AHijo, Sale, 21) do
      if MismoIdentificador(UltimoTrozo(C), AAbuelo) then
        Exit(True);
    Result := False;
  end;

begin
  Result := (A <> '') and (B <> '') and
    (Desciende(A, B) or Desciende(B, A));
end;

function DefinitionLocation(AResp: TJSONObject; out AUri: string;
  out ALine: Integer): Boolean;
var
  V: TJSONValue;
  Obj: TJSONObject;
begin
  Result := False;
  AUri := '';
  ALine := -1;
  V := AResp.GetValue('result');
  if (V = nil) or (V is TJSONNull) then
    Exit;
  if V is TJSONArray then
  begin
    if TJSONArray(V).Count = 0 then
      Exit;
    V := TJSONArray(V).Items[0];
  end;
  if not (V is TJSONObject) then
    Exit;
  Obj := TJSONObject(V);
  if Obj.GetValue('uri') = nil then
    Exit;
  AUri := Obj.GetValue('uri').Value;
  ALine := Obj.GetValue<Integer>('range.start.line');
  Result := True;
end;

function FindDelphiReferences(const AFilePath: string;
  ALine, ACharacter: Integer; AMaxFiles, AMaxCandidates: Integer): TJSONObject;
var
  Session: TLspSession;
  Client: TLspClient;
  Settings, RootDir, FullPath, Ident, TargetUri, CandUri: string;
  Lines: TStringList;
  Resp: TJSONObject;
  TargetLine, CandLine: Integer;
  Candidates: TList<TCandidate>;
  Cand: TCandidate;
  Files: TArray<string>;
  F, Ext, Text, LineText: string;
  AllFiles: TList<string>;
  I, P, ScanCol, FilesOpened: Integer;
  Confirmed, Unverified: TJSONArray;
  Menciones: TList<TCandidate>;   // el nombre aparece, pero en prosa
  VistaLines: TStringList;        // las lineas de su CODIGO (Lsp.Pascal)
  VistaLine: string;
  Rejected, Scanned: Integer;
  RejectedArr: TJSONArray;
  ScopeDirs: TArray<string>;
  OpenedFiles: TDictionary<string, Boolean>;
  Entry: TJSONObject;

  function CandidateJson(const C: TCandidate): TJSONObject;
  begin
    Result := TJSONObject.Create;
    Result.AddPair('path', C.Path);
    Result.AddPair('line', TJSONNumber.Create(C.Line));
    // La 1-based al lado de la 0-based, como definition/hover: references y
    // diagnostics eran las dos tools del motor sin gemela (Hermes, 2026-09-23)
    Result.AddPair('line1', TJSONNumber.Create(C.Line + 1));
    Result.AddPair('character', TJSONNumber.Create(C.Col));
    Result.AddPair('text', C.Text.Trim);
    // The trimmed text reads well but is NOT an anchor: delphi_edit wants the
    // WHOLE line, indentation included, so every caller had to go and read
    // the file again (measured 2026-08-25, five wasted calls). Give both.
    Result.AddPair('anchor', C.Text.TrimRight([#13, #10]));
  end;

begin
  Session := TLspSession.Instance;
  FullPath := TPath.GetFullPath(AFilePath);
  Client := Session.AcquireFor(FullPath, Settings);
  Session.ResolveSettings(FullPath, RootDir);

  // Identify the symbol under the cursor.
  Lines := TStringList.Create;
  try
    Lines.Text := TLspClient.LoadSourceText(FullPath);
    if (ALine < 0) or (ALine >= Lines.Count) then
      raise Exception.Create(MsgFmt(SR_LSP_LINE_OUT_RANGE_FMT, [ALine]));
    Ident := IdentifierAt(Lines[ALine], ACharacter);
  finally
    Lines.Free;
  end;
  if Ident = '' then
    raise Exception.Create(MsgText(SR_LSP_NO_IDENTIFIER));

  // Resolve the target location the compiler engine assigns to that symbol.
  var Pending: Boolean;
  Resp := Client.DefinitionResolved(TLspClient.PathToUri(FullPath), ALine, ACharacter, Pending);
  try
    if not DefinitionLocation(Resp, TargetUri, TargetLine) then
    begin
      // Hover knows the symbol but definition is not indexed yet: that is
      // "not yet", not "not a symbol" (measured by Hermes, 2026-09-22).
      if Pending then
        raise Exception.CreateFmt(MsgText(SR_REFS_WARMING_FMT), [Ident]);
      // This fires whenever the position is not on something the compiler
      // can resolve - inside a string literal, in a comment, on a keyword -
      // and it used to blame "project settings" and quote the name of an
      // internal function, which sent the reader looking in the wrong place
      // (measured 2026-08-25).
      raise Exception.CreateFmt(MsgText(SR_REFS_NO_DEFINITION_FMT), [Ident]);
    end;
  finally
    Resp.Free;
  end;

  // El motor contesta con un FICHERO, y ese fichero puede no ser de aqui: el
  // indice le sobrevive al servidor y una unit sin configurar se resuelve
  // contra otra del mismo nombre vista en otra sesion (y en otra jaula).
  // Hasta ahora esa ruta ajena viajaba hasta el primer sitio que tocaba la
  // jaula y reventaba la llamada entera con un RECHAZADO... que escupia la
  // ruta. Se corta AQUI, que es donde la respuesta del motor entra en
  // nuestro mundo, y el mensaje nombra el identificador y no el sitio.
  // La zona de biblioteca (RTL/VCL, componentes instalados) NO cae aqui:
  // ReadPathDenied la da por buena, que es justo lo que se quiere.
  if ReadPathDenied(TLspClient.UriToPath(TargetUri)) <> '' then
    raise Exception.CreateFmt(MsgText(SR_REFS_TARGET_OUTSIDE_FMT), [Ident]);

  // A Pascal routine has TWO definition lines: the interface (or forward)
  // declaration and the implementation. The engine answers one or the other
  // depending on WHERE you ask, and the two never compare equal - so asking
  // "who uses this" from the BODY confirmed the body and threw every real
  // call site away as a homonym. Measured 2026-09-20 on OneTool: 4 real
  // uses, 1 reported from the body, 3 from a call site. An agent that goes
  // delphi_symbols (which hands you DECLARATION lines) -> delphi_references
  // lands exactly on the bad side and reads "nobody uses this" about a
  // routine with two callers - a wrong answer, not a missing one.
  // So resolve the counterpart ONCE, here, and accept both as one symbol.
  var TargetTwin: Integer := -1;
  var ClaseObjetivo := '';
  var Familia := False;
  var Herencia := TDictionary<string, string>.Create;
  var Textos := TObjectDictionary<string, TStringList>.Create([doOwnsValues]);
  // y sus clases, leidas una vez por fichero (EL lector, Lsp.PascalDecl)
  var Unidades := TObjectDictionary<string, TUnidadPas>.Create([doOwnsValues]);
  var TargetPath := TLspClient.UriToPath(TargetUri);
  if TFile.Exists(TargetPath) then
  begin
    var TwinLines := TStringList.Create;
    var TwinU: TUnidadPas := nil;
    try
      // la vista del codigo: lo que se busca aqui es estructura (la clase
      // del metodo) y la columna del identificador en codigo
      TwinLines.Text := CodigoPascal(TLspClient.LoadSourceText(TargetPath));
      TwinU := LeeFuentePascal(TwinLines.Text);
      ClaseObjetivo := ClaseDeMetodo(TwinLines, TwinU, TargetLine, Ident);
      if (TargetLine >= 0) and (TargetLine < TwinLines.Count) then
      begin
        // Same 1-based-Pos-as-character convention the candidate loop uses
        // below: a position one char into the identifier, never its edge.
        var TwinCol := Pos(Ident.ToLower, TwinLines[TargetLine].ToLower);
        if TwinCol > 0 then
        begin
          Resp := Client.Definition(TargetUri, TargetLine, TwinCol);
          try
            var TwinUri: string;
            var TwinLine: Integer;
            if DefinitionLocation(Resp, TwinUri, TwinLine) and
               SameText(TwinUri, TargetUri) and (TwinLine <> TargetLine) then
            begin
              TargetTwin := TwinLine;
              // La mitad declarada dentro de la clase no siempre dice de
              // quien es; la implementacion SIEMPRE lo dice, cualificada.
              if ClaseObjetivo = '' then
                ClaseObjetivo := ClaseDeMetodo(TwinLines, TwinU, TwinLine, Ident);
            end;
          finally
            Resp.Free;
          end;
        end;
      end;
    finally
      TwinU.Free;
      TwinLines.Free;
    end;
  end;

  // Text scan for candidates.
  Candidates := TList<TCandidate>.Create;
  Menciones := TList<TCandidate>.Create;
  AllFiles := TList<string>.Create;
  try
    // The project folder is not the whole project: units living in sibling
    // folders (SharedSource\ next to codigofuente\, measured 2026-08-23 on a
    // real project) were never scanned, so a symbol used twice in its own
    // file reported zero references. Scan the project folder, the folder of
    // the file itself and the folder of every unit the .dpr lists.
    var Dirs := TList<string>.Create;
    try
      // Con el MISMO filtro que los otros dos sitios que anaden carpetas
      // aqui abajo. Era uno de tres y era el unico sin comprobar, que es
      // como se cuelan estas cosas: RootDir no lo elige quien llama, lo
      // decide la busqueda de configuracion, y esa podia traerlo de FUERA
      // del workspace (un .dproj suelto por encima de la raiz). El barrido
      // se llevaba entonces todo lo que colgase de ahi - medido el
      // 2026-09-21: 168 fuentes de otros workspaces - y la llamada moria
      // publicando sus rutas. La causa se corto ademas en Lsp.Session
      // (PuedoSubirA); esto es el cinturon, porque el ambito del barrido es
      // cosa de aqui.
      var Raiz := IncludeTrailingPathDelimiter(TPath.GetFullPath(RootDir));
      if ReadPathDenied(Raiz) = '' then
        Dirs.Add(Raiz);
      var Extra: TArray<string> := [TPath.GetDirectoryName(FullPath)];
      var Dproj := Session.FindDproj(FullPath);
      if Dproj <> '' then
        for var PU in ProjectUnits(Dproj, False) do
          if TPath.IsPathRooted(PU.Include) then
            Extra := Extra + [TPath.GetDirectoryName(PU.Include)]
          else
            Extra := Extra + [TPath.GetDirectoryName(TPath.GetFullPath(
              TPath.Combine(TPath.GetDirectoryName(Dproj), PU.Include)))];
      for var D in Extra do
      begin
        if (D = '') or not TDirectory.Exists(D) then
          Continue;
        var DD := IncludeTrailingPathDelimiter(TPath.GetFullPath(D));
        var Covered := False;
        for var K in Dirs do
          if StartsText(K, DD) then
          begin
            Covered := True;
            Break;
          end;
        if not Covered and (ReadPathDenied(DD) = '') then
          Dirs.Add(DD);
      end;
      // ...and the projects that CONSUME this folder. A test project sitting
      // next door with `..\Inventario` in its search path is not "somewhere
      // else": it compiles against these very units, and a rename that
      // ignores it breaks its build. Measured 2026-08-25: the reference in
      // the sibling test WAS seen and then filed as a homonym, so the rename
      // came back applicable and the next build failed.
      for var Sib in ProjectsSearching(TPath.GetDirectoryName(FullPath)) do
      begin
        var SD := IncludeTrailingPathDelimiter(TPath.GetFullPath(Sib));
        var Have := False;
        for var K in Dirs do
          if StartsText(K, SD) then
          begin
            Have := True;
            Break;
          end;
        if not Have and (ReadPathDenied(SD) = '') then
          Dirs.Add(SD);
      end;
      for var D in Dirs do
      begin
        ScopeDirs := ScopeDirs + [D];
        for Ext in TArray<string>.Create('*.pas', '*.dpr', '*.inc') do
          for F in WalkFiles(D, Ext) do
            if not SkipPath(F) and not AllFiles.Contains(F) then
              AllFiles.Add(F);
      end;
    finally
      Dirs.Free;
    end;
    Scanned := AllFiles.Count;

    for F in AllFiles do
    begin
      if Candidates.Count >= AMaxCandidates then
        Break;
      Text := TLspClient.LoadSourceText(F);
      // lo que es codigo lo dice EL lexico (Lsp.Pascal): la vista del codigo
      // tiene el mismo largo y los mismos saltos, y un identificador es
      // codigo si su primera letra sigue en ella. Aqui habia una copia del
      // lexico (MarcaCodigo, 2026-09-21); el censo del 2-oct-2026 las junto
      var Vista := CodigoPascal(Text);
      // La jerarquia se apunta AQUI, del fuente que ya se ha leido para
      // buscar candidatos: el parentesco entre clases sale gratis. Sus
      // clases, de EL lector (tenia su propia regex)
      var UVista := LeeFuentePascal(Vista);
      try
        AnotaAncestros(UVista, Herencia);
      finally
        UVista.Free;
      end;
      Lines := TStringList.Create;
      VistaLines := TStringList.Create;
      try
        Lines.Text := Text;
        VistaLines.Text := Vista;
        for I := 0 to Lines.Count - 1 do
        begin
          LineText := Lines[I];
          VistaLine := VistaLines[I];
          ScanCol := 1;
          repeat
            P := Pos(Ident.ToLower, LineText.ToLower, ScanCol);
            if P = 0 then
              Break;
            // word boundaries
            if ((P = 1) or not EsCaracterDeIdent(LineText[P - 1])) and
               ((P + Length(Ident) > Length(LineText)) or
                not EsCaracterDeIdent(LineText[P + Length(Ident)])) then
            begin
              Cand.Path := F;
              Cand.Line := I;
              Cand.Col := P - 1;
              Cand.Text := LineText;
              // Codigo, o solo una mencion. Y una mencion ya no gasta
              // presupuesto de candidatos ni hace abrir un fichero para
              // validarla: ese era el otro coste, callado, de meterlas en
              // el mismo saco que lo que no se pudo comprobar.
              if (P <= Length(VistaLine)) and (VistaLine[P] <> ' ') then
              begin
                Candidates.Add(Cand);
                if Candidates.Count >= AMaxCandidates then
                  Break;
              end
              else
                Menciones.Add(Cand);
            end;
            ScanCol := P + Length(Ident);
          until False;
          if Candidates.Count >= AMaxCandidates then
            Break;
        end;
      finally
        Lines.Free;
        VistaLines.Free;
      end;
    end;

    // Validate candidates with definition(), bounded by AMaxFiles.
    Confirmed := TJSONArray.Create;
    Unverified := TJSONArray.Create;
    Rejected := 0;
    RejectedArr := TJSONArray.Create;
    FilesOpened := 0;
    OpenedFiles := TDictionary<string, Boolean>.Create;
    try
      for Cand in Candidates do
      begin
        if not OpenedFiles.ContainsKey(Cand.Path.ToLower) then
        begin
          if FilesOpened >= AMaxFiles then
          begin
            Unverified.Add(CandidateJson(Cand));
            Continue;
          end;
          // didOpen + warm, en el motor AL QUE SE PREGUNTA: AcquireFor buscaba
          // el del candidato, y una unidad compartida arrancaba el de otro
          // proyecto para nada (menor de la ronda 16, medido)
          Session.AbreEn(Client, Cand.Path);
          OpenedFiles.Add(Cand.Path.ToLower, True);
          Inc(FilesOpened);
        end;
        Resp := Client.Definition(TLspClient.PathToUri(Cand.Path),
          Cand.Line, Cand.Col + 1);
        try
          var Resuelto := DefinitionLocation(Resp, CandUri, CandLine);
          var EsElMismo := Resuelto and SameText(CandUri, TargetUri) and
            ((CandLine = TargetLine) or (CandLine = TargetTwin));
          // El parentesco: el candidato resolvio a OTRA linea, pero a un
          // metodo del mismo nombre en una clase de la misma familia. Eso no
          // es un homonimo: es el mismo metodo a otra altura de la jerarquia.
          var Pariente := False;
          if Resuelto and not EsElMismo and (ClaseObjetivo <> '') then
          begin
            var CandPath := TLspClient.UriToPath(CandUri);
            var CandLines: TStringList;
            if not Textos.TryGetValue(CandPath.ToLower, CandLines) then
            begin
              CandLines := TStringList.Create;
              try
                CandLines.Text := CodigoPascal(TLspClient.LoadSourceText(CandPath));
              except
              end;
              Textos.Add(CandPath.ToLower, CandLines);
            end;
            var CandU: TUnidadPas;
            if not Unidades.TryGetValue(CandPath.ToLower, CandU) then
            begin
              CandU := LeeFuentePascal(CandLines.Text);
              Unidades.Add(CandPath.ToLower, CandU);
            end;
            Pariente := MismaFamilia(Herencia, ClaseObjetivo,
              ClaseDeMetodo(CandLines, CandU, CandLine, Ident));
          end;
          if EsElMismo then
            Confirmed.Add(CandidateJson(Cand))
          else if Pariente then
          begin
            var PObj := CandidateJson(Cand);
            PObj.AddPair('via', 'override');
            PObj.AddPair('resolvedTo', TLspClient.UriToPath(CandUri));
            PObj.AddPair('resolvedLine', TJSONNumber.Create(CandLine));
            Confirmed.Add(PObj);
            Familia := True;
          end
          else if CandUri = '' then
            Unverified.Add(CandidateJson(Cand))
          else
          begin
            Inc(Rejected);
            // A "homonym" is only a homonym if the engine really resolved it
            // somewhere else. When the file belongs to ANOTHER project, the
            // engine resolves it against the wrong settings and the real
            // reference lands here - which is how a rename came back
            // applicable while leaving a caller broken (measured 2026-08-25).
            // Keep them, with where they resolved instead, so the caller can
            // look rather than trust a count.
            // Only when it resolves to ANOTHER unit. A symbol declared in
            // the interface and implemented below resolves to two different
            // lines of its own file, and treating that as a lookalike made
            // every single rename inapplicable (caught by the battery).
            // Every rejection is LISTED, never just counted. The tool's own
            // description promises leftovers are never silently dropped, and
            // a bare count is precisely what hid the bug above from view
            // (rejectedHomonyms: 3, rejected: []). Same-file leftovers are
            // listed too now: with the decl/impl pair accepted above, one
            // that still lands here really is another symbol, and the caller
            // is the one who should decide whether that matters.
            // ...pero LISTADOS, no VOLCADOS. Con un identificador corto (una
            // variable local "F") salen cientos: 212 homonimos con su ruta y
            // su texto entero hicieron una respuesta de 78 KB que el cliente
            // MCP rechazo ENTERA por pasarse de tokens - o sea que el agente
            // no vio ni las 8 referencias buenas. La tool promete "Bounded
            // work"; el trabajo si estaba acotado, la respuesta no. Medido el
            // 2026-09-20 por un agente auditor. Se listan los primeros y se
            // dice cuantos hay: el recuento completo sigue en
            // rejectedHomonyms.
            if RejectedArr.Count < 25 then
            begin
              var RObj := CandidateJson(Cand);
              RObj.AddPair('resolvedTo', TLspClient.UriToPath(CandUri));
              RObj.AddPair('resolvedLine', TJSONNumber.Create(CandLine));
              RObj.AddPair('resolvedLine1', TJSONNumber.Create(CandLine + 1));
              RejectedArr.AddElement(RObj);
            end;
          end;
        finally
          Resp.Free;
        end;
      end;

      Result := TJSONObject.Create;
      Result.AddPair('identifier', Ident);
      Entry := TJSONObject.Create;
      Result.AddPair('definition', Entry);
      Entry.AddPair('path', TLspClient.UriToPath(TargetUri));
      Entry.AddPair('line', TJSONNumber.Create(TargetLine));
      Entry.AddPair('line1', TJSONNumber.Create(TargetLine + 1));
      Result.AddPair('confirmed', Confirmed);
      Result.AddPair('unverified', Unverified);
      // Menciones: el nombre esta escrito ahi, pero en prosa. No son
      // referencias y NO bloquean un rename - que es exactamente lo que
      // hacian mientras caian en "unverified". Se listan igual, acotadas:
      // quien renombra suele querer repasar los comentarios a mano, y el
      // "nunca se tiran en silencio" que promete la tool vale tambien aqui.
      Result.AddPair('mentionsCount', TJSONNumber.Create(Menciones.Count));
      if Menciones.Count > 0 then
      begin
        var MenArr := TJSONArray.Create;
        Result.AddPair('mentions', MenArr);
        for var Men in Menciones do
        begin
          if MenArr.Count >= 25 then
            Break;
          MenArr.AddElement(CandidateJson(Men));
        end;
        Result.AddPair('mentionsNote', MsgFmt(SN_REFS_MENTIONS_FMT,
          [Menciones.Count, MenArr.Count]));
      end;
      if Familia then
        Result.AddPair('familyNote', MsgText(SN_REFS_FAMILY_NOTE));
      Result.AddPair('rejectedHomonyms', TJSONNumber.Create(Rejected));
      Result.AddPair('rejected', RejectedArr);
      if Rejected > RejectedArr.Count then
        Result.AddPair('rejectedNote', MsgFmt(SN_REFS_REJECTED_CAP_FMT,
          [RejectedArr.Count, Rejected]));
      Result.AddPair('filesScanned', TJSONNumber.Create(Scanned));
      Result.AddPair('candidates', TJSONNumber.Create(Candidates.Count));
      // WHERE we looked. "filesScanned: 4" says how many, never which, and a
      // caller cannot tell a complete answer from one that stopped at the
      // project's own folder (field round 11).
      var ScopeArr := TJSONArray.Create;
      Result.AddPair('scope', ScopeArr);
      for var SD in ScopeDirs do
        ScopeArr.Add(SD);
    finally
      OpenedFiles.Free;
    end;
  finally
    Candidates.Free;
    Menciones.Free;
    AllFiles.Free;
    Herencia.Free;
    Unidades.Free;
    Textos.Free;
  end;
end;

end.
