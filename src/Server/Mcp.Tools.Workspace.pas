unit Mcp.Tools.Workspace;

{ Remote-work toolset: delphi_search, delphi_list, delphi_git. Together with
  delphi_read/delphi_edit/delphi_build they give an agent on ANOTHER machine
  (e.g. Linux) full control of the Delphi projects living on this Windows box
  - no file share, no shell access. Paths in results are 1-based lines to
  match delphi_read numbering. }

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Math,
  System.StrUtils,
  System.NetEncoding,
  System.Zip,
  System.Generics.Collections,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Texts,   // SchemaDescription texts live there, and attributes are interface-level
  Lsp.Attributes;  // [RutaDelServidor]: que parametro es una ruta NUESTRA

type
  TDelphiSearchParams = class
  private
    FRoot: string;
    FQuery: string;
    FMaxResults: Integer;
    FOffset: Integer;
    FWholeWord: Boolean;
    FPattern: string;
    FRegex: Boolean;
  public
    [SchemaDescription(SP_WS_ROOT)]
    [Required]
    [RutaDelServidor]
    property Root: string read FRoot write FRoot;
    [SchemaDescription(SP_WS_QUERY)]
    [Required]
    property Query: string read FQuery write FQuery;
    [SchemaDescription(SP_WS_MAXRESULTS)]
    [SchemaDefault('100')]
    property MaxResults: Integer read FMaxResults write FMaxResults;
    [SchemaDescription(SP_WS_OFFSET)]
    [SchemaDefault('0')]
    property Offset: Integer read FOffset write FOffset;
    [SchemaDescription(SP_WS_WHOLEWORD)]
    property WholeWord: Boolean read FWholeWord write FWholeWord;
    [SchemaDescription(SP_WS_PATTERN)]
    property Pattern: string read FPattern write FPattern;
    [SchemaDescription(SP_WS_REGEX)]
    property Regex: Boolean read FRegex write FRegex;
  end;

  TDelphiListParams = class
  private
    FRoot: string;
    FPattern: string;
    FDirs: Boolean;
    FIncludeTrash: Boolean;
    FMaxResults: Integer;
    FOffset: Integer;
  public
    [SchemaDescription(SP_WS_ROOT_2)]
    [Required]
    [RutaDelServidor]
    property Root: string read FRoot write FRoot;
    [SchemaDescription(SP_WS_PATTERN_2)]
    property Pattern: string read FPattern write FPattern;
    [SchemaDescription(SP_WS_DIRS)]
    property Dirs: Boolean read FDirs write FDirs;
    [SchemaDescription(SP_WS_INCLUDETRASH)]
    property IncludeTrash: Boolean read FIncludeTrash write FIncludeTrash;
    [SchemaDescription(SP_WS_LIST_MAXRESULTS)]
    [SchemaDefault('500')]
    property MaxResults: Integer read FMaxResults write FMaxResults;
    [SchemaDescription(SP_WS_LIST_OFFSET)]
    [SchemaDefault('0')]
    property Offset: Integer read FOffset write FOffset;
  end;

  TDelphiProjectsParams = class
  private
    FRoot: string;
    FName: string;
    FMaxResults: Integer;
    FOffset: Integer;
  public
    [SchemaDescription(SP_WS_ROOT_3)]
    [RutaDelServidor]
    property Root: string read FRoot write FRoot;
    [SchemaDescription(SP_WS_NAME)]
    property Name: string read FName write FName;
    [SchemaDescription(SP_WS_MAXRESULTS_2)]
    [SchemaDefault('50')]
    property MaxResults: Integer read FMaxResults write FMaxResults;
    [SchemaDescription(SP_WS_OFFSET_2)]
    [SchemaDefault('0')]
    property Offset: Integer read FOffset write FOffset;
  end;

  TDelphiGitParams = class
  private
    FRepo: string;
    FCommand: string;
    FArgs: string;
    FCreate: Boolean;
    FMessage: string;
    FPath: string;
    FRef: string;
    FOffset: Integer;
  public
    [SchemaDescription(SP_WS_REPO)]
    [Required]
    [RutaDelServidor]
    property Repo: string read FRepo write FRepo;
    [SchemaDescription(SP_WS_COMMAND)]
    [Required]
    property Command: string read FCommand write FCommand;
    [SchemaDescription(SP_WS_ARGS)]
    property Args: string read FArgs write FArgs;
    [SchemaDescription(SP_WS_CREATE)]
    property Create: Boolean read FCreate write FCreate;
    [SchemaDescription(SP_WS_MESSAGE)]
    property Message: string read FMessage write FMessage;
    [SchemaDescription(SP_WS_PATH)]
    [RutaDelServidor]
    property Path: string read FPath write FPath;
    [SchemaDescription(SP_WS_REF)]
    property Ref: string read FRef write FRef;
    [SchemaDescription(SP_WS_OFFSET_GIT)]
    property Offset: Integer read FOffset write FOffset;
  end;

  TDelphiSearchTool = class(TMCPToolBase<TDelphiSearchParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiSearchParams): string; override;
  public
    constructor Create; override;
  end;

  TDelphiListTool = class(TMCPToolBase<TDelphiListParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiListParams): string; override;
  public
    constructor Create; override;
  end;

  TDelphiGitTool = class(TMCPToolBase<TDelphiGitParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiGitParams): string; override;
  public
    constructor Create; override;
  end;

  TDelphiProjectsTool = class(TMCPToolBase<TDelphiProjectsParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiProjectsParams): string; override;
  public
    constructor Create; override;
  end;

  TDelphiInstallsParams = class
  end;

  TDelphiInstallsTool = class(TMCPToolBase<TDelphiInstallsParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiInstallsParams): string; override;
  public
    constructor Create; override;
  end;

  TDelphiWorkspaceParams = class
  end;

  TDelphiWorkspaceTool = class(TMCPToolBase<TDelphiWorkspaceParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiWorkspaceParams): string; override;
  public
    constructor Create; override;
  end;

  TDelphiFetchParams = class
  private
    FPath: string;
    FOffset: Integer;
    FMaxBytes: Integer;
  public
    [SchemaDescription(SP_WS_PATH_2)]
    [Required]
    [RutaDelServidor]
    property Path: string read FPath write FPath;
    [SchemaDescription(SP_WS_OFFSET_3)]
    property Offset: Integer read FOffset write FOffset;
    [SchemaDescription(SP_FETCH_MAXBYTES)]
    property MaxBytes: Integer read FMaxBytes write FMaxBytes;
  end;

  TDelphiFetchTool = class(TMCPToolBase<TDelphiFetchParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiFetchParams): string; override;
  public
    constructor Create; override;
  end;

  TDelphiUploadParams = class
  private
    FPath: string;
    FChunkBase64: string;
    FOffset: Integer;
    FSha256: string;
    FChunkSha256: string;
  public
    [SchemaDescription(SP_WS_PATH_3)]
    [Required]
    [RutaDelServidor]
    property Path: string read FPath write FPath;
    [SchemaDescription(SP_WS_CHUNKBASE64)]
    [Required]
    property ChunkBase64: string read FChunkBase64 write FChunkBase64;
    [SchemaDescription(SP_WS_OFFSET_4)]
    property Offset: Integer read FOffset write FOffset;
    [SchemaDescription(SP_WS_SHA256)]
    property Sha256: string read FSha256 write FSha256;
    [SchemaDescription(SP_WS_CHUNKSHA256)]
    property ChunkSha256: string read FChunkSha256 write FChunkSha256;
  end;

  TDelphiUploadTool = class(TMCPToolBase<TDelphiUploadParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiUploadParams): string; override;
  public
    constructor Create; override;
  end;

  TDelphiPackageParams = class
  private
    FDir: string;
    FOutFile: string;
  public
    [Required]
    [SchemaDescription(SP_WS_DIR)]
    [RutaDelServidor]
    property Dir: string read FDir write FDir;
    [SchemaDescription(SP_WS_OUTFILE)]
    [RutaDelServidor]
    property OutFile: string read FOutFile write FOutFile;
  end;

  TDelphiPackageTool = class(TMCPToolBase<TDelphiPackageParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiPackageParams): string; override;
  public
    constructor Create; override;
  end;

var
  { Como arranco ESTE proceso: lo fija el .dpr en la rama que elige (un solo
    lector de la linea de ordenes) y lo cuenta delphi_workspace. }
  GModoServidor: string = 'console';     // console | service | tray
  GTransporteServidor: string = 'stdio'; // stdio | http

{ En que MAQUINA corre este proceso: lo cuenta delphi_workspace ("host") y
  Lsp.Host lo pasa al vendor para serverInfo. Un solo lector para los dos. }
function NombreDeMaquina: string;

implementation

uses
  System.RegularExpressions,
  System.DateUtils,
  Winapi.Windows,
  MCPServer.Registration,
  MCPServer.Logger,
  Lsp.Client,
  Lsp.Discovery,
  Lsp.References,
  Lsp.Listas, // TPagina, TPorCarpeta y el organizador de listas de ficheros
  Lsp.BuildRunner,
  Lsp.Guard,
  Lsp.Patch,
  Lsp.ShaCache,
  Lsp.Base64,     // BytesToBase64 / Base64ToBytes: el codificador de la casa
  Lsp.Dproj,      // RutasDeBusqueda: el search path de un .dproj, resuelto
  Lsp.Files,
  Mcp.Tools.Messages,
  Lsp.DesignerBin,
  Lsp.NetDrives, // DirectedMessagesPending, para la ficha del servidor
  Lsp.Pascal,
  Lsp.Regex, // TExprDelAgente: la expresion de delphi_search regex=true
  Lsp.Sandbox;

// la tool git va por delante de sus compositores
function GitExito(const ACuerpo: string; AExit: Integer): string; forward;
function GitFallo(ACodigo: Cardinal; const ASalida: string): string; forward;

const
  DEFAULT_MASKS: array [0 .. 7] of string =
    ('*.pas', '*.dpr', '*.dpk', '*.inc', '*.dfm', '*.fmx', '*.dproj', '*.groupproj');
  // Entradas de un delphi_list: el recorte y la nota que lo cuenta, el mismo
  // numero (la nota lo llevaba copiado a mano)
  LIST_CAP = 500;

// WalkFiles vive en Lsp.Guard: la misma lectura para todas las tools.

{ TDelphiSearchTool }

constructor TDelphiSearchTool.Create;
begin
  inherited;
  FName := 'delphi_search';
  FDescription := SD_WS_SEARCH;
end;

function RelToRoot(const AFull, ARoot: string): string; forward;

const
  // lo que una busqueda lee de un fichero: uno mayor (un volcado, un log
  // dentro del arbol) se salta y se dice; se leia entero en memoria (muro de
  // la lista del 4-oct-2026)
  TOPE_BUSQUEDA_MB = 8;

function TDelphiSearchTool.ExecuteWithParams(const Params: TDelphiSearchParams): string;
var
  Return: TJSONObject;
  Hits: TJSONArray;
  I, P, Len, ScanFrom, FilesScanned: Integer;
  F, Text, Q, LineText, GrupoDe: string;
  Lines: TArray<string>;
  Mask: string;
  Entry, Grupo: TJSONObject;
begin
  Result := ReadPathDenied(Params.Root); // searching may enter the library zone
  if Result <> '' then
    Exit;
  // A single FILE as root: "find X in this .dproj" used to cost 3-6
  // delphi_read calls of 400 lines (field 2026-08-22, a 1909-line .dproj).
  var SingleFile := TFile.Exists(Params.Root) and not TDirectory.Exists(Params.Root);
  if not SingleFile and not TDirectory.Exists(Params.Root) then
    Exit(MsgFmt(SR_WS_DIR_NOT_FOUND_FMT, [Params.Root]));
  if Params.Query = '' then
    Exit(MsgText(SR_WS_EMPTY_QUERY));
  // linea a linea: una consulta con un salto no casaria con nada
  if Params.Query.Contains(#10) or Params.Query.Contains(#13) then
    Exit(MsgText(SR_SEARCH_VARIAS_LINEAS));
  // la pagina: 100 por defecto, 500 como mucho (TPagina, la de las listas)
  var Pag := PaginaDe(Params.Offset, Params.MaxResults, 100, 500);
  Q := Params.Query.ToLower;
  // regex=true: la consulta es una expresion (PCRE, sin distinguir
  // mayusculas, como la literal), que se aplica linea a linea; una que no
  // compila se dice antes de leer nada. Es del AGENTE: Lsp.Regex.
  // TExprDelAgente, que dice tambien cuando el motor se rinde (TRegEx lo
  // tomaba por "no casa" y la busqueda daba cero en silencio)
  var Expr: TExprDelAgente := nil;
  if Params.Regex then
  begin
    var ErrRx: string;
    Expr := TExprDelAgente.Create(Params.Query, ErrRx);
    if ErrRx <> '' then
    begin
      Expr.Free;
      Exit(MsgFmt(SR_SEARCH_REGEX_INVALID_FMT, [ErrRx]));
    end;
  end;


  Return := TJSONObject.Create;
  // los aciertos AGRUPADOS por fichero: la ruta iba repetida en cada uno
  // (revisor de tokens, 4-oct-2026: el mayor ahorro de una sesion tipica);
  // y los ficheros por carpeta, con el organizador de todas las listas
  // (1.15.0). Se libera en el finally: un Exit a media busqueda -SEARCH-005-
  // no la deja suelta.
  var Lista := TListaDeFicheros.Create;
  GrupoDe := '';
  Grupo := nil;
  Hits := nil;
  FilesScanned := 0;
  try
    var Masks: TArray<string> := [];
    for Mask in DEFAULT_MASKS do
      Masks := Masks + [Mask];
    if Params.Pattern.Trim <> '' then
    begin
      // una mascara de nombre de fichero: letras de cualquier alfabeto (hay
      // units acentuadas: UArbol con su tilde*.pas se negaba), digitos y * ? . - _
      if not TRegEx.IsMatch(Params.Pattern.Trim, '\A(?:' + PATRON_CAR_IDENT + '|[*?.\-])+\z') then
        Exit(MsgText(SR_WS_PATTERN_DEBE_SER_MASCARA));
      Masks := [Params.Pattern.Trim];
    end;
    var Targets: TArray<string> := [];
    if SingleFile then
      Targets := [Params.Root]
    else
      Targets := WalkFiles(Params.Root, Masks); // un paseo, cada fichero una vez
    // La MISMA regla que delphi_list, su gemela: los artefactos se filtran
    // sobre la ruta RELATIVA a la raiz, y si quien llama nombro una carpeta
    // de compilacion, es que la quiere ver. Aqui se filtraba la ABSOLUTA y
    // sin consentimiento: buscar en ...\Win64\Release (o en una jaula que
    // cuelga de una carpeta llamada Debug) devolvia cero, en silencio
    // (auditoria 2026-09-21).
    var RaizEnArtefactos := (not SingleFile) and
      SkipIdeArtifacts(IncludeTrailingPathDelimiter(Params.Root));
    // Y lo saltado se CUENTA, como en delphi_list: esconder sin decirlo
    // contestaba "total 0" con medio arbol sin mirar (revision de
    // baterias, 26-sep-2026).
    var Ocultos := Default(THiddenCount);
    var Ilegibles: TArray<string> := [];
    var Grandes: TArray<string> := [];
    for F in Targets do
      begin
        if not SingleFile and InVault(F) then
          Continue;
        if not SingleFile and not RaizEnArtefactos then
        begin
          var Motivo := SkipReason(RelToRoot(F, Params.Root), False);
          if Motivo <> '' then
          begin
            Ocultos.Add(Motivo);
            Continue;
          end;
        end;
        // UN fichero que no se deja leer no tumba la busqueda de toda la
        // carpeta: se salta y se dice (sexta revision). En la de UN
        // fichero, el fallo es la respuesta.
        try
          // el tope, ANTES de leerlo: uno nombrado a solas se dice; en una
          // carpeta, se salta y se cuenta
          var Tam := TFile.GetSize(F);
          if Tam > Int64(TOPE_BUSQUEDA_MB) * 1024 * 1024 then
          begin
            if SingleFile then
              Exit(MsgFmt(SR_SEARCH_FICHERO_GRANDE_FMT,
                [MaskDriveText('', F), Tam div (1024 * 1024), TOPE_BUSQUEDA_MB]));
            Grandes := Grandes + [MaskDriveText('', F)];
            Continue;
          end;
          Text := TLspClient.LoadSourceText(F);
        except
          if SingleFile then
            raise;
          Ilegibles := Ilegibles + [MaskDriveText('', F)];
          Continue;
        end;
        Inc(FilesScanned);
        if not Params.Regex and not Text.ToLower.Contains(Q) then
          Continue;
        Lines := LineasDelTexto(Text); // numeradas como delphi_read (un CR suelto es salto)
        for I := 0 to High(Lines) do
        begin
          LineText := Lines[I];
          ScanFrom := 1;
          repeat
            if Params.Regex then
            begin
              // una expresion que se dispara (backtracking) agota el limite de
              // pasos del motor: se dice donde, en vez de un cero falso
              case Expr.Busca(LineText, ScanFrom, P, Len) of
                rbNoCasa:
                  Break;
                rbSeRinde:
                  Exit(MsgFmt(SR_SEARCH_REGEX_CARA_FMT, [I + 1, MaskDriveText('', F)]));
              end;
            end
            else
            begin
              P := Pos(Q, LineText.ToLower, ScanFrom);
              Len := Length(Q);
            end;
            if P = 0 then
              Break;
            // la palabra entera es la de EL identificador (Lsp.Pascal): con
            // A-Z a mano, el trozo de un nombre que sigue con una enye o un
            // acento contaba como palabra entera (censo del 4-oct-2026)
            if (not Params.WholeWord) or
               (((P = 1) or not EsCaracterDeIdent(LineText[P - 1])) and
                ((P + Len > Length(LineText)) or
                 not EsCaracterDeIdent(LineText[P + Len]))) then
            begin
              if Pag.Entra then
              begin
                // el grupo de ESTE fichero: los aciertos de uno van seguidos
                if (Grupo = nil) or (GrupoDe <> F) then
                begin
                  GrupoDe := F;
                  // This tool's answer is exempt from the blanket outbound
                  // filter (the delphi_search note in MaskDriveText): the
                  // organizer masks the folder it writes. Any OTHER path field
                  // added from now on MUST go through MaskDriveText too, or
                  // a real drive letter walks out.
                  Grupo := Lista.Add(F);
                  Hits := TJSONArray.Create;
                  Grupo.AddPair('hits', Hits);
                end;
                Entry := TJSONObject.Create;
                Hits.Add(Entry);
                Entry.AddPair('line', TJSONNumber.Create(I + 1));
                // The LSP tools want a 0-based line:character, and the hit
                // used to arrive Trim'ed - so the column could not be derived
                // and every navigation cost an extra delphi_read just to
                // count spaces (field 2026-08-25). Now the line travels
                // VERBATIM and the position of the match comes with it.
                Entry.AddPair('line0', TJSONNumber.Create(I));
                Entry.AddPair('character0', TJSONNumber.Create(P - 1));
                Entry.AddPair('text', LineText);
              end;
              Break; // one hit per line is enough
            end;
            ScanFrom := P + System.Math.Max(Len, 1); // (una coincidencia vacia avanza igual)
          until False;
        end;
      end;
    Pag.Report(Return);
    Return.AddPair('filesScanned', TJSONNumber.Create(FilesScanned));
    if Length(Ilegibles) > 0 then
      Return.AddPair('unreadableNote', MsgFmt(SN_SEARCH_ILEGIBLES_FMT,
        [Length(Ilegibles), string.Join(', ', Copy(Ilegibles, 0, 5))]));
    if Length(Grandes) > 0 then
      Return.AddPair('bigFilesNote', MsgFmt(SN_SEARCH_GRANDES_FMT,
        [Length(Grandes), TOPE_BUSQUEDA_MB, string.Join(', ', Copy(Grandes, 0, 5))]));
    // un "pattern" que no casa con ningun fichero: "total 0" se leia como
    // "el texto no esta" (delphi_list ya lo decia; verificacion de la
    // tercera ronda)
    // ...y los que casaron pero no se dejaron leer (SEARCH-003) SI casaron: la
    // mascara estaba bien (septima revision)
    if (FilesScanned = 0) and (Length(Ilegibles) = 0) and
       (Params.Pattern.Trim <> '') and not SingleFile then
      Return.AddPair('maskNote', MsgFmt(SN_SEARCH_MASK_NO_MATCH_FMT, [Params.Pattern.Trim]));
    Ocultos.Report(Return);
    // la lista, detras de los contadores y las notas, como iba
    Lista.Cuelga(Return);
    Result := Return.ToJSON;
  finally
    Lista.Free;
    Return.Free;
    Expr.Free;
  end;
end;

{ TDelphiListTool }

constructor TDelphiListTool.Create;
begin
  inherited;
  FName := 'delphi_list';
  FDescription := SD_WS_LIST;
end;

{ Path relative to the listing root, in the '\seg\' shape SkipIdeArtifacts
  expects. Artifact filtering for delphi_list happens on THIS, not on the
  absolute path: naming a build-output folder as root is explicit consent to
  see inside it (field: an agent chased a freshly built exe for 20 calls
  because Compiled\Win32\Release answered empty), while listings from above
  still hide build output - and now say how much they hid. }
function RelToRoot(const AFull, ARoot: string): string;
var
  R: string;
begin
  R := IncludeTrailingPathDelimiter(ARoot);
  if AFull.ToLower.StartsWith(R.ToLower) then
    Result := '\' + Copy(AFull, Length(R) + 1, MaxInt)
  else
    Result := AFull;
end;

function TDelphiListTool.ExecuteWithParams(const Params: TDelphiListParams): string;
var
  Return: TJSONObject;
  F, Mask, Root, Reason: string;
  Masks: TArray<string>;
  Entry: TJSONObject;
  ShownTrash, ShownMarcas: Integer;
  Ocultos: THiddenCount;
  RootInArtifacts: Boolean;
begin
  Result := ReadPathDenied(Params.Root); // listing may enter the library zone
  if Result <> '' then
    Exit;
  // Canonicalize before walking: otherwise a root carrying "..\" segments is
  // echoed literally in every returned path (field round 4, R4-C).
  try
    Root := TPath.GetFullPath(Params.Root);
  except
    Root := Params.Root;
  end;
  if not TDirectory.Exists(Root) then
  begin
    // "No esta" y "no es una carpeta" no son lo mismo, y contestar la primera
    // cuando pasa la segunda manda al agente a buscar un fichero que tiene
    // delante (medido 2026-09-20 sobre README.md).
    if TFile.Exists(Root) then
      Exit(MsgFmt(SR_LIST_IS_FILE_FMT, [Root]));
    Exit(MsgFmt(SR_WS_DIR_NOT_FOUND_FMT, [Root]));
  end;
  // Shell-style brace expansion is NOT a mask: *.{pas,dfm} matched nothing
  // silently (field 2026-08-22). Say so instead of returning an empty list.
  if Params.Pattern.Contains('{') or Params.Pattern.Contains('}') then
    Exit(MsgText(SR_WS_PATTERN_ADMITE_LLAVES_EXPANSION));

  if TFile.Exists(Root) then
    Exit(MsgFmt(SR_LIST_ROOT_IS_FILE_FMT, [TPath.GetFileName(Root)]));
  if Params.Dirs then
  begin
    Return := TJSONObject.Create;
    // la carpeta una vez y sus subcarpetas por su nombre (el organizador):
    // la raiz repetida en cada una era el 80% de la respuesta (6-oct-2026)
    var ListaDirs := TListaDeFicheros.Create('dirs');
    // por paginas, como su hermana delphi_search: cortaba en 500 y las de
    // detras no se alcanzaban
    var PagDirs := PaginaDe(Params.Offset, Params.MaxResults, LIST_CAP, LIST_CAP);
    Ocultos := Default(THiddenCount);
    try
      // A root already inside artifact territory was asked for by name:
      // hiding its Debug/Release children would recreate the trap.
      RootInArtifacts := SkipIdeArtifacts(IncludeTrailingPathDelimiter(Root));
      for F in TDirectory.GetDirectories(Root) do
      begin
        if InVault(F) then
          Continue;
        // These were skipped WITHOUT being counted, so a folder holding .git
        // and __delphi-patch answered "total: 1" and said nothing about the
        // other two (measured 2026-08-25). Silence is not the same as saying
        // there is nothing there.
        // El motivo lo pone SkipReason, el mismo que en el modo ficheros:
        // aqui habia tres reglas a mano y cada una contaba en otro cajon
        // (__delphi-temp como compilacion, __history como papelera, .vs
        // como git, Win64 en ninguno; revision de baterias, 26-sep-2026).
        var Nombre := TPath.GetFileName(F);
        Reason := SkipReason(RelToRoot(F, Root) + '\', Params.IncludeTrash);
        if RootInArtifacts and (Reason = SKIP_ARTIFACTS) and
           not Nombre.StartsWith('__') then
          Reason := '';
        // Explorador: las carpetas de otras herramientas (.vs, .github,
        // .idea) tampoco salen en este modo; la papelera, si se pidio
        // (__pycache__ es compilado: lo esconde SkipReason en los dos modos).
        if (Reason = '') and (Nombre.StartsWith('.') or Nombre.StartsWith('__')) and
           (SkipReason(RelToRoot(F, Root) + '\', False) <> SKIP_TRASH) then
          Reason := SKIP_FOLDERS;
        if Reason <> '' then
        begin
          Ocultos.Add(Reason);
          Continue;
        end;
        if PagDirs.Entra then
          ListaDirs.AddNombre(F);
      end;
      PagDirs.Report(Return);
      // el recorte se dice, como en el modo ficheros (callaba)
      if PagDirs.HayMas then
        Return.AddPair('shownNote', MsgFmt(SN_LIST_DIRS_CAPPED_FMT,
          [PagDirs.Mostrados, PagDirs.Total, PagDirs.Siguiente]));
      Ocultos.Report(Return);
      ListaDirs.Cuelga(Return);
      Result := Return.ToJSON;
    finally
      ListaDirs.Free;
      Return.Free;
    end;
    Exit;
  end;
  if Params.Pattern <> '' then
    Masks := Params.Pattern.Split([';'])
  else
  begin
    SetLength(Masks, Length(DEFAULT_MASKS));
    for var I := 0 to High(DEFAULT_MASKS) do
      Masks[I] := DEFAULT_MASKS[I];
  end;

  Return := TJSONObject.Create;
  // la carpeta una vez y debajo sus ficheros (el organizador): la ruta
  // repetida en cada entrada era el 42% de una pagina (6-oct-2026)
  var Lista := TListaDeFicheros.Create;
  // por paginas, y lo que no cabe dice DONDE esta (byFolder): las 500
  // primeras de la raiz de referencia de un ERP eran copias de backups\ y lo
  // vivo no se alcanzaba (Hermes, 5-oct-2026)
  var Pag := PaginaDe(Params.Offset, Params.MaxResults, LIST_CAP, LIST_CAP);
  var PorCarpeta := Default(TPorCarpeta);
  Ocultos := Default(THiddenCount);
  ShownTrash := 0;
  ShownMarcas := 0;
  RootInArtifacts := SkipIdeArtifacts(IncludeTrailingPathDelimiter(Root));
  try
    // Un paseo con todas las mascaras: cada fichero sale UNA vez aunque dos
    // mascaras casen con el ("*;*.pas") o la papelera lo vea dos veces
    var Limpias: TArray<string> := [];
    for Mask in Masks do
      if Mask.Trim <> '' then
        Limpias := Limpias + [Mask.Trim];
      for F in WalkFiles(Root, Limpias, Params.IncludeTrash) do
      begin
        // The vault is the vault_* tools' business, even when it sits inside a
        // root: listing its notes would invite edits behind its back.
        if InVault(F) then
          Continue;
        // The advice was "pass that folder as root", and it only worked for
        // the DEEPEST one: asking for Win64 still hid everything, because the
        // path relative to the root still said "\debug\". If the caller
        // named a build folder, the caller means it (measured 2026-08-25).
        if RootInArtifacts then
          Reason := ''
        else
          Reason := SkipReason(RelToRoot(F, Root), Params.IncludeTrash);
        if Reason <> '' then
        begin
          Ocultos.Add(Reason);
          Continue;
        end;
        var Entra := Pag.Entra;
        PorCarpeta.Add(F, Root);
        // Con includetrash la papelera entra en el listado y deja de contarse
        // como oculta; el lector sigue queriendo saber cuantas de las entradas
        // son copias y cuantas ficheros vivos (Hermes, 2026-09-22).
        // ...copias: la marca de dueno de una copia (.by) no es otra copia
        // (septima revision)
        if Params.IncludeTrash and (SkipReason(RelToRoot(F, Root), False) = SKIP_TRASH) then
          if EsMarcaDeDueno(F) then
            Inc(ShownMarcas)
          else
            Inc(ShownTrash);
        if Entra then
        begin
          Entry := Lista.Add(F);
          // Size/date can fail on paths past the classic length limit (the
          // Android NDK is full of them) - measured: one such file aborted
          // the whole listing. The entry still goes out, just without them.
          try
            Entry.AddPair('size', TJSONNumber.Create(TFile.GetSize(F)));
            Entry.AddPair('modified',
              FormatDateTime('yyyy-mm-dd hh:nn:ss', TFile.GetLastWriteTime(F)));
          except
            Entry.AddPair('note', MsgText(SN_WS_SIZE_DATE_UNAVAILABLE));
          end;
        end;
      end;
    Pag.Report(Return);
    if ShownTrash + ShownMarcas > 0 then
    begin
      Return.AddPair('shownTrash', TJSONNumber.Create(ShownTrash));
      // las marcas, en su campo tambien: solo estaban dentro del texto
      Return.AddPair('shownMarkers', TJSONNumber.Create(ShownMarcas));
      Return.AddPair('trashNote', MsgFmt(SN_LIST_SHOWN_TRASH_FMT,
        [Pag.Total, ShownTrash, ShownMarcas]));
    end;
    // Una sola nota de lo que falta: con mas de 500 salian DOS claves
    // "shownNote" en el mismo objeto (revision 27-sep-2026)
    if Pag.HayMas then
    begin
      Return.AddPair('shownNote', MsgFmt(SN_LIST_CAPPED_FMT,
        [Pag.Mostrados, Pag.Total, Pag.Siguiente]));
      PorCarpeta.Report(Return);
    end;
    // Say WHICH, because "42 hidden" plus the wrong reason sends the reader
    // hunting for build output that is not there (measured 2026-08-25).
    Ocultos.Report(Return);
    // Without "pattern" only Delphi files are listed. That is a filter, and a
    // filter nobody mentioned reads as "there is nothing else here".
    if Params.Pattern.Trim = '' then
      Return.AddPair('maskNote', MsgText(SN_LIST_DEFAULT_MASK))
    // ...y "no caso con nada" solo si no se escondio nada: con *.pyc los 125
    // de __pycache__ casaban, salian contados en LIST-003 y esta nota decia
    // a la vez que la mascara no habia casado (en vivo, 6-oct-2026)
    else if (Pag.Total = 0) and (Ocultos.Total = 0) then
    begin
      // Solo el primer nivel, que es barato y basta para probar que la
      // carpeta no esta vacia: recorrerla entera otra vez para dar una cifra
      // mas bonita seria pagar dos veces el paseo justo en el caso malo.
      var Cuantas := 0;
      try
        Cuantas := Length(TDirectory.GetFileSystemEntries(Root));
      except
        Cuantas := 0;
      end;
      if Cuantas > 0 then
        Return.AddPair('maskNote', MsgFmt(SN_LIST_MASK_NO_MATCH_FMT,
          [Params.Pattern.Trim, Cuantas]));
    end;
    Lista.Cuelga(Return);
    Result := Return.ToJSON;
  finally
    Lista.Free;
    Return.Free;
  end;
end;

{ TDelphiGitTool }

constructor TDelphiGitTool.Create;
begin
  inherited;
  FName := 'delphi_git';
  FDescription := SD_WS_GIT;
end;

{ Los argumentos LIBRES del usuario, recompuestos desde el argv que valida la
  puerta (TrocearArgs) con su inversa EnComillas: git.exe recibe EXACTAMENTE
  los tokens que GitArgDenied/GitRemoteDenied aprobaron, sin que la puerta
  tenga que adivinar como trocea el CRT de Windows la cadena cruda. Es la
  parte (a) del arreglo del 26-sep-2026: el ejecutor obliga a git a leer lo
  que leyo la puerta, en vez de pasar la cadena tal cual y confiar en que los
  dos parsers coincidan. }
function ArgvSeguro(const AArgs: string): string;
var
  Tok: string;
begin
  Result := '';
  for Tok in TrocearArgs(AArgs) do
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + EnComillas(Tok);
  end;
end;

{ True si los argumentos de un commit o un tag traen el MENSAJE (-m, -m<texto>,
  -am, --message, --message=): el mensaje va en "message", que llega a git por
  -F byte a byte, y los dos juntos acababan en el exit 129 de git sin un
  codigo nuestro (Hermes, validacion de la 1.16.0). }
function MensajeEnArgsGit(const AArgs: string): Boolean;
begin
  for var Tok in TrocearArgs(AArgs) do
    if Tok.StartsWith('-m') or SameText(Tok, '-am') or (Tok = '--message') or
       Tok.StartsWith('--message=') then
      Exit(True);
  Result := False;
end;

{ Las RUTAS de un comando de git que las lleva (stash push -- <rutas>,
  restore <rutas>): cada trozo desde ADesde es un fichero o carpeta DE ESTE
  repo, con su nombre tal cual (sin opciones ni comodines), y sale como
  :(literal)<relativa> entre comillas, listo para la linea de git. Con
  AEscribeFicheros cada ruta pasa por la puerta del escritor (stash push
  reescribe el fichero; restore --staged solo toca el indice). '' = bien;
  si no, la negativa con los textos de ESE comando (AComando: 'stash' o
  'restore'; cada texto sale por su helper, aqui dentro). Era el bucle de
  stash push y restore iba a ser su gemelo (1.7.6). ACarpetas: la carpeta de
  cada ruta (ella misma si es una carpeta), para quien tiene que soltar lo
  nuestro de ahi antes de que git la reescriba. }
function RutasDeGit(const ARepo, AArgs: string; const ATrozos: TArray<string>;
  ADesde: Integer; AEscribeFicheros: Boolean; const AComando: string;
  out ARutas: string; out ACarpetas: TArray<string>): string;
var
  Base, Ruta, Rel: string;
  I: Integer;
begin
  Result := '';
  ARutas := '';
  ACarpetas := nil;
  Base := IncludeTrailingPathDelimiter(TPath.GetFullPath(ARepo));
  for I := ADesde to High(ATrozos) do
  begin
    if (I = ADesde) and (ATrozos[I] = '--') then
      Continue;
    // Rutas, no opciones: -u, -k, -p, --worktree... cambian lo que se guarda
    // y lo que se toca, y ninguna hace falta.
    if ATrozos[I].StartsWith('-') or (ATrozos[I].Trim = '') then
      if SameText(AComando, 'restore') then
        Exit(MsgFmt(SR_GIT_RESTORE_ARGS_FMT, [AArgs.Trim]))
      else
        Exit(MsgFmt(SR_GIT_STASH_ARGS_FMT, [AArgs.Trim]));
    // Una ruta de ESTE repo, con su nombre tal cual: un comodin no es un
    // nombre en Windows, y lo que GetFullPath no entiende no es una ruta.
    Ruta := '';
    try
      if not (ATrozos[I].Contains('*') or ATrozos[I].Contains('?')) then
        Ruta := SinBarraFinal(TPath.GetFullPath(
          TPath.Combine(Base, ATrozos[I].Replace('/', '\'))));
    except
      Ruta := '';
    end;
    if (Ruta = '') or not StartsText(Base, IncludeTrailingPathDelimiter(Ruta)) then
      if SameText(AComando, 'restore') then
        Exit(MsgFmt(SR_GIT_RESTORE_RUTA_FMT, [ATrozos[I], ARepo]))
      else
        Exit(MsgFmt(SR_GIT_STASH_RUTA_FMT, [ATrozos[I], ARepo]));
    // Devolver un fichero a HEAD es ESCRIBIRLO: la pregunta de todo
    // escritor, por la ruta real de cada uno.
    if AEscribeFicheros then
    begin
      Result := EscrituraDenegada(Ruta);
      if Result <> '' then
        Exit;
    end;
    Rel := Ruta.Substring(Length(Base)).Replace('\', '/');
    if Rel = '' then
      Rel := '.'; // la carpeta del propio repo
    // :(literal): el nombre es el nombre, sin comodines ni magia.
    ARutas := ARutas + ' ' + EnComillas(':(literal)' + Rel);
    // la carpeta de la ruta, UNA vez cada una (dos ficheros de la misma
    // carpeta eran dos avisos, uno detras de otro)
    if not TDirectory.Exists(Ruta) then
      Ruta := ExtractFileDir(Ruta);
    if not MatchText(Ruta, ACarpetas) then
      ACarpetas := ACarpetas + [Ruta];
  end;
end;

{ LA LINEA de git, por UN compositor: git.exe, -C con la carpeta de la
  llamada - por el compositor de la casa (EnComillas), como todo argumento -,
  lo que lo fija (AFijado: --git-dir...) y el comando. Se componia a mano en
  cada sitio, con -C "%s": una carpeta acabada en barra invertida se comia
  la comilla de cierre y el resto de la linea entraba en el argumento de -C
  (medido en la 1.7.6: GIT-036, "cannot change to ..."; cuarta revision de
  la 1.7.7). }
function GitLinea(const ARepo, AFijado, AResto: string): string;
begin
  // La orden de red no hereda una recursion a remotos de submodulos sin juzgar.
  var Comando := PrimerTrozo(AResto, [' ']);
  var Resto := AResto;
  if MatchText(Comando, ['fetch', 'pull', 'push']) then
    Resto := Comando + ' --no-recurse-submodules' + Copy(AResto, Length(Comando) + 1, MaxInt);
  // Nunca ejecutar los hooks ni el monitor de un repo del workspace.
  // El directorio del servidor no admite escrituras de los clientes.
  // La regla general tambien manda en switch/restore y en los hijos de Git.
  Result := 'git.exe -c submodule.recurse=false -c core.fsmonitor=false ' +
    '-c commit.gpgsign=false -c tag.gpgsign=false -c core.hooksPath=' +
    EnComillas(ServerTempDir('git-hooks-off')) + ' -C ' +
    EnComillas(ARepo) + AFijado + ' ' + Resto;
end;

{ git, LANZADO por un solo sitio: la linea del compositor por el lanzador de
  la casa. Y el servidor SIN git lo dice aqui. CreateProcess no encuentra
  git.exe (error 2) y la llamada acababa en "[SYS-006 INTERNAL]
  ... CreateProcess failed (2)", que no dice ni que falta ni de quien es el
  arreglo (medido el 30-sep-2026 en una maquina sin git: init y status). Se
  decide con el fallo del lanzamiento DE VERDAD y no preguntando antes si
  git esta: quien lo busca por su cuenta no lo busca como CreateProcess.
  Sigue siendo una excepcion - quien pregunta para juzgar no toma un fallo
  por un "no hay" -, con el mensaje ya etiquetado. }
function GitCorre(const ARepo, AFijado, AResto: string; ATimeoutMs: Integer;
  out ACodigo: Cardinal): string;
begin
  try
    Result := RunCapturedIn(GitLinea(ARepo, AFijado, AResto), '', ATimeoutMs,
      ACodigo, EntornoSinConfiguracion(['GIT_TERMINAL_PROMPT=0', 'GCM_INTERACTIVE=never']));
  except
    on E: EOSError do
    begin
      // solo el 2, que es el medido: git se lanza por su nombre a secas y
      // un 3 no tiene de donde salir. Un git que ESTA y no arranca (5,
      // 193) no es "no hay git": sigue con el mensaje de siempre
      if E.ErrorCode = ERROR_FILE_NOT_FOUND then
        raise Exception.Create(MsgFmt(SR_GIT_NO_HAY_GIT_FMT, [E.ErrorCode]));
      raise;
    end;
  end;
end;

{ La configuracion LOCAL tambien manda programas aunque args sea limpio.
  Se lee sin includes: una inclusion del repo puede sacar la lectura de la
  jaula y esconder un filtro. La configuracion del servidor sigue siendo suya. }

function DireccionDeRemotoDenegada(const ACmd, ADireccion, ABase: string;
  out ACarpeta: string; out ANoEsta: Boolean): string; forward;

function RemotosDelRepo(const ARepo, AFijado: string;
  out ANombres: TArray<string>): Boolean; forward;

{ Medido con objetos LFS ausentes: estas ordenes materializan el arbol.
  Los filtros clean de add/commit/status no descargan objetos. }
function GitMaterializaArbol(const ACmd, AArgs: string): Boolean;
var
  Trozos: TArray<string>;
begin
  Result := MatchText(ACmd, ['clone', 'switch', 'merge', 'pull']);
  if ACmd = 'stash' then
  begin
    Trozos := TrocearArgs(AArgs);
    Result := Length(Trozos) = 0;
    if Length(Trozos) > 0 then
      Result := MatchText(Trozos[0], ['push', 'pop']);
  end
  else if ACmd = 'worktree' then
    Result := SameText(AArgs.Trim, 'add');
end;

function ConfiguracionGitDenegada(const ARepo, ARaiz: string;
  AExaminarLfs: Boolean; var AFijado: string): string;
var
  Salida, RutaLfs, Endpoint: string;
  Codigo: Cardinal;
  HayLfs, HayFuenteLfs: Boolean;
  NombresLfs: TArray<string>;

  function NombreDelEndpoint(const ALinea: string): string;
  var
    P: Integer;
  begin
    if ALinea.StartsWith('Endpoint (') then
    begin
      P := Pos(')', ALinea);
      if P > 11 then Exit(Copy(ALinea, 11, P - 11));
    end;
    if Length(NombresLfs) = 1 then Exit(NombresLfs[0]);
    Result := '(default: git-lfs)';
  end;

  function EndpointLfsDenegado(const ADireccion, ARemoto: string): string;
  var
    Carpeta, Base: string;
    NoEsta: Boolean;
  begin
    Base := ARaiz;
    if Base = '' then Base := ARepo;
    // El endpoint LFS se juzga con EL MISMO juez que un remoto: la red por
    // los hosts de GitRemotes, la carpeta por la puerta de carpetas del
    // workspace. Su valor nunca se muestra: la negativa nombra el remoto.
    if DireccionDeRemotoDenegada('lfs', ADireccion, Base, Carpeta, NoEsta) <> '' then
      Result := MsgFmt(SR_GIT_LFS_ENDPOINT_FMT, [ARemoto])
    else
      Result := '';
  end;

  function RevisaConfiguracion(const ATexto: string; ASoloLocal: Boolean): string;
  var
    Registro, Clave, Valor: string;
    Registros: TArray<string>;
    P: Integer;
  begin
    Result := '';
    Registros := ATexto.Split([#0], TStringSplitOptions.ExcludeEmpty);
    if Odd(Length(Registros)) then
      Exit(MsgText(SR_GIT_CONFIG_NO_VERIFICABLE));
    for var I := 0 to Length(Registros) div 2 - 1 do
    begin
      if IndexStr(Registros[I * 2],
        ['system', 'global', 'local', 'worktree', 'command']) < 0 then
        Exit(MsgText(SR_GIT_CONFIG_NO_VERIFICABLE));
      if not ASoloLocal or
         (IndexStr(Registros[I * 2], ['local', 'worktree']) >= 0) then
      begin
        Registro := Registros[I * 2 + 1];
        P := Pos(#10, Registro);
        // Una clave sin valor es un booleano true valido en la sintaxis de git.
        if P = 0 then
        begin
          Clave := LowerCase(Registro);
          Valor := 'true';
        end
        else
        begin
          Clave := LowerCase(Copy(Registro, 1, P - 1));
          Valor := Copy(Registro, P + 1, MaxInt);
        end;
        // El valor no sale en el rechazo: podria llevar credenciales.
        // LISTA BLANCA: claves conocidas sin programas ni rutas de lectura.
        // No se permiten familias enteras: gc.*, diff.* o remote.* crecen.
        var Permitida := MatchText(Clave, [
          'core.repositoryformatversion', 'core.filemode', 'core.bare',
          'core.logallrefupdates', 'core.symlinks', 'core.ignorecase',
          'core.autocrlf', 'core.eol', 'core.safecrlf', 'core.precomposeunicode',
          'core.protectntfs', 'core.protecthfs', 'core.worktree',
          'user.name', 'user.email', 'user.signingkey',
          'commit.gpgsign', 'tag.gpgsign', 'extensions.worktreeconfig',
          'extensions.objectformat', 'fetch.recursesubmodules',
          'push.recursesubmodules', 'submodule.recurse', 'push.default']);
        var Partes := Clave.Split(['.']);
        if Length(Partes) >= 3 then
        begin
          var Familia := Partes[0];
          var Campo := Partes[High(Partes)];
          if Familia = 'remote' then
            Permitida := MatchText(Campo, ['url', 'pushurl', 'fetch', 'push',
              'mirror', 'tagopt', 'prune', 'prunetags'])
          else if Familia = 'branch' then
            Permitida := MatchText(Campo, ['remote', 'pushremote', 'merge', 'description'])
          else if Familia = 'submodule' then
            Permitida := MatchText(Campo, ['url', 'path', 'active', 'ignore',
              'branch', 'fetchrecursesubmodules']);
        end;
        // LFS es el UNICO programa local admitido, con su comando estandar EXACTO.
        if Clave = 'filter.lfs.clean' then
          Permitida := Valor = 'git-lfs clean -- %f'
        else if Clave = 'filter.lfs.smudge' then
          Permitida := Valor = 'git-lfs smudge -- %f'
        else if Clave = 'filter.lfs.process' then
          Permitida := Valor = 'git-lfs filter-process'
        else if Clave = 'filter.lfs.required' then
          Permitida := SameText(Valor, 'true');
        // El endpoint pasa por EL juez de direcciones de los remotos.
        if MatchText(Clave, ['lfs.url', 'lfs.pushurl']) or
           ((Length(Partes) >= 3) and (Partes[0] = 'remote') and
            MatchText(Partes[High(Partes)], ['lfsurl', 'lfspushurl'])) then
        begin
          Permitida := True;
          if AExaminarLfs then
          begin
            var Remoto := NombreDelEndpoint('');
            if Partes[0] = 'remote' then
              Remoto := Copy(Clave, 8, Length(Clave) - 8 - Length(Partes[High(Partes)]));
            Result := EndpointLfsDenegado(Valor, Remoto);
            if Result <> '' then Exit;
          end;
        end
        else if Clave = 'lfs.repositoryformatversion' then
          Permitida := Valor = '0';
        if not Permitida then
          Exit(MsgFmt(SR_GIT_CONFIG_PROGRAMA_FMT, [Clave]));
      end;
    end;
  end;

  function RevisaFuenteLfs(const AArgumento: string): string;
  begin
    Salida := GitCorre(ARepo, AFijado,
      'config --no-includes --null --list --show-scope ' + AArgumento, 60000, Codigo);
    if Codigo <> 0 then
      Exit(MsgText(SR_GIT_CONFIG_NO_VERIFICABLE));
    Result := RevisaConfiguracion(Salida, False);
  end;

begin
  Result := '';
  Salida := GitCorre(ARepo, AFijado,
    'config --no-includes --null --list --show-scope', 60000, Codigo);
  if Codigo <> 0 then
    Exit(MsgText(SR_GIT_CONFIG_NO_VERIFICABLE));
  HayLfs := ContainsText(Salida, 'filter.lfs.');
  HayFuenteLfs := False;
  NombresLfs := nil;
  if AExaminarLfs and not RemotosDelRepo(ARepo, AFijado, NombresLfs) then
    Exit(MsgText(SR_GIT_CONFIG_NO_VERIFICABLE));
  Result := RevisaConfiguracion(Salida, True);
  if Result <> '' then Exit;
  if not AExaminarLfs then Exit;
  if ARaiz <> '' then
  begin
    RutaLfs := TPath.Combine(ARaiz, '.lfsconfig');
    if TFile.Exists(RutaLfs) then
    begin
      HayFuenteLfs := True;
      if (ReadPathDenied(RutaLfs) <> '') or EsEnlace(RutaLfs) then
        Exit(MsgFmt(SR_GIT_CONFIG_PROGRAMA_FMT, ['.lfsconfig']));
      Result := RevisaFuenteLfs('--file ' + EnComillas(RutaLfs));
      if Result <> '' then Exit;
    end;
    // Se midio la precedencia: fichero de trabajo, indice y despues HEAD.
    if not HayFuenteLfs then
    begin
      Salida := GitCorre(ARepo, AFijado, 'ls-files --stage -- .lfsconfig', 60000, Codigo);
      if Codigo <> 0 then Exit(MsgText(SR_GIT_CONFIG_NO_VERIFICABLE));
      if Salida.Trim <> '' then
      begin
        HayFuenteLfs := True;
        Result := RevisaFuenteLfs('--blob :.lfsconfig');
        if Result <> '' then Exit;
      end;
    end;
  end;
  // HEAD sirve tambien a un bare y a clone --no-checkout.
  if not HayFuenteLfs then
  begin
    Salida := GitCorre(ARepo, AFijado, 'rev-parse --verify --quiet HEAD', 60000, Codigo);
    if Codigo = 0 then
    begin
      Salida := GitCorre(ARepo, AFijado, 'ls-tree --name-only HEAD -- .lfsconfig', 60000, Codigo);
      if Codigo <> 0 then Exit(MsgText(SR_GIT_CONFIG_NO_VERIFICABLE));
      if Salida.Trim <> '' then
      begin
        Result := RevisaFuenteLfs('--blob HEAD:.lfsconfig');
        if Result <> '' then Exit;
      end;
    end
    else if Codigo <> 1 then
      Exit(MsgText(SR_GIT_CONFIG_NO_VERIFICABLE));
  end;
  if not HayLfs then Exit;
  // El programa estandar interpreta la precedencia; no hacemos otro lector.
  // Su salida (rutas y posibles credenciales) nunca se devuelve al agente.
  Salida := GitCorre(ARepo, AFijado, 'lfs env', 60000, Codigo);
  if Codigo <> 0 then Exit(MsgText(SR_GIT_CONFIG_NO_VERIFICABLE));
  Endpoint := '';
  for var Linea in Salida.Split([#10]) do
    if Linea.StartsWith('Endpoint') then
    begin
      var P := Pos('=', Linea);
      if P = 0 then Exit(MsgText(SR_GIT_CONFIG_NO_VERIFICABLE));
      var Direccion := Copy(Linea, P + 1, MaxInt).Trim;
      P := Pos(' (auth=', Direccion);
      if P > 0 then Direccion := Copy(Direccion, 1, P - 1);
      if Direccion = '' then Continue;
      Result := EndpointLfsDenegado(Direccion, NombreDelEndpoint(Linea));
      if Result <> '' then Exit;
      if Endpoint = '' then Endpoint := Direccion;
    end;
  // Fijarlo evita que un checkout cambie .lfsconfig durante la misma orden.
  // La precedencia de -c lfs.url se midio contra .lfsconfig y remote.*.lfsurl.
  AFijado := AFijado + ' -c ' + EnComillas('lfs.url=' + Endpoint) +
    ' -c ' + EnComillas('lfs.pushurl=' + Endpoint);
end;

{ DONDE VIVE el repo de ARepo (o de una carpeta de dentro), preguntado a git:
  su carpeta de git (AGitDir: la de ESTA copia de trabajo), la comun (AComun:
  la del repo principal, cuando ARepo es un worktree enlazado) y la raiz del
  arbol de trabajo (ARaiz: '' en un repo bare y dentro de la propia .git).
  Con barras de Windows. False si git no lo da: ASalida y ACodigo son
  entonces su respuesta ("not a git repository").

  Es la pregunta de la JAULA de git (la tool no deja trabajar en un repo que
  vive fuera de las raices) y la de quien suelta lo nuestro antes de que git
  reescriba el arbol; worktree add ya preguntaba la raiz.

  git contesta una carpeta por linea y su salida llega mezclada con la de
  errores: cuentan SOLO las lineas que son una carpeta que existe, en su
  orden. Un aviso de git con exit 0 hacia la raiz de varias lineas, y no
  casaba con nada, en silencio. }
function DondeViveElRepo(const ARepo: string; out AGitDir, AComun, ARaiz,
  ASalida: string; out ACodigo: Cardinal): Boolean;
var
  Linea, Ruta: string;
  Carpetas: TArray<string>;
begin
  AGitDir := '';
  AComun := '';
  ARaiz := '';
  ASalida := GitCorre(ARepo, '', 'rev-parse --absolute-git-dir ' +
    '--git-common-dir --show-toplevel', 60000, ACodigo);
  Carpetas := nil;
  for Linea in ASalida.Split([#10]) do
  begin
    Ruta := Linea.Trim.Replace('/', '\');
    if Ruta = '' then
      Continue;
    try
      // la comun llega RELATIVA a ARepo (..\..\.git) fuera de un worktree
      // enlazado (medido, git 2.53)
      Ruta := SinBarraFinal(
        TPath.GetFullPath(TPath.Combine(ARepo, Ruta)));
      // git contesta la ruta REAL: bajo una raiz declarada en una letra de
      // red es su UNC, y la puerta juzga por la forma declarada. Se le da
      // escrita asi (Lsp.Guard.FormaDeclarada; era GIT-041, 30-sep-2026)
      Ruta := FormaDeclarada(Ruta, ARepo);
      if TDirectory.Exists(Ruta) then
        Carpetas := Carpetas + [Ruta];
    except
      // lo que no es una ruta es un aviso de git
    end;
  end;
  // las tres, o las dos primeras cuando no hay arbol de trabajo (git sale
  // entonces con 128 y las ha dado igual)
  Result := (Length(Carpetas) = 2) or (Length(Carpetas) = 3);
  if not Result then
    Exit;
  AGitDir := Carpetas[0];
  AComun := Carpetas[1];
  if Length(Carpetas) = 3 then
    ARaiz := Carpetas[2];
end;

{ Las opciones que ADMITEN los comandos de red (fetch, pull, push). Una lista
  de lo que vale, no de lo que no: la opcion que no esta aqui no pasa. Las de
  la BAJADA para fetch y pull; pull lleva ademas --ff-only, siempre. }
const
  OPCIONES_DE_BAJADA = '--tags, --no-tags, --prune, --depth=<n>, --unshallow';
  OPCIONES_DE_FETCH = OPCIONES_DE_BAJADA + ', --all';
  OPCIONES_DE_PUSH = '--tags, -u, --set-upstream, --dry-run';

function OpcionDeRed(const ACmd, AOpcion: string): Boolean;
begin
  if ACmd = 'push' then
    Exit(IndexStr(AOpcion, ['--tags', '-u', '--set-upstream', '--dry-run']) >= 0);
  Result := (IndexStr(AOpcion, ['--tags', '--no-tags', '--prune', '--unshallow']) >= 0) or
    TRegEx.IsMatch(AOpcion, '^--depth=\d+$') or
    ((ACmd = 'pull') and (AOpcion = '--ff-only')) or
    ((ACmd = 'fetch') and (AOpcion = '--all'));
end;

{ Los trozos de args que no son opciones, en su orden: el remoto y lo que se
  trae o se envia. Por los trozos que lee la puerta (TrocearArgs). }
function TrozosSinGuion(const AArgs: string): TArray<string>;
var
  Trozo: string;
begin
  Result := nil;
  for Trozo in TrocearArgs(AArgs) do
    if not Trozo.StartsWith('-') then
      Result := Result + [Trozo];
end;

{ UN NOMBRE de rama, de tag o de commit, y nada mas que un nombre. Con
  AConRevision vale tambien la forma relativa (HEAD~3, v1^): para NOMBRAR
  una version que ya esta en el repo. }
function EsNombreDeRef(const ANombre: string; AConRevision: Boolean): Boolean;
begin
  if AConRevision then
    Result := TRegEx.IsMatch(ANombre, '^[A-Za-z0-9][A-Za-z0-9._/~^-]*$')
  else
    Result := TRegEx.IsMatch(ANombre, '^[A-Za-z0-9][A-Za-z0-9._/-]*$');
end;

{ LO QUE push ENVIA: los trozos sin guion de detras del remoto. push ANADE
  al remoto; lo que ya hay alli no se reescribe ni se borra por esta tool
  (David, 29-sep-2026: "nada de destruccion remota"). Una lista de lo que
  vale: cada trozo es un nombre (main, v1.7.7) o dos con dos puntos en medio
  (local:remoto) - a la izquierda una version que ya esta en el repo, a la
  derecha el nombre que tendra alli. True si hay uno que no (AMalo).

  Medido ese dia por la tool, con --force y --delete ya negados por su
  nombre: args="origin +main", con las historias divergidas, reescribia la
  rama del remoto, y args="origin :sobra" la borraba. }
function EnvioQueNoVale(const AArgs: string; out AMalo: string): Boolean;
var
  Trozos: TArray<string>;
  I, P: Integer;
  Vale: Boolean;
begin
  Result := False;
  AMalo := '';
  Trozos := TrozosSinGuion(AArgs);
  // (el primero es el remoto: lo juzga RemotoDenegado)
  for I := 1 to High(Trozos) do
  begin
    P := Trozos[I].IndexOf(':');
    if P >= 0 then
      Vale := EsNombreDeRef(Trozos[I].Substring(0, P), True) and
        EsNombreDeRef(Trozos[I].Substring(P + 1), False)
    else
      Vale := EsNombreDeRef(Trozos[I], False);
    if not Vale then
    begin
      AMalo := Trozos[I];
      Exit(True);
    end;
  end;
end;

{ Lo que git contesta a una pregunta, linea a linea (las que traen algo).
  False si git sale con error o no contesta en su plazo: quien pregunta para
  JUZGAR no toma un fallo por un "no hay" (cuarta revision de la 1.7.7: una
  pregunta que fallaba acababa en "se puede"). Por eso las preguntas se
  hacen de forma que "no hay" salga con 0: el que se queda sin plazo sale
  con 1, que es tambien con lo que git config dice que una clave no esta. }
function GitContesta(const ARepo, AFijado, APregunta: string;
  out ALineas: TArray<string>): Boolean;
var
  Salida, Linea: string;
  Codigo: Cardinal;
begin
  ALineas := nil;
  Salida := GitCorre(ARepo, AFijado, APregunta, 60000, Codigo);
  Result := Codigo = 0;
  if Result then
    for Linea in Salida.Split([#10]) do
      if Linea.Trim <> '' then
        ALineas := ALineas + [Linea.Trim];
end;

{ Una direccion de RED con su esquema. La lista es la de clone. }
function EsUrlDeRed(const ADireccion: string): Boolean;
begin
  Result := ADireccion.StartsWith('https://') or ADireccion.StartsWith('http://') or
    ADireccion.StartsWith('git://') or ADireccion.StartsWith('ssh://');
end;

{ QUE ES la direccion de un remoto. Una lista de lo que vale:
    drRed      una direccion de red: con su esquema (EsUrlDeRed) o en la
               forma corta de ssh, [usuario@]maquina:ruta
    drCarpeta  una carpeta (ACarpeta, tal como viene): su ruta, o
               file:///<unidad>:/<ruta> sin nada codificado, que es la forma
               de file:// que se lee igual aqui que en git
    drOtra     lo demas, que no se admite
  Medido el 29-sep-2026 por la tool (cuarta revision): git DECODIFICA los
  %xx de un file:// y aqui se leian tal cual - "mi%20repo.git" era para el
  juez una carpeta y para git otra -, y un remoto del repo con su direccion
  en file://C:/... (dos barras) pasaba por direccion de red: fetch traia la
  historia de una carpeta de fuera de las raices y push escribia en ella. }
type
  TDireccionDeRemoto = (drRed, drCarpeta, drOtra);

function ClaseDeDireccion(const ADireccion: string; out ACarpeta: string): TDireccionDeRemoto;
begin
  ACarpeta := '';
  if StartsText('file:', ADireccion) then
  begin
    if not TRegEx.IsMatch(ADireccion, '^file:///[A-Za-z]:/[^%]*$') then
      Exit(drOtra);
    ACarpeta := ADireccion.Substring(8);
    Exit(drCarpeta);
  end;
  if EsUrlDeRed(ADireccion) then
    Exit(drRed);
  if ADireccion.Contains('://') then
    Exit(drOtra);
  // la forma corta de ssh ([usuario@]maquina:ruta) la decide EL MISMO lector
  // de host que el resto (GitUrlHost con scp corto): un solo juez, sin regex
  // gemela aqui, y asi no discrepan (C:\ o C:/ no es una maquina).
  if GitUrlHost(ADireccion, True) <> '' then
    Exit(drRed);
  ACarpeta := ADireccion;
  Result := drCarpeta;
end;

{ Los remotos del repo, por su nombre. False si git no lo dice. }
function RemotosDelRepo(const ARepo, AFijado: string; out ANombres: TArray<string>): Boolean;
begin
  Result := GitContesta(ARepo, AFijado, 'remote', ANombres);
end;

{ UNA CARPETA que hace de remoto, juzgada: '' = se puede usar. La puerta de
  lectura para traer, la de escritura para enviar. Pasa la carpeta y pasa EL
  REPO QUE VIVE ALLI, con sus tres carpetas, como el de la llamada
  (DondeViveElRepo): una carpeta de dentro de las raices cuyo .git es un
  puntero - un worktree enlazado - sirve y escribe el repo al que apunta.
  Medido el 29-sep-2026 por la tool (cuarta revision): con un worktree de
  dentro de un repo de fuera por remoto, fetch traia la historia de fuera y
  push escribia una rama alli. }
function CarpetaDeRemotoDenegada(const ACmd, ACarpeta: string;
  out ANoEsta: Boolean): string;

  function Puerta(const ASitio: string): string;
  begin
    if ACmd = 'push' then
      Result := PathDenied(ASitio, True)
    else
      Result := ReadPathDenied(ASitio, True);
    if Result <> '' then
      Result := MsgFmt(SR_GIT_REMOTO_FUERA_FMT, [ACmd, ASitio,
        IfThen(ACmd = 'push', 'write', 'read')]);
  end;

var
  GitDir, Comun, Raiz, Salida, Sitio: string;
  Codigo: Cardinal;
begin
  ANoEsta := False;
  Result := Puerta(ACarpeta);
  if Result <> '' then
    Exit;
  // UNA CARPETA QUE ESTA. git abre mas cosas que una carpeta - el fichero
  // puntero de un worktree enlazado, o una ruta a la que el le pone el
  // sufijo .git -, y lo que abre entonces no es lo que aqui se ha mirado.
  // Medido el 29-sep-2026 por la tool (el revisor de este mismo arreglo):
  // con el remoto en "<worktree>\.git", que es un fichero, fetch traia la
  // historia del repo de fuera y push escribia una rama alli.
  // (de lo que NO esta, solo despues de la puerta: de una ruta de fuera no
  // se dice ni si existe)
  if not TDirectory.Exists(ACarpeta) then
  begin
    ANoEsta := True;
    Exit(MsgFmt(SR_GIT_REMOTO_ILEGIBLE_FMT, [ACmd, ACarpeta]));
  end;
  if not DondeViveElRepo(ACarpeta, GitDir, Comun, Raiz, Salida, Codigo) then
    Exit(GitFallo(Codigo, Salida));
  for Sitio in TArray<string>.Create(GitDir, Comun, Raiz) do
    if Sitio <> '' then
    begin
      Result := Puerta(Sitio);
      if Result <> '' then
        Exit;
    end;
end;

function DireccionDeRemotoDenegada(const ACmd, ADireccion, ABase: string;
  out ACarpeta: string; out ANoEsta: Boolean): string;
begin
  Result := '';
  ACarpeta := '';
  ANoEsta := False;
  case ClaseDeDireccion(ADireccion, ACarpeta) of
    drRed:
      begin
        if GitUrlHost(ADireccion, True) = '' then
          Exit(MsgFmt(SR_GIT_REMOTO_ILEGIBLE_FMT, [ACmd, ADireccion]));
        Result := GitRemoteDenied(EnComillas(ADireccion), True);
      end;
    drCarpeta:
      begin
        try
          ACarpeta := SinBarraFinal(TPath.GetFullPath(
            TPath.Combine(ABase, ACarpeta.Replace('/', '\'))));
        except
          Exit(MsgFmt(SR_GIT_REMOTO_ILEGIBLE_FMT, [ACmd, ADireccion]));
        end;
        Result := CarpetaDeRemotoDenegada(ACmd, ACarpeta, ANoEsta);
      end;
  else
    Result := MsgFmt(SR_GIT_REMOTO_ILEGIBLE_FMT, [ACmd, ADireccion]);
  end;
end;

{ EL REMOTO de una llamada de red, juzgado: '' = se puede usar.

  El remoto es adonde git va a leer (fetch, pull) o a escribir (push). En la
  llamada se da por el NOMBRE que tiene en el repo o por su direccion, y una
  direccion es una de dos cosas (ClaseDeDireccion): de RED, o una CARPETA,
  que pasa por la jaula (CarpetaDeRemotoDenegada). Lo que no es ni lo uno ni
  lo otro se niega.

  Un nombre se cambia por sus direcciones - TODAS las que tenga: git envia a
  cada una - y se juzgan esas. Sin remoto en la llamada, git usa uno de los
  del repo: se juzgan todos. Cada direccion de red pasa por la lista de
  hosts, proceda de la llamada o del repo. Tiene que ser una direccion que
  esa lista entiende: con su esquema, o con usuario.

  Si git no contesta a lo que se le pregunta para juzgar, no se usa.

  Medido el 29-sep-2026 por la tool: con una carpeta de fuera de las raices,
  por su ruta o por su nombre, fetch traia su historia y push escribia ramas
  alli. La lista de hosts solo entiende direcciones de red, y una carpeta no
  la miraba nadie. }
function RemotoDenegado(const ACmd, ARepo, AFijado, ABase, AArgs: string): string;
var
  Trozos, Nombres, Mirar, Lineas: TArray<string>;
  Nombre, Direccion, Carpeta, Pregunta: string;
  EscritaEnLaLlamada, NoEsta: Boolean;
begin
  Result := '';
  Pregunta := 'remote get-url --all ';
  if ACmd = 'push' then
    Pregunta := 'remote get-url --push --all ';
  if not RemotosDelRepo(ARepo, AFijado, Nombres) then
    Exit(MsgFmt(SR_GIT_REMOTO_SIN_RESPUESTA_FMT, [ACmd]));
  // el remoto de la llamada: su primer trozo que no es una opcion
  Trozos := TrozosSinGuion(AArgs);
  EscritaEnLaLlamada := (Length(Trozos) > 0) and (IndexStr(Trozos[0], Nombres) < 0);
  if EscritaEnLaLlamada then
    Mirar := nil
  else if Length(Trozos) > 0 then
    Mirar := [Trozos[0]]
  else
    Mirar := Nombres;
  var Direcciones: TArray<string> := nil;
  if EscritaEnLaLlamada then
    Direcciones := [Trozos[0]];
  for Nombre in Mirar do
  begin
    if not GitContesta(ARepo, AFijado, Pregunta + EnComillas(Nombre), Lineas) or
       (Length(Lineas) = 0) then
      Exit(MsgFmt(SR_GIT_REMOTO_SIN_RESPUESTA_FMT, [ACmd]));
    Direcciones := Direcciones + Lineas;
  end;
  for Direccion in Direcciones do
  begin
    Result := DireccionDeRemotoDenegada(ACmd, Direccion, ABase, Carpeta, NoEsta);
    if NoEsta and EscritaEnLaLlamada then
      Result := MsgFmt(SR_GIT_REMOTO_NO_ESTA_FMT, [Direccion,
        IfThen(Length(Nombres) = 0, '(none)', string.Join(', ', Nombres)),
        Carpeta]);
    if Result <> '' then Exit;
  end;
end;

{ LO QUE push ENVIA CUANDO NO SE LE DICE: sin nombres en la llamada lo
  decide la configuracion del repo, y tambien se juzga. '' = vale. Un repo
  ESPEJO (remote.<n>.mirror) envia a la fuerza y quita del remoto lo que
  aqui ya no esta; un remote.<n>.push dice que enviar, y tiene que ser de
  nombres, como lo que se escribe en la llamada. Medido el 29-sep-2026 por
  la tool (cuarta revision): desde un repo espejo, push a secas borro del
  remoto una rama. }
function EnvioConfiguradoDenegado(const ARepo, AFijado, AArgs: string): string;
var
  Trozos, Nombres, Lineas, Todas: TArray<string>;
  Nombre, Linea, Malo, Clave: string;
begin
  Result := '';
  Trozos := TrozosSinGuion(AArgs);
  if Length(Trozos) > 1 then
    Exit; // con nombres en la llamada mandan ellos (EnvioQueNoVale)
  if not RemotosDelRepo(ARepo, AFijado, Nombres) then
    Exit(MsgFmt(SR_GIT_REMOTO_SIN_RESPUESTA_FMT, ['push']));
  if Length(Trozos) = 1 then
  begin
    if IndexStr(Trozos[0], Nombres) < 0 then
      Exit; // una direccion: no tiene configuracion en el repo
    Nombres := [Trozos[0]];
  end;
  // La configuracion ENTERA, de una vez: sale con 0 haya lo que haya, y de
  // sus lineas cuentan las de cada remoto (un aviso de git mezclado en la
  // salida no empieza por el nombre de una clave).
  if not GitContesta(ARepo, AFijado, 'config --list', Todas) then
    Exit(MsgFmt(SR_GIT_REMOTO_SIN_RESPUESTA_FMT, ['push']));
  for Nombre in Nombres do
  begin
    // espejo: lo dice git, que sabe leer sus si y sus no (true, yes, on, 1)
    if not GitContesta(ARepo, AFijado, 'config --type=bool --default false --get ' +
         EnComillas('remote.' + Nombre + '.mirror'), Lineas) then
      Exit(MsgFmt(SR_GIT_REMOTO_SIN_RESPUESTA_FMT, ['push']));
    if IndexStr('true', Lineas) >= 0 then
      Exit(MsgFmt(SR_GIT_PUSH_CONFIG_FMT, [Nombre, 'mirror', Nombre]));
    Clave := 'remote.' + Nombre + '.push=';
    for Linea in Todas do
      if Linea.StartsWith(Clave) and
         EnvioQueNoVale('remoto ' + Linea.Substring(Length(Clave)), Malo) then
        Exit(MsgFmt(SR_GIT_PUSH_CONFIG_FMT, [Nombre,
          'push = ' + Linea.Substring(Length(Clave)), Nombre]));
  end;
end;

const
  TOPE_SALIDA_GIT = 30000; // caracteres de una pagina de la respuesta de git

{ Las lineas de AOutput desde la ADesde (0-based) que caben en una pagina, y
  si queda algo, la nota que dice cuales son y como pedir el resto. Corta
  siempre en un salto; una linea mas larga que la pagina, sola, se corta y
  se dice (GIT-055): la siguiente pagina empieza en la otra, y su cola se
  perdia sin aviso (revision de la 1.13.0) }
function PaginaDeSalidaGit(const AOutput: string; ADesde: Integer): string;
var
  Lineas: TArray<string>;
  Sb: TStringBuilder;
  K: Integer;
  Cortadas: string;
begin
  if (ADesde <= 0) and (Length(AOutput) <= TOPE_SALIDA_GIT) then
    Exit(AOutput);
  Lineas := AOutput.Split([#10]);
  if (Length(Lineas) > 0) and (Lineas[High(Lineas)] = '') then
    SetLength(Lineas, Length(Lineas) - 1); // el salto del final no es una linea
  if ADesde >= Length(Lineas) then
    Exit(MsgFmt(SN_GIT_OFFSET_FUERA_FMT, [ADesde, Length(Lineas)]));
  Cortadas := '';
  Sb := TStringBuilder.Create;
  try
    K := ADesde;
    while (K < Length(Lineas)) and
          ((K = ADesde) or (Sb.Length + Length(Lineas[K]) + 1 <= TOPE_SALIDA_GIT)) do
    begin
      Sb.Append(Copy(Lineas[K], 1, TOPE_SALIDA_GIT)).Append(#10);
      if Length(Lineas[K]) > TOPE_SALIDA_GIT then
        Cortadas := Cortadas + IfThen(Cortadas <> '', ', ') + IntToStr(K + 1);
      Inc(K);
    end;
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
  if Cortadas <> '' then
    Result := Result + MsgFmt(SN_GIT_LINEA_CORTADA_FMT, [Cortadas, TOPE_SALIDA_GIT]) + #10;
  if K < Length(Lineas) then
    Result := Result + MsgFmt(SN_GIT_PAGINA_FMT, [ADesde + 1, K, Length(Lineas), K]);
end;

function TDelphiGitTool.ExecuteWithParams(const Params: TDelphiGitParams): string;
var
  Cmd, GitArgs, Repo, Output, MsgFile: string;
  ExitCode: Cardinal;
  Destino, Enlace: string; // worktree
  GitDir, Comun, Raiz: string; // donde vive el repo (DondeViveElRepo)
  Fijado: string; // --git-dir y --work-tree: git trabaja donde la puerta miro
  SeQuitan: TArray<string>; // las carpetas que git puede quitar: lo nuestro, fuera
  Sitio: string;
begin
  MsgFile := '';
  SeQuitan := nil;
  GitDir := '';
  Comun := '';
  Raiz := '';
  Fijado := '';
  Repo := Params.Repo;
  if Repo = '' then
    Exit(MsgText(SR_GIT_MISSING_REPO));
  // En un proyecto de REFERENCIA (ReadOnlyRoots) vale la mitad de CONSULTA
  // de git - la misma clasificacion que la credencial de solo lectura, en
  // UNA funcion (Lsp.Guard.GitCommandIsQuery). Lo demas pasa por la puerta
  // de escritura y sale con el motivo de referencia.
  if (ReadOnlyRootOf(Repo) <> '') and
     GitCommandIsQuery(Params.Command, Params.Args, Params.Message) then
    Result := ReadPathDenied(Repo, True)
  // el destino de un clone es un sitio donde se ESCRIBE: la puerta de
  // escritura (jaula + carpetas muertas), como su gemela worktree add. Se
  // clonaba dentro de __delphi-temp, __delphi-patch o __history (septima)
  else if SameText(Params.Command.Trim, 'clone') then
    Result := WriteTargetDenied(Repo)
  else
    Result := PathDenied(Repo, True);
  if Result <> '' then
    Exit;
  if TFile.Exists(Repo) then
    Repo := TPath.GetDirectoryName(Repo);
  // clone is the one command whose target directory may not exist yet: it
  // is created (inside the jail, already checked above) right before git
  // runs, and a failed clone removes it only if THIS clone created it. Se
  // creaba aqui arriba: un rechazo de la URL la dejaba, y la limpieza de
  // abajo borraba una carpeta vacia que ya estaba (la raiz vacia de otro
  // workspace; sexta revision).
  var CreadaPorElClone := False;
  var AncestroDelClone := ''; // lo que el clone cree debajo es suyo
  if not SameText(Params.Command.Trim, 'clone') and not TDirectory.Exists(Repo) then
    Exit(MsgFmt(SR_GIT_DIR_NOT_FOUND_FMT, [Repo]));

  // UNA lista de metacaracteres (Lsp.Guard.ShellArgDenied): la tool tenia
  // su copia (novena revision)
  if ShellArgDenied(Params.Args) <> '' then
    Exit(MsgText(SR_GIT_SHELL_METACHARS_ARGS));
  // The message never goes through a shell (git is spawned with a direct
  // command line): normal punctuation is welcome. Line breaks are refused
  // ONLY for the commands that embed the message in the command line -
  // commit and tag write it to a file and pass -F, so there a multi-line
  // message is exactly what you want: subject, blank line, body with the
  // WHY. Refusing it left every agent-made history as one-line subjects
  // (field report 2026-08-25).
  if (Params.Message.Contains(#13) or Params.Message.Contains(#10)) and
     not MatchText(Params.Command.Trim, ['commit', 'tag']) then
    Exit(MsgText(SR_GIT_MESSAGE_LINES));
  // Dangerous git options (--output, --no-index, -c, ...) are filtered at the
  // single gate (Lsp.Guard.ToolCallDenied), before this handler runs.

  Cmd := Params.Command.Trim.ToLower;
  // lo que no va con el comando se dice (Lsp.Guard.ParametroQueNoVa): commit
  // con path hacia un commit de TODO el indice (octava revision). Solo los
  // parametros de UN comando; args es de todos y lo mira el filtro
  // stash y worktree tienen SUBcomando (el primer trozo de args): la tabla
  // era por comando, y stash list admitia message, worktree list path y
  // worktree remove ref (novena revision)
  var ModoGit := Cmd;
  if Cmd = 'stash' then
  begin
    var TrozosSub := TrocearArgs(Params.Args);
    // (sin IfThen: evalua las dos ramas y TrozosSub[0] sin trozos era un AV)
    ModoGit := 'stash push';
    if Length(TrozosSub) > 0 then
      ModoGit := 'stash ' + LowerCase(TrozosSub[0]);
  end
  else if Cmd = 'worktree' then
    ModoGit := 'worktree ' + Params.Args.Trim.ToLower;
  var SuyosGit: string;
  var SobraGit := ParametroQueNoVa(ModoGit, [
      'status', 'offset', 'diff', 'offset', 'log', 'offset', 'show', 'offset',
      'branch', 'offset', 'add', '',
      'pull', '', 'fetch', '', 'ls-remote', 'offset', 'init', '', 'merge', '', 'push', '',
      'commit', 'message', 'clone', 'message', 'config', 'message',
      'stash push', 'message', 'stash pop', '', 'stash list', 'offset',
      'tag', 'message offset', 'switch', 'create', 'restore', '',
      'worktree add', 'path ref', 'worktree list', 'offset', 'worktree remove', 'path'],
    ['message', Params.Message, '', 'path', Params.Path, '', 'ref', Params.Ref, '',
     'create', IfThen(Params.Create, 'true'), '',
     'offset', IfThen(Params.Offset <> 0, IntToStr(Params.Offset)), ''], SuyosGit);
  if SobraGit <> '' then
  begin
    // como viaja en el cable: command=stash args=pop, no "command=stash pop"
    // (un agente lo repetia literal y caia en GIT-034; r11b H5)
    var Muestra := Cmd;
    if ModoGit <> Cmd then
      Muestra := Cmd + ' args=' + Copy(ModoGit, Length(Cmd) + 2, MaxInt);
    Exit(MsgFmt(SR_GIT_NO_VA_CON_COMANDO_FMT, [SobraGit, Muestra, Muestra, ONinguno(SuyosGit)]));
  end;
  // offset, solo con una CONSULTA: branch y tag listan sin argumentos (su
  // nota GIT-053 lo ofrece) y escriben con ellos
  if (Params.Offset <> 0) and not GitCommandIsQuery(Cmd, Params.Args, Params.Message) then
    Exit(MsgFmt(SR_GIT_OFFSET_SOLO_CONSULTA_FMT, [Cmd]));
  // Un comando que no es de la lista se dice ANTES de preguntar nada a git
  // (la lista de abajo acaba en el mismo texto: esta es la que manda, y un
  // comando nuevo que no se apunte aqui no funciona - cerrado).
  if not MatchText(Cmd, ['status', 'diff', 'log', 'show', 'branch', 'add',
       'commit', 'clone', 'pull', 'fetch', 'init', 'config', 'switch', 'merge',
       'stash', 'restore', 'push', 'tag', 'worktree', 'ls-remote']) then
    Exit(MsgFmt(SR_GIT_UNKNOWN_COMMAND_FMT, [Params.Command]));

  // LA JAULA DEL REPO. git no trabaja sobre la carpeta que se le da: sube
  // desde ella hasta dar con el repo, y lee y reescribe ESE arbol entero. La
  // puerta de arriba miraba solo la carpeta: con la raiz del repo por encima
  // de las raices de la sesion, status y diff ensenaban lo de fuera, y
  // stash, switch y commit lo reescribian (medido el 29-sep-2026: una sesion
  // con mono\a por unica raiz reescribio mono\b y escribio en mono\.git).
  // Las TRES carpetas del repo pasan por la misma puerta que paso la suya -
  // la raiz del arbol, su carpeta de git y la comun (la del repo principal
  // de un worktree enlazado) -, y git corre FIJADO a ellas: trabaja donde
  // la puerta miro, no donde el encuentre un repo al volver a buscar. clone
  // hace su repo. init tambien REINICIALIZA el .git que ya exista: su
  // fichero gitdir puede apuntar fuera, y pasa por la misma puerta.
  if (Cmd <> 'clone') and ((Cmd <> 'init') or
     TFile.Exists(TPath.Combine(Repo, '.git')) or
     TDirectory.Exists(TPath.Combine(Repo, '.git'))) then
  begin
    if not DondeViveElRepo(Repo, GitDir, Comun, Raiz, Output, ExitCode) then
      Exit(GitFallo(ExitCode, Output));
    for Sitio in TArray<string>.Create(Raiz, GitDir, Comun) do
      if Sitio <> '' then
      begin
        if (ReadOnlyRootOf(Sitio) <> '') and
           GitCommandIsQuery(Params.Command, Params.Args, Params.Message) then
          Result := ReadPathDenied(Sitio, True)
        else
          Result := PathDenied(Sitio, True);
        if Result <> '' then
          Exit(MsgFmt(SR_GIT_REPO_FUERA_FMT, [Params.Repo, Sitio]));
      end;
    // por el compositor de la casa (EnComillas), como todo argumento
    Fijado := ' --git-dir=' + EnComillas(GitDir);
    if Raiz <> '' then
      Fijado := Fijado + ' --work-tree=' + EnComillas(Raiz)
    else
      // SIN arbol de trabajo (un repo bare, o "repo" apuntando a la propia
      // .git): --bare. Con --git-dir solo, git toma el directorio actual por
      // arbol de trabajo: status ensenaba el contenido de .git como si
      // fueran los fuentes y switch escribia los ficheros de la rama DENTRO
      // de .git (medido con git a pelo el 29-sep-2026, tercera revision).
      // Con --bare contesta lo que contesta sin fijar: log y branch van, y
      // lo que necesita un arbol dice que no lo tiene.
      Fijado := Fijado + ' --bare';
    // EL REMOTO antes que su endpoint LFS: un pull desde una carpeta de
    // fuera se niega por el remoto (GIT-044), no por el endpoint que de el
    // deriva. La puerta del remoto va delante de la de la configuracion.
    if MatchText(Cmd, ['pull', 'fetch', 'push', 'ls-remote']) then
    begin
      Result := RemotoDenegado(Cmd, Repo, Fijado, IfThen(Raiz <> '', Raiz, Repo),
        Params.Args);
      if (Result = '') and (Cmd = 'push') then
        Result := EnvioConfiguradoDenegado(Repo, Fijado, Params.Args);
      if Result <> '' then
        Exit;
    end;
    Result := ConfiguracionGitDenegada(Repo, Raiz, GitMaterializaArbol(Cmd, Params.Args), Fijado);
    if Result <> '' then
      Exit;
  end;
  if Cmd = 'status' then
    GitArgs := 'status --porcelain=v1 -b ' + ArgvSeguro(Params.Args)
  else if Cmd = 'diff' then
    GitArgs := 'diff ' + ArgvSeguro(Params.Args)
  else if Cmd = 'ls-remote' then
  begin
    for var Trozo in TrocearArgs(Params.Args) do
      if Trozo.StartsWith('-') and
         (IndexStr(Trozo, ['--heads', '--tags', '--refs', '--symref', '--exit-code']) < 0) then
        Exit(MsgFmt(SR_GIT_RED_OPCION_FMT, [Cmd, Trozo,
          '--heads, --tags, --refs, --symref, --exit-code']));
    GitArgs := 'ls-remote ' + ArgvSeguro(Params.Args);
  end
  else if Cmd = 'log' then
  begin
    GitArgs := 'log --oneline -20 ' + ArgvSeguro(Params.Args);
  end
  else if Cmd = 'show' then
    GitArgs := 'show --stat --format=medium ' + ArgvSeguro(Params.Args)
  else if Cmd = 'branch' then
    GitArgs := 'branch -vv ' + ArgvSeguro(Params.Args)
  else if Cmd = 'add' then
  begin
    if Params.Args.Trim = '' then
      Exit(MsgText(SR_GIT_ADD_NEEDS_ARGS_PATHS));
    GitArgs := 'add ' + ArgvSeguro(Params.Args);
  end
  else if Cmd = 'commit' then
  begin
    if MensajeEnArgsGit(Params.Args) then
      Exit(MsgText(SR_GIT_MENSAJE_EN_ARGS));
    if Params.Message.Trim = '' then
      Exit(MsgText(SR_GIT_COMMIT_NEEDS_MESSAGE));
    // -F <file>: the message reaches git byte-exact. Embedding it in the
    // command line mangled double quotes (measured in the field: " -> '').
    // Temporal DEL SERVIDOR, y de los que importan: lleva el mensaje que
    // escribe quien llama. Vivia en el %TEMP% de la MAQUINA, fuera de toda
    // jaula; se borra siempre (mas abajo), pero mientras existe no tiene por
    // que estar donde lo vea cualquiera. Por el nombrador (Lsp.Guard).
    CrearCarpeta(ServerTempDir('git'));
    MsgFile := NombreDeMensajeGit;
    TFile.WriteAllBytes(MsgFile, TEncoding.UTF8.GetBytes(Params.Message));
    GitArgs := Format('commit -F "%s" %s', [MsgFile, ArgvSeguro(Params.Args)]);
  end
  else if Cmd = 'clone' then
  begin
    // The URL travels in "message" (args screens metacharacters, and a URL
    // legitimately carries ':' '/' '@'). Destination = repo (jailed).
    var Url := Params.Message.Trim;
    if Url = '' then
      Exit(MsgText(SR_GIT_CLONE_NEEDS_REPOSITORY_URL));
    if not EsUrlDeRed(Url) then
      Exit(MsgText(SR_GIT_CLONE_URLS_ACCEPTED));
    if ShellArgDenied(Url) <> '' then
      Exit(MsgText(SR_GIT_SHELL_METACHARS_URL));
    if Url.Contains('--upload-pack') or Url.Contains('--config') or
       Url.StartsWith('-') then
      Exit(MsgText(SR_GIT_URL_NOT_ALLOWED));
    if TDirectory.Exists(TPath.Combine(Repo, '.git')) then
      Exit(MsgFmt(SR_GIT_YA_ES_REPOSITORIO_FMT, [Repo]));
    // El destino se crea AQUI, pasadas todas las negativas: un rechazo no
    // deja nada, y si el clone falla se quita solo si lo creo el.
    if not TDirectory.Exists(Repo) then
    begin
      AncestroDelClone := PrimerAncestroQueExiste(Repo);
      CrearCarpeta(Repo);
      CreadaPorElClone := True;
    end;
    // clone into "." of the (jailed, existing) destination directory. The "--"
    // separator guarantees the URL is a POSITIONAL, never parsed as an option,
    // whatever it contains - defence in depth over the leading-"-" check above
    // (field round 9: git network args travel fairly verbatim). User args go
    // BEFORE "--" so legitimate options (--depth, --branch) still apply; they
    // were already vetted for dangerous flags at the single gate (GitArgDenied).
    // Primero los objetos: ningun filtro ve un endpoint aun sin juzgar.
    GitArgs := Format('clone --no-checkout %s -- %s .', [ArgvSeguro(Params.Args), EnComillas(Url)]);
  end
  else if Cmd = 'pull' then
  begin
    // SIEMPRE --ff-only, como merge: pull es bajar e integrar, y lo segundo
    // lo hacia como git quisiera. Con las historias divergidas y sin ninguna
    // opcion dejaba un commit de mezcla; con --rebase reescribia la
    // historia, y con --squash dejaba el arbol a medias (medido el
    // 29-sep-2026). Y la opcion del que llama iba DETRAS y ganaba: de las
    // opciones, solo las de la bajada (por los trozos que lee la puerta).
    for var Trozo in TrocearArgs(Params.Args) do
      if Trozo.StartsWith('-') and not OpcionDeRed(Cmd, Trozo) then
        Exit(MsgFmt(SR_GIT_PULL_ARGS_FMT, [Trozo]));
    GitArgs := 'pull --ff-only ' + ArgvSeguro(Params.Args);
    SeQuitan := [Raiz]; // reescribe el arbol: puede quitar carpetas
  end
  else if Cmd = 'fetch' then
  begin
    for var Trozo in TrocearArgs(Params.Args) do
      if Trozo.StartsWith('-') and not OpcionDeRed(Cmd, Trozo) then
        Exit(MsgFmt(SR_GIT_RED_OPCION_FMT, [Cmd, Trozo, OPCIONES_DE_FETCH]));
    GitArgs := 'fetch ' + ArgvSeguro(Params.Args);
  end
  else if Cmd = 'init' then
    GitArgs := 'init ' + ArgvSeguro(Params.Args)
  else if Cmd = 'config' then
  begin
    // Only the commit identity, so a remote agent can commit on a fresh
    // repo/machine. Anything else in git config stays off-limits.
    if not (SameText(Params.Args.Trim, 'user.name') or
            SameText(Params.Args.Trim, 'user.email')) then
      Exit(MsgText(SR_GIT_CONFIG_ONLY_ACCEPTS_USER));
    if Params.Message.Trim = '' then
      Exit(MsgText(SR_GIT_CONFIG_NEEDS_VALUE));
    GitArgs := 'config ' + Params.Args.Trim.ToLower + ' ' +
      EnComillas(Params.Message);
  end
  else if Cmd = 'switch' then
  begin
    // Changing branch is what a real workflow needs and what was missing:
    // an agent could CREATE a branch and never move to it (review
    // 2026-08-25). Only the branch form: "switch <branch>" or, with
    // create=true, "switch -c <branch>". The file-restoring forms of
    // checkout (checkout -- <path>) are NOT here on purpose - those DISCARD
    // work, and discarding has its own command with its own words.
    if Params.Args.Trim = '' then
      Exit(MsgText(SR_GIT_SWITCH_NEEDS));
    if Params.Create then
      GitArgs := 'switch -c ' + ArgvSeguro(Params.Args) // el arbol se queda como esta
    else
    begin
      GitArgs := 'switch ' + ArgvSeguro(Params.Args);
      SeQuitan := [Raiz]; // la otra rama puede no tener la carpeta de un proyecto
    end;
  end
  else if Cmd = 'merge' then
  begin
    if Params.Args.Trim = '' then
      Exit(MsgText(SR_GIT_MERGE_NEEDS));
    // --ff-only: a merge that would need a commit (and could conflict half
    // way) is refused rather than left half-done. Real conflicts are a
    // human's business, not an agent's guess.
    // ...which only held while the caller could not ADD options: user args
    // landed after --ff-only, so `--no-ff <branch>` won and left the repo in
    // MERGING with conflict markers and no way back through this tool
    // (measured 2026-08-25). A branch name, or --abort. Nothing else.
    SeQuitan := [Raiz]; // lo que entra (o lo que se deshace) puede quitar carpetas
    if SameText(Params.Args.Trim, '--abort') then
      GitArgs := 'merge --abort'
    else if Params.Args.Trim.StartsWith('-') or
            (Params.Args.Trim.Split([' ', #9],
              TStringSplitOptions.ExcludeEmpty)[0] <> Params.Args.Trim) then
      Exit(MsgText(SR_GIT_MERGE_ARGS))
    else
      GitArgs := 'merge --ff-only ' + ArgvSeguro(Params.Args.Trim);
  end
  else if Cmd = 'stash' then
  begin
    // push (default) / pop / list: park work to change branch and get it
    // back. Never "stash drop" - that destroys.
    // Y push con RUTAS es como se DESCARTAN los cambios de unos ficheros
    // sin destruirlos: vuelven a HEAD y lo de antes queda en el stash, de
    // donde pop lo devuelve. Faltaba: devolver dos .res a HEAD obligo a
    // salir a la consola (muro, 26-sep-2026).
    var Trozos := TrocearArgs(Params.Args);
    var Sub := 'push';
    if Length(Trozos) > 0 then
      Sub := Trozos[0].ToLower;
    if MatchText(Sub, ['pop', 'list']) and (Length(Trozos) = 1) then
    begin
      GitArgs := 'stash ' + Sub;
      // list solo ENSENA; pop reescribe el arbol con lo aparcado
      if Sub = 'pop' then
        SeQuitan := [Raiz];
    end
    else if Sub = 'push' then
    begin
      GitArgs := 'stash push';
      if Params.Message.Trim <> '' then
        GitArgs := GitArgs + ' -m ' + EnComillas(Params.Message.Trim);
      // las rutas, por el helper de los comandos con rutas (RutasDeGit):
      // cada una pasa por la puerta del escritor (se reescribe el fichero)
      var Rutas: string;
      var Carpetas: TArray<string>;
      Result := RutasDeGit(Repo, Params.Args, Trozos, 1, True, 'stash', Rutas, Carpetas);
      if Result <> '' then
        Exit;
      // Vuelve a HEAD lo que se aparca, y lo que HEAD no tiene se va: con
      // rutas, solo bajo sus carpetas; sin ellas, en todo el arbol.
      SeQuitan := [Raiz];
      if Rutas <> '' then
      begin
        GitArgs := GitArgs + ' --' + Rutas;
        SeQuitan := Carpetas;
      end;
    end
    else
      Exit(MsgFmt(SR_GIT_STASH_ARGS_FMT, [Params.Args.Trim]));
  end
  else if Cmd = 'restore' then
  begin
    // SIEMPRE --staged: deshacer un add. Solo rutas (una o mas; . = todo),
    // sin opciones: --worktree/--source tocarian el arbol, y para descartar
    // cambios esta stash push -- <rutas>. Hermes (28-sep-2026): sin rm ni
    // reset en la lista, tras un add no habia forma de deshacer el staging
    // y borro el .git para volver a empezar. El indice es del repo (la
    // puerta ya paso por Repo): las rutas no vuelven a preguntar.
    var Trozos := TrocearArgs(Params.Args);
    var Rutas: string;
    var Carpetas: TArray<string>; // el indice no quita carpetas: no se usan
    Result := RutasDeGit(Repo, Params.Args, Trozos, 0, False, 'restore', Rutas, Carpetas);
    if Result <> '' then
      Exit;
    if Rutas = '' then
      Exit(MsgFmt(SR_GIT_RESTORE_ARGS_FMT, [Params.Args.Trim]));
    GitArgs := 'restore --staged --' + Rutas;
  end
  else if Cmd = 'push' then
  begin
    // uses the SERVER's stored credentials/remotes - consistent with the
    // centralized model (the repo lives next to the compiler)
    for var Trozo in TrocearArgs(Params.Args) do
      if Trozo.StartsWith('-') and not OpcionDeRed(Cmd, Trozo) then
        Exit(MsgFmt(SR_GIT_RED_OPCION_FMT, [Cmd, Trozo, OPCIONES_DE_PUSH]));
    // ...y lo que se envia, nombres: push anade, no reescribe ni borra
    var Malo: string;
    if EnvioQueNoVale(Params.Args, Malo) then
      Exit(MsgFmt(SR_GIT_PUSH_NOMBRE_FMT, [Malo]));
    GitArgs := 'push ' + ArgvSeguro(Params.Args);
  end
  else if Cmd = 'tag' then
  begin
    if MensajeEnArgsGit(Params.Args) then
      Exit(MsgText(SR_GIT_MENSAJE_EN_ARGS));
    if Params.Message.Trim <> '' then
    begin
      // -F makes it annotated (like -m) and keeps quotes byte-exact;
      // args = tag name (and options)
      CrearCarpeta(ServerTempDir('git'));
      MsgFile := NombreDeMensajeGit;
      TFile.WriteAllBytes(MsgFile, TEncoding.UTF8.GetBytes(Params.Message));
      GitArgs := Format('tag -F "%s" %s', [MsgFile, ArgvSeguro(Params.Args)]);
    end
    else
      GitArgs := 'tag ' + ArgvSeguro(Params.Args); // no args = list tags
  end
  else if Cmd = 'worktree' then
  begin
    // OTRA version del repo al lado, sin tocar el arbol de nadie: con lo que
    // un agente REMOTO compara con una version anterior sin salirse del MCP
    // (1.4.0; David, 26-sep-2026: 'lo que nos falta para que el agente remoto
    // pueda revisar'). Como clone: la carpeta la elige el agente dentro de sus
    // raices. Sin carpetas temporales ni limpiezas al arrancar (David): la
    // quita quien la pone, y list se la ensena.
    var Sub := Params.Args.Trim.ToLower;
    if Sub = 'list' then
      GitArgs := 'worktree list'
    else if (Sub = 'add') or (Sub = 'remove') then
    begin
      if Params.Path.Trim = '' then
        Exit(MsgText(SR_GIT_WORKTREE_PATH));
      Destino := SinBarraFinal(TPath.GetFullPath(Params.Path.Trim));
      // Crear o quitar una copia de trabajo es ESCRIBIR alli: la pregunta de
      // todo escritor, por la ruta real, y nunca en una carpeta muerta.
      Result := EscrituraDenegada(Destino);
      if Result = '' then
        Result := WriteTargetDenied(Destino);
      if Result <> '' then
        Exit;
      if Sub = 'add' then
      begin
        if TDirectory.Exists(Destino) or TFile.Exists(Destino) then
          Exit(MsgFmt(SR_GIT_WORKTREE_EXISTS_FMT, [Destino]));
        if not EsNombreDeRef(Params.Ref.Trim, True) then
          Exit(MsgText(SR_GIT_WORKTREE_REF));
        // Nunca DENTRO del propio repo: el arbol principal la veria como una
        // carpeta sin seguimiento, y un add -A se la llevaria.
        // Por la ruta REAL de los dos: git da nombres largos y el agente
        // puede pasar la forma 8.3 (medido: C:\Users\DFONTA~1 frente a
        // C:/Users/dfontanet - el texto no casaba y lo dejaba dentro).
        var RaizReal := SinBarraFinal(RealPath(Raiz));
        var DestinoReal := SinBarraFinal(RealPath(Destino));
        if (Raiz <> '') and
           (SameText(DestinoReal, RaizReal) or
            StartsText(IncludeTrailingPathDelimiter(RaizReal), DestinoReal)) then
          Exit(MsgFmt(SR_GIT_WORKTREE_INSIDE_FMT, [Raiz]));
        GitArgs := Format('worktree add --detach "%s" %s', [Destino, Params.Ref.Trim]);
      end
      else
      begin
        // Solo lo que git lista como worktree de ESTE repo, y nunca el
        // principal (el primero): remove no sirve para borrar otra cosa.
        var Lista := GitCorre(Repo, Fijado, 'worktree list --porcelain', 60000, ExitCode);
        var Listado := False;
        var DestinoReal := SinBarraFinal(RealPath(Destino));
        var Primero := True;
        for var Linea in Lista.Split([#10]) do
          if Linea.StartsWith('worktree ') then
          begin
            // por la ruta real, como arriba: git lista nombres largos
            if not Primero and SameText(DestinoReal, SinBarraFinal(
                 RealPath(Linea.Substring(9).Trim.Replace('/', '\')))) then
              Listado := True;
            Primero := False;
          end;
        if not Listado then
          Exit(MsgFmt(SR_GIT_WORKTREE_NOT_LISTED_FMT, [Destino]));
        // git worktree remove ATRAVIESA un enlace de dentro y borra lo que hay
        // detras (medido el 26-sep-2026: un junction en una carpeta ignorada
        // dejo vacia una victima de fuera). Con un enlace dentro no se quita.
        Enlace := '';
        RecorreSinEnlaces(Destino,
          procedure(const APath: string)
          begin
          end,
          procedure(const APath: string)
          begin
            if Enlace = '' then
              Enlace := APath;
          end);
        if Enlace <> '' then
          Exit(MsgFmt(SR_GIT_WORKTREE_LINK_FMT, [Enlace]));
        // Lo NUESTRO, fuera antes de que git la borre: con un DelphiLSP vivo
        // en el worktree (un hover basta) git borraba el contenido, no podia
        // con la carpeta y salia con 255 (medido el 29-sep-2026). Se suelta
        // abajo, junto al git y con el cerrojo de escritura ya cogido.
        SeQuitan := [Destino];
        // Sin --force: con cambios, git se niega y lo dice.
        GitArgs := Format('worktree remove "%s"', [Destino]);
      end;
    end
    else
      Exit(MsgText(SR_GIT_WORKTREE_ARGS));
  end
  else
    Exit(MsgFmt(SR_GIT_UNKNOWN_COMMAND_FMT, [Params.Command]));

  if MatchText(Cmd, ['clone', 'pull', 'fetch', 'push', 'ls-remote']) then
    TLogger.Warning(MsgFmt(SL_GIT_NETWORK_FMT,
      [Cmd, Repo, Params.Message]));

  // Lo que REESCRIBE el arbol en local (switch, merge, stash, reset,
  // restore, worktree...) toma el cerrojo de escritura, como todo escritor:
  // un delphi_edit entre medias se perdia con OK. Las de RED no: clone crea
  // una carpeta nueva, fetch y push no tocan el arbol, y pull -que si lo
  // toca- tarda lo que tarde la red y pararia toda edicion del servidor:
  // es la excepcion, y esta escrita (septima revision). Las consultas no
  // escriben.
  var ConCerrojo := not GitCommandIsQuery(Params.Command, Params.Args, Params.Message) and
    not MatchText(Cmd, ['clone', 'pull', 'fetch', 'push']);
  // Lo que REESCRIBE el arbol puede QUITAR carpetas: una rama sin la carpeta
  // de un proyecto, y git borraba sus ficheros, no podia con la carpeta -el
  // motor de ese proyecto la tiene de directorio de trabajo- y la dejaba
  // vacia, con exit=0 (medido el 29-sep-2026). Los motores de lo que se
  // reescribe se paran antes (SeQuitan: lo apunta cada comando, arriba,
  // donde sabe lo que hace - una consulta como stash list, o switch con
  // create, no paran a nadie); vuelven a arrancar en la siguiente peticion.
  //
  // pull es red Y arbol. Lo de la red se hace ANTES, con un fetch: sin
  // marca, porque dura lo que dure la red y en ese rato nadie podria
  // arrancar un motor en el repo. El pull de despues encuentra lo suyo ya
  // bajado y es casi todo local: ese va con la marca, como los demas. (Se
  // soltaba y se quitaba la marca antes de empezar: el motor que arrancaba
  // durante la red volvia a retener su carpeta.) Solo el pull sin opciones:
  // con ellas (--depth, --tags...) el fetch previo bajaria otra cosa.
  if SameText(Cmd, 'pull') and (Raiz <> '') then
  begin
    // por los trozos que lee la puerta (TrocearArgs), no por el texto
    var ConOpciones := False;
    for var Trozo in TrocearArgs(Params.Args) do
      if Trozo.StartsWith('-') then
        ConOpciones := True;
    if not ConOpciones then
    begin
      var Previo: Cardinal;
      GitCorre(Repo, Fijado, 'fetch ' + ArgvSeguro(Params.Args), 600000, Previo);
      // si falla, el pull lo dira con sus palabras
    end;
  end;
  // (el try de fuera no sangra lo de dentro, como el de RunCore: es solo la
  // regla del clone que no ocurrio, abajo)
  var GitCorrio := False;
  try
  if ConCerrojo then
    EnterFileEdit;
  try
    for Sitio in SeQuitan do
      if Sitio <> '' then
        SueltaLoNuestroBajo(Sitio);
    try
      try
        Output := GitCorre(Repo, Fijado, GitArgs,
          IfThen(MatchText(Cmd, ['push', 'clone', 'pull', 'fetch', 'ls-remote']), 600000, 60000),
          ExitCode);
        GitCorrio := True;
        if (Cmd = 'clone') and (ExitCode = 0) then
        begin
          // El repo ya existe, pero su arbol todavia no se ha materializado.
          if not DondeViveElRepo(Repo, GitDir, Comun, Raiz, Output, ExitCode) then
            Exit(GitFallo(ExitCode, Output));
          Fijado := ' --git-dir=' + EnComillas(GitDir);
          if Raiz <> '' then Fijado := Fijado + ' --work-tree=' + EnComillas(Raiz)
          else Fijado := Fijado + ' --bare';
          Result := ConfiguracionGitDenegada(Repo, Raiz, GitMaterializaArbol(Cmd, Params.Args), Fijado);
          if Result <> '' then
          begin
            ExitCode := 1;
            Exit;
          end;
          // Un bare o --no-checkout no pide arbol. Un clone vacio tampoco.
          if (Raiz <> '') and not MatchText('--no-checkout', TrocearArgs(Params.Args)) and
             not MatchText('-n', TrocearArgs(Params.Args)) then
          begin
            GitCorre(Repo, Fijado, 'rev-parse --verify --quiet HEAD', 60000, ExitCode);
            if ExitCode = 0 then
              Output := GitCorre(Repo, Fijado, 'checkout --force', 600000, ExitCode)
            else if ExitCode = 1 then
            begin
              ExitCode := 0;
              Output := '';
            end;
          end;
        end;
      finally
        if (MsgFile <> '') and TFile.Exists(MsgFile) then
          TFile.Delete(MsgFile);
      end;
    finally
      for Sitio in SeQuitan do
        if Sitio <> '' then
          YaNoSeQuita(Sitio);
    end;
  finally
    if ConCerrojo then
      LeaveFileEdit;
  end;
  finally
    // A clone that did not happen must not leave its empty destination lying
    // around for the caller to clean up by hand (field round 10).
    // Todas las que creo (n1\n2\n3 dejaba n1\n2), vacias y por la puerta de
    // escritura: la regla de la foto (septima revision). Y el que no llego
    // ni a lanzar git - un servidor sin git, GIT-050 - tampoco ocurrio: se
    // iba por la excepcion y dejaba sus carpetas (medido el 30-sep-2026).
    if (not GitCorrio or (ExitCode <> 0)) and SameText(Cmd, 'clone') and CreadaPorElClone then
      QuitaCarpetasCreadas(Repo, AncestroDelClone);
  end;
  // Una pagina de la respuesta: la de una orden que solo LEE se puede pedir
  // entera, por lineas (offset); se cortaba a 30000 caracteres y no habia
  // forma de ver el resto (muro de la lista del 4-oct-2026). La de una que
  // escribe, no: repetirla con offset la volveria a ejecutar
  if GitCommandIsQuery(Cmd, Params.Args, Params.Message) then
    Output := PaginaDeSalidaGit(Output, Params.Offset)
  else if Length(Output) > TOPE_SALIDA_GIT then
    Output := Copy(Output, 1, TOPE_SALIDA_GIT) + #10 + MsgText(SF_GIT_TRUNCATED);
  // Un git que dice que no (exit<>0) es un fallo: salia como exito y el
  // agente no lo distinguia de uno que funciono (revision 27-sep-2026). Su
  // salida va detras, que es la que explica que paso.
  // diff con --quiet / --exit-code contesta exit=1 cuando HAY diferencias: es
  // su respuesta, no un fallo (tercera revision: salia GIT-036 DENIED). Con
  // --no-index no: un fichero que no esta tambien da 1 (medido).
  var DiffConCambios := SameText(Cmd, 'diff') and (ExitCode = 1) and
    (ContainsText(Params.Args, '--quiet') or ContainsText(Params.Args, '--exit-code')) and
    not ContainsText(Params.Args, '--no-index');
  if DiffConCambios then
    Result := GitExito(MsgText(SN_GIT_DIFF_HAY_CAMBIOS) +
      IfThen(Output.Trim <> '', #10 + Output.Trim, ''), 1)
  else if ExitCode <> 0 then
    Result := GitFallo(ExitCode, Output)
  else
    Result := GitExito(Output.Trim, 0);
  // Una respuesta que es solo "exit=0" no se distingue de una que se ha roto
  // por el camino, y lo primero que hace quien la recibe es repetirla. El
  // silencio de git SIGNIFICA cosas distintas segun la orden, asi que se
  // dice cual (medido 2026-09-20 pidiendo el diff de un arbol limpio).
  if (ExitCode = 0) and (Output.Trim = '') then
  begin
    if SameText(Cmd, 'diff') then
      Result := GitExito(MsgText(SN_GIT_DIFF_CLEAN), 0)
    else if GitCommandIsQuery(Cmd, Params.Args, Params.Message) then
    begin
      // Una consulta vacia dice LO QUE RECIBIO git (sin la -C del repo ni la
      // configuracion de la casa): "log -S<texto>" vacio parecia que el texto
      // se perdia por el camino, y era que el fichero decia otra cosa (Hermes,
      // validacion de la 1.16.0). Solo en las que leen: en las que escriben,
      // callar ya es el exito y el eco repetiria URLs y valores.
      Result := GitExito(MsgFmt(SN_GIT_CONSULTA_VACIA_FMT, [GitArgs.Trim]), 0);
      if SameText(Cmd, 'log') then
        for var Trozo in TrocearArgs(Params.Args) do
          if Trozo.StartsWith('-S') or Trozo.StartsWith('-G') then
          begin
            Result := Result + #10 + MsgText(SN_GIT_PICKAXE_VACIO);
            Break;
          end;
    end
    else
      Result := GitExito(MsgFmt(SN_GIT_SILENT_OK_FMT, [Cmd]), 0);
  end;
  // Un worktree nuevo es de quien lo pidio: se lo dice, con como quitarlo.
  if (ExitCode = 0) and (Cmd = 'worktree') and SameText(Params.Args.Trim, 'add') then
    Result := Result + #10 + MsgFmt(SN_GIT_WORKTREE_ADDED_FMT, [Destino]);
  // git's own hints recommend exactly what this tool refuses (--no-ff,
  // rebase, "specify the URL from the command-line"): say so, or the reader
  // follows the advice printed last (field round 10).
  // Un merge que no puede ir en fast-forward muere con exit 128 y "Not
  // possible to fast-forward": git no sugiere nada y la respuesta era el
  // codigo a pelo (abierto menor del 22-sep). Se dice que significa.
  if (ExitCode <> 0) and MatchText(Cmd, ['merge', 'pull']) and Output.Contains('fast-forward') then
    Result := Result + #10 + MsgText(SN_GIT_MERGE_DIVERGED);
  if (ExitCode <> 0) and not DiffConCambios and (Output.Contains('--no-ff') or Output.Contains('rebase') or
     Output.Contains('specify the URL')) then
    Result := Result + #10 + MsgText(SN_GIT_HINT_OVERRIDE);
  // El CONTENIDO de un diff, de un show o de un log - las lineas de un
  // fichero o de un mensaje de commit, que empiezan por +, - o espacio -
  // viaja como esta en el disco: el barrido de unidades las reescribia
  // (Lsp.Guard.EnmascaraSalvoContenido). Lo que dice git - cabeceras,
  // avisos, que si pueden nombrar una ruta del servidor - sigue enmascarado.
  if ((ExitCode = 0) or DiffConCambios) and MatchText(Cmd, ['diff', 'show', 'log']) then
    Result := EnmascaraSalvoContenido(Result, '+- ');
end;

{ TDelphiInstallsTool }

constructor TDelphiInstallsTool.Create;
begin
  inherited;
  FName := 'delphi_installs';
  FDescription := SD_WS_INSTALLS;
end;

function TDelphiInstallsTool.ExecuteWithParams(const Params: TDelphiInstallsParams): string;
var
  Return: TJSONObject;
  Arr: TJSONArray;
  Entry: TJSONObject;
  Info, Active: TRadStudioInfo;
  All: TArray<TRadStudioInfo>;
begin
  All := DiscoverAllRadStudios;
  Active := DiscoverRadStudio;
  Return := TJSONObject.Create;
  try
    Return.AddPair('total', TJSONNumber.Create(Length(All)));
    // la del servidor: sin ella no arranca (ExigeElDelphiDelServidor)
    Return.AddPair('activeForLsp', Active.Version);
    // la que fija su settings.ini ([Server] DelphiVersion; el servidor la
    // escribe al arrancar si no estaba)
    if ServerDelphiVersion <> '' then
      Return.AddPair('requested', ServerDelphiVersion);
    // el update que declara el operador ([Server] DelphiUpdate): hoy no
    // decide nada, es la prevision para lo que traiga uno concreto
    if ServerDelphiUpdate <> '' then
      Return.AddPair('requestedUpdate', ServerDelphiUpdate);
    Arr := TJSONArray.Create;
    Return.AddPair('installs', Arr);
    for Info in All do
    begin
      Entry := TJSONObject.Create;
      Arr.AddElement(Entry);
      Entry.AddPair('version', Info.Version);
      // lo que la instalacion dice de si misma (registro y bds.exe), nada
      // compuesto aqui: ausente = no lo tenemos
      if Info.ProductName <> '' then
        Entry.AddPair('name', Info.ProductName);
      if Info.DelphiName <> '' then
        Entry.AddPair('personality', Info.DelphiName);
      if Info.Edition <> '' then
        Entry.AddPair('edition', Info.Edition);
      // el texto que apunto su instalador: una etiqueta para el operador
      if Info.InstalledUpdate <> '' then
        Entry.AddPair('installedUpdate', Info.InstalledUpdate);
      if Info.Build <> '' then
        Entry.AddPair('build', Info.Build);
      Entry.AddPair('rootdir', Info.RootDir);
      Entry.AddPair('delphilsp', TJSONBool.Create(Info.DelphiLspExe <> ''));
      Entry.AddPair('msbuild', TJSONBool.Create(Info.RsVarsBat <> ''));
      Entry.AddPair('active', TJSONBool.Create(
        (Info.Version = Active.Version) and (Info.Version <> '')));
    end;
    Result := Return.ToJSON;
  finally
    Return.Free;
  end;
end;

var
  GArranque: TDateTime; // cuando empezo a vivir ESTE proceso

{ La respuesta de git que acabo bien: "exit=0" y lo que dijo. El formato que
  leen los agentes y las baterias, compuesto en UN sitio (estaba a mano tres
  veces). La que acabo mal es SR_GIT_EXIT_FMT. }
function GitExito(const ACuerpo: string; AExit: Integer): string;
begin
  Result := 'exit=' + IntToStr(AExit) + #10 + ACuerpo;
end;

{ La que acabo MAL: GIT-036, lo que dijo git y las pistas que salen de lo que
  dijo - lo que el agente SI puede hacer, o de quien es el arreglo cuando no
  es suyo. Las tres salidas que acaban en GIT-036 (la carpeta de un remoto,
  la jaula del repo y la orden misma) pasan por aqui: las pistas iban solo en
  la ultima, y el "dubious ownership" de un NAS sale en la jaula, antes de la
  orden (Hermes, 5-oct-2026). Las pistas que dependen de la orden (merge,
  pull) se quedan con la orden. }
function GitFallo(ACodigo: Cardinal; const ASalida: string): string;
begin
  Result := MsgFmt(SR_GIT_EXIT_FMT, [ACodigo, ASalida.Trim]);
  // A fresh repo has no author identity and commit dies with exit 128:
  // the fix is already whitelisted, say so (measured 2026-08-24).
  if ASalida.Contains('Author identity unknown') then
    Result := Result + #10 + MsgText(SN_GIT_PISTA_CONFIGURA_IDENTIDAD);
  if ASalida.Contains('dubious ownership') then
    Result := Result + #10 + MsgText(SN_GIT_PISTA_PROPIEDAD_DUDOSA);
end;

{ Cuanto lleva en marcha, en algo que se lee de un vistazo. }
function TiempoEnMarcha(const ADesde: TDateTime): string;
var
  Segs: Int64;
begin
  Segs := SecondsBetween(Now, ADesde);
  if Segs < 60 then
    Exit(MsgFmt(SF_WS_UPTIME_S_FMT, [Segs]));
  if Segs < 3600 then
    Exit(MsgFmt(SF_WS_UPTIME_M_S_FMT, [Segs div 60, Segs mod 60]));
  if Segs < 86400 then
    Exit(MsgFmt(SF_WS_UPTIME_H_M_FMT, [Segs div 3600, (Segs mod 3600) div 60]));
  Result := MsgFmt(SF_WS_UPTIME_D_H_FMT, [Segs div 86400, (Segs mod 86400) div 3600]);
end;

{ QUIEN esta contestando: version, como se arranco este proceso y cuanto lleva
  vivo. Ninguna tool lo decia: la version vivia en el titulo de la bandeja y
  dentro de un delphi_report, asi que comprobar un despliegue obligaba a mirar
  el proceso DESDE FUERA del MCP (medido el 2026-09-20 usando el servidor como
  agente). Esto es autoconocimiento, no listar procesos: nada de aqui sale de
  este proceso. }
{ Con que cuenta de Windows corre ESTE proceso. No es curiosidad: el IDE guarda
  su Library Path, sus paquetes, sus SDK y sus perfiles en HKCU, asi que un
  servicio instalado con la cuenta por defecto (LocalSystem) arranca, contesta,
  dice activeDelphi y falla con F2613 en cuanto un proyecto toca un componente
  instalado (medido el 2026-09-20: 11 raices de biblioteca como el usuario del
  IDE, 1 como LocalSystem). Estaba escrito en el README y en ningun sitio que
  el servidor pudiera DECIR. }
function CuentaDelProceso(out AEsSistema: Boolean): string;
var
  Buf: array[0..256] of Char;
  Len: DWORD;
begin
  Len := Length(Buf);
  if GetUserName(Buf, Len) then
    Result := Buf
  else
    Result := GetEnvironmentVariable('USERNAME');
  if GetEnvironmentVariable('USERDOMAIN') <> '' then
    Result := GetEnvironmentVariable('USERDOMAIN') + '\' + Result;
  // Dos senales, porque ninguna depende del idioma de Windows a la vez: el
  // nombre de la cuenta y donde cae su perfil.
  AEsSistema := Result.EndsWith('\SYSTEM', True) or SameText(Result, 'SYSTEM') or
    GetEnvironmentVariable('USERPROFILE').ToLower.EndsWith('\config\systemprofile');
end;

{ En que MAQUINA corre ESTE proceso. Con dos servidores del mismo nombre y
  version (28-sep-2026: el 13.1 de este PC y el 13.2 de la VM, mismo token)
  ninguna respuesta decia cual contestaba: serverInfo identico, el workspace
  con el mismo nombre y la cuenta como unica pista. Es el dato que los separa.
  GetComputerName es el lector oficial (el nombre NetBIOS, el mismo que
  USERDOMAIN muestra sin dominio); COMPUTERNAME solo de reserva. }
function NombreDeMaquina: string;
var
  Buf: array[0..256] of Char;
  Len: DWORD;
begin
  Len := Length(Buf);
  if GetComputerName(Buf, Len) then
    Result := Buf
  else
    Result := GetEnvironmentVariable('COMPUTERNAME');
end;

procedure AnadirFichaDelServidor(ADestino: TJSONObject);
var
  Srv: TJSONObject;
  Modo, Transporte, P: string;
  I: Integer;
begin
  // Lo fija el .dpr en la rama que elige al arrancar: releer la linea de
  // ordenes aqui, con otras reglas, decia transport=http con un "/http"
  // suelto sirviendo por stdio (segunda revision, 27-sep-2026)
  Modo := GModoServidor;
  Transporte := GTransporteServidor;
  Srv := TJSONObject.Create;
  ADestino.AddPair('server', Srv);
  Srv.AddPair('version', SERVER_VERSION);
  Srv.AddPair('mode', Modo);
  Srv.AddPair('transport', Transporte);
  Srv.AddPair('pid', TJSONNumber.Create(GetCurrentProcessId));
  Srv.AddPair('exe', ParamStr(0));
  Srv.AddPair('startedAt', FormatDateTime('yyyy-mm-dd hh:nn:ss', GArranque));
  Srv.AddPair('uptime', TiempoEnMarcha(GArranque));
  // El ini se lee UNA vez al arrancar y no se recarga en caliente (decision
  // de David, 24-sep-2026: cambiar la jaula bajo sesiones vivas es una
  // superficie nueva). Lo que si se dice es que el fichero en disco es mas
  // nuevo que el que tiene cargado: lo tocado no esta cargado, hay que
  // reiniciar. Lo decide Lsp.Guard, el dueno del ini, que sabe lo que
  // escribio el mismo.
  var IniEn: TDateTime;
  if SettingsIniMasNuevoQueElCargado(IniEn) then
    Srv.AddPair('settingsChangedNote', MsgFmt(SN_SERVER_INI_CHANGED_FMT,
      [FormatDateTime('yyyy-mm-dd hh:nn:ss', IniEn),
       FormatDateTime('yyyy-mm-dd hh:nn:ss', GArranque)]));
  // La maquina y la cuenta, juntas: son lo que distingue dos despliegues del
  // mismo binario (el mismo dato va en serverInfo.host, por Lsp.Host).
  Srv.AddPair('host', NombreDeMaquina);
  var EsSistema: Boolean;
  Srv.AddPair('account', CuentaDelProceso(EsSistema));
  if EsSistema then
    Srv.AddPair('accountWarning', MsgText(SN_SERVER_LOCALSYSTEM));
  // Cuantos parametros vigila el suelo de la jaula en la puerta. Un cero
  // aqui es un suelo muerto, y siendo redundante nadie mas lo notaria.
  Srv.AddPair('jailedParams', TJSONNumber.Create(ServerPathParamCount));
  // Sesiones HTTP vivas y cuando caducan: lo primero que mira un operador
  // cuando un agente dice que "le han cerrado la sesion". En stdio, 0.
  Srv.AddPair('sessions', TJSONNumber.Create(LiveSessionCount));
  Srv.AddPair('sessionTimeoutMinutes', TJSONNumber.Create(SessionTimeoutMinutes));
  // Mail waiting in NAMED agent boxes. It lives here, in the orientation
  // call, and nowhere else: it is server state, not a message for whoever is
  // asking. Announced at the end of EVERY tool answer it was 90 bytes of
  // noise about other people's post - unreadable and unclearable by the
  // reader, so it never went away (measured 2026-09-20).
  var Correo := DirectedMessagesPending;
  if Correo > 0 then
    Srv.AddPair('mailboxes', TJSONNumber.Create(Correo));
end;

{ TDelphiWorkspaceTool }

constructor TDelphiWorkspaceTool.Create;
begin
  inherited;
  FName := 'delphi_workspace';
  FDescription := MsgFmt(SD_WS_WORKSPACE_FMT, [MsgText(SF_VIRTUAL_DRIVES)]);
end;

function TDelphiWorkspaceTool.ExecuteWithParams(const Params: TDelphiWorkspaceParams): string;
var
  Return: TJSONObject;
  RootsArr: TJSONArray;
  R: string;
  Roots: TArray<string>;
  Info: TRadStudioInfo;
begin
  Return := TJSONObject.Create;
  try
    Return.AddPair('note', MsgText(SN_WORKSPACE_NOTE));
    Roots := WorkspaceRoots;
    RootsArr := TJSONArray.Create;
    Return.AddPair('roots', RootsArr);
    // La raiz que es la unidad entera sale CON su barra (srvn:\), que es lo
    // que el agente puede devolver: sin ella - "srvn:" - la respuesta era
    // GUARD-021, y para Windows "N:" a secas es otra carpeta (1.9.0,
    // SinBarraFinal).
    // Aqui NO se enmascara nada. El enmascarado es UN solo punto de salida
    // (MaskDriveText, montado como ResultFilter en Lsp.Host) y esa es la
    // arquitectura: un sitio, una regla. La primera version de este arreglo
    // (20-sep-2026) apano el sintoma AQUI - le ponia una barra final a una
    // raiz de unidad entera para que "D:" tuviera la forma que el
    // enmascarador sabia reconocer - y eso dejo la fuga viva en todas las
    // demas tools, que echoan rutas en sus negativas. La regla central ya
    // cubre "D:" a secas; parchear los emisores uno a uno es exactamente
    // como sobrevive esta clase de fallo.
    for R in Roots do
      RootsArr.Add(SinBarraFinal(R));
    // Proyectos de REFERENCIA (ReadOnlyRoots): se leen, nunca se escriben,
    // no son raices (la jaula de escritura no los ve) y mandan sobre Roots.
    if Length(WorkspaceReadOnlyRoots) > 0 then
    begin
      var RefArr := TJSONArray.Create;
      Return.AddPair('readOnlyRoots', RefArr);
      for R in WorkspaceReadOnlyRoots do
        RefArr.Add(SinBarraFinal(R));
      Return.AddPair('readOnlyRootsNote', MsgText(SN_WORKSPACE_REFERENCE_NOTE));
    end;
    // Las declaradas que el servidor no alcanza AHORA, con su motivo (sin
    // salir a la red: MotivoRaizNoDisponible). Una referencia en una letra
    // sin montar salia aqui como si estuviera, y el agente se estrellaba
    // contra WS-008 en cada tool (Hermes, 5-oct-2026).
    var NoEstan: TJSONArray := nil;
    for R in Roots + WorkspaceReadOnlyRoots do
    begin
      var Motivo := MotivoRaizNoDisponible(R);
      if Motivo = '' then
        Continue;
      if NoEstan = nil then
      begin
        NoEstan := TJSONArray.Create;
        Return.AddPair('unavailableRoots', NoEstan);
      end;
      var Una := TJSONObject.Create;
      NoEstan.AddElement(Una);
      Una.AddPair('root', SinBarraFinal(R));
      Una.AddPair('reason', Motivo);
    end;
    if NoEstan <> nil then
      Return.AddPair('unavailableRootsNote', MsgText(SN_WS_RAICES_NO_DISPONIBLES));
    if ModoLocalCerrado <> '' then
      // el modo local cerrado al cargar: decia "may look at any path" y cada
      // llamada contestaba GUARD-030 (segunda revision de la 1.9.0)
      Return.AddPair('jail', MsgFmt(SF_WS_JAIL_CERRADA_FMT, [ModoLocalCerrado]))
    else if Length(Roots) = 0 then
      // Sin Roots solo queda el proceso local sin token: mira, no toca. Decir
      // "unrestricted" al lado de access=read-only era contradecirse (22-sep).
      Return.AddPair('jail', MsgText(SF_WS_JAIL_NONE))
    else
      Return.AddPair('jail', 'active');
    // El NOMBRE de la seccion [Workspace.<nombre>] que autentico esta
    // sesion. Ninguna tool lo decia y el operador no podia saber que seccion
    // del ini es la de cada agente (Hermes, 2026-09-23): CurrentWorkspaceName
    // existia desde v0.98 "para delphi_workspace" y nadie la llamaba.
    if CurrentWorkspaceName <> '' then
      Return.AddPair('workspace', CurrentWorkspaceName);
    // What may be READ beyond the roots: the RAD Studio installations, the
    // IDE library search paths and the GetIt catalog repositories. Announced
    // because "anything outside is refused" was not the whole truth for
    // reading tools (field round 4, R4-B).
    // COMPRESSED to the unique top-level trees: the raw list is ~145
    // registered folders and cost every agent ~3.5k tokens on its FIRST
    // call of every session (measured 2026-08-24 while hunting what filled
    // a local model's context). Subfolders of an announced tree add a
    // counter, not a line.
    var ExtraArr := TJSONArray.Create;
    Return.AddPair('readableExtra', ExtraArr);
    var Tops := TList<string>.Create;
    var Counts := TList<Integer>.Create;
    try
      for R in LibraryReadRoots do
      begin
        var Full := IncludeTrailingPathDelimiter(R);
        var Found := -1;
        for var I := 0 to Tops.Count - 1 do
          if StartsText(Tops[I], Full) then
          begin
            Found := I;
            Break;
          end;
        if Found >= 0 then
          Counts[Found] := Counts[Found] + 1
        else
        begin
          // a new candidate may itself be the parent of already-listed ones
          for var I := Tops.Count - 1 downto 0 do
            if StartsText(Full, Tops[I]) then
            begin
              Counts[Tops.Count - 1] := 0; // placeholder, fixed below
              Tops.Delete(I);
              Counts.Delete(I);
            end;
          Tops.Add(Full);
          Counts.Add(0);
        end;
      end;
      for var I := 0 to Tops.Count - 1 do
        if Counts[I] > 0 then
          ExtraArr.Add(MsgFmt(SF_WS_SUBCARPETAS_REGISTRADAS_FMT,
            [SinBarraFinal(Tops[I]), Counts[I]]))
        else
          ExtraArr.Add(SinBarraFinal(Tops[I]));
    finally
      Counts.Free;
      Tops.Free;
    end;
    if LibraryZoneEnabled then
      Return.AddPair('readableExtraNote', MsgText(SN_WS_READONLY_TERRITORY))
    else
      Return.AddPair('readableExtraNote', MsgText(SN_WORKSPACE_LIBZONE_OFF));
    if IsReadOnlyNow then
      Return.AddPair('access', 'read-only')
    else
      Return.AddPair('access', 'read-write');
    Info := DiscoverRadStudio;
    if Info.Found then
    begin
      Return.AddPair('activeDelphi', Info.Version);
      // El numero de BDS no le dice nada a un agente; el nombre si, y sin
      // el no puede buscar documentacion de SU version (David, 22-sep-2026).
      // Todo sale de la instalacion misma (registro, bds.exe): lo que no
      // este ahi no se inventa.
      if Info.ProductName <> '' then
        Return.AddPair('activeDelphiName', Info.ProductName);
      if Info.DelphiName <> '' then
        Return.AddPair('activeDelphiPersonality', Info.DelphiName);
      if Info.Edition <> '' then
        Return.AddPair('activeDelphiEdition', Info.Edition);
      if Info.Build <> '' then
        Return.AddPair('activeDelphiBuild', Info.Build);
      Return.AddPair('activeDelphiRoot', Info.RootDir);
    end
    else
      Return.AddPair('activeDelphi', '');
    // La version que fija su settings.ini ([Server] DelphiVersion): un
    // servidor es un Delphi y sin el no arranca (5-oct-2026).
    if ServerDelphiVersion <> '' then
      Return.AddPair('delphiVersionRequested', ServerDelphiVersion);
    // el update que declara el operador ([Server] DelphiUpdate=13.2): hoy
    // no decide nada, es la prevision para lo que traiga uno concreto
    if ServerDelphiUpdate <> '' then
      Return.AddPair('delphiUpdate', ServerDelphiUpdate);
    AnadirFichaDelServidor(Return);
    Result := Return.ToJSON;
  finally
    Return.Free;
  end;
end;

{ TDelphiProjectsTool }

constructor TDelphiProjectsTool.Create;
begin
  inherited;
  FName := 'delphi_projects';
  FDescription := SD_WS_PROJECTS;
end;

{ The git repository a path belongs to (the folder holding .git), '' when
  none, plus the branch checked out there. An agent arriving cold has to know
  whether what it is about to edit is under version control and on which
  branch BEFORE it edits: asking for it cost a call and some guessing (field
  round 7). Read straight from .git/HEAD - no git process, no shell. }
function RepoOf(const APath: string; out ABranch: string): string;
var
  Dir, Head: string;
begin
  Result := '';
  ABranch := '';
  Dir := APath;
  if TFile.Exists(Dir) then
    Dir := TPath.GetDirectoryName(Dir);
  while (Dir <> '') and TDirectory.Exists(Dir) do
  begin
    if TDirectory.Exists(TPath.Combine(Dir, '.git')) or
       TFile.Exists(TPath.Combine(Dir, '.git')) then
    begin
      Result := Dir;
      Head := TPath.Combine(Dir, '.git\HEAD');
      // Lectura interna: conserva la jaula, sin abrir .git a las tools de ficheros.
      if (ReadPathDenied(Head, True) = '') and TFile.Exists(Head) then
        try
          ABranch := TFile.ReadAllText(Head).Trim;
          if ABranch.StartsWith('ref:') then
            ABranch := ABranch.Substring(ABranch.LastIndexOf('/') + 1)
          else
            ABranch := ABranch.Substring(0, 8) + ' (detached)';
        except
          ABranch := '';
        end;
      Exit;
    end;
    if TPath.GetDirectoryName(Dir) = Dir then
      Break;
    Dir := TPath.GetDirectoryName(Dir);
  end;
end;

{ The folders a .dproj adds to its unit search path, resolved and only when
  they exist. Not the whole compiler path - just what makes a project see
  sources that are not its own. }
function ProjectSearchDirs(const ADproj: string): TArray<string>;
var
  Xml: string;
  L: TStringList;
begin
  Result := nil;
  try
    Xml := TFile.ReadAllText(ADproj);
  except
    Exit;
  end;
  L := TStringList.Create;
  try
    L.Duplicates := dupIgnore;
    L.Sorted := True;
    for var R in RutasDeBusqueda(ADproj, Xml) do
      if (R.Carpeta <> '') and TDirectory.Exists(R.Carpeta) and
         (ReadPathDenied(R.Carpeta) = '') then
        L.Add(R.Carpeta);
    Result := L.ToStringArray;
  finally
    L.Free;
  end;
end;

function TDelphiProjectsTool.ExecuteWithParams(const Params: TDelphiProjectsParams): string;
var
  Return: TJSONObject;
  Roots: TArray<string>;
  RootDir, F, Filt: string;
  Entry: TJSONObject;
  Mask, Repo, Branch: string;
  AllCount: Integer;
begin
  if Params.Root <> '' then
  begin
    Result := ReadPathDenied(Params.Root); // listar es leer: una referencia vale
    if Result <> '' then
      Exit;
    Roots := TArray<string>.Create(Params.Root);
  end
  else
  begin
    // The jail's own list (env DELPHI_MCP_ROOTS or settings.ini) - the ONE
    // source of truth. This tool used to re-read the ini itself and a server
    // configured by environment variable answered "no roots configured"
    // while every other tool was correctly jailed (measured 2026-08-24).
    Roots := WorkspaceRoots;
    // el modo local cerrado no tiene raices, y lo dice con SU motivo: "no
    // roots configured" mandaba a configurarlas (tercera revision, 1.9.0)
    Result := NegativaDeCierre;
    if Result <> '' then
      Exit;
    if Length(Roots) = 0 then
      Exit(MsgText(SR_WS_NO_ROOT_GIVEN));
    // ...y los proyectos de REFERENCIA, marcados abajo como readOnly. Si se
    // solapan (una raiz dentro de una referencia o al reves) se recorre UNA
    // vez: la referencia manda y la marca sale por fichero.
    var Unicas: TArray<string> := nil;
    for var Rz in Roots do
      if ReadOnlyRootOf(Rz) = '' then
        Unicas := Unicas + [Rz];
    for var Rf in WorkspaceReadOnlyRoots do
    begin
      var Dentro := False;
      for var Rz in Unicas do // solo las raices que siguen vivas: una en los dos sitios entra como referencia
        if StartsText(IncludeTrailingPathDelimiter(Rz), IncludeTrailingPathDelimiter(Rf)) then
          Dentro := True;
      if not Dentro then
        Unicas := Unicas + [Rf];
    end;
    Roots := Unicas;
  end;

  // A root that is not there answered {"total":0}, which reads as "there are
  // no projects" instead of "you mistyped the path" - delphi_list says
  // "directory not found" for the same thing (measured 2026-08-25).
  // Eso vale para la carpeta que NOMBRA quien llama. Una raiz del workspace
  // que no esta (una letra sin montar) se salta y se dice: la primera que
  // faltaba cortaba la lista ENTERA con PROJ-003, y el agente creyo que esa
  // era la carpeta por defecto (Hermes, 5-oct-2026).
  var Saltadas := '';
  for RootDir in Roots do
    if (RootDir.Trim <> '') and not TDirectory.Exists(RootDir.Trim) then
    begin
      if Params.Root <> '' then
        Exit(MsgFmt(SR_PROJECTS_NO_ROOT_FMT, [RootDir.Trim]));
      if Saltadas <> '' then
        Saltadas := Saltadas + ', ';
      Saltadas := Saltadas + SinBarraFinal(RootDir.Trim);
    end;
  Filt := Params.Name.Trim.ToLower;
  // Paginado como delphi_search: una maquina de trabajo tiene miles de .dproj
  // y la lista entera no cabe en una respuesta (medido: 7025 proyectos = 82 KB
  // = limite del cliente reventado, o sea la tool inservible sin "root").
  var Pag := PaginaDe(Params.Offset, Params.MaxResults, 50, 300);
  Return := TJSONObject.Create;
  // la carpeta una vez y debajo sus proyectos (el organizador): 'project' y
  // 'dir' repetian la carpeta, el 30% de la respuesta (6-oct-2026)
  var Lista := TListaDeFicheros.Create;
  // cada repositorio UNA vez, con su rama: repo y branch iban en cada
  // proyecto, la misma ruta otra vez (1.15.0). El de un proyecto es el que
  // empieza su carpeta, y delphi_git acepta cualquier ruta de dentro
  var Repos := TStringList.Create;
  var Ramas := TStringList.Create;
  // Donde estan, no solo cuantos: en una maquina de trabajo la lista la
  // COPAN los componentes de terceros y sus copias de seguridad (medido el
  // 2026-09-20 en este servidor: de 7025 proyectos, 6420 eran backups de
  // componentes y fuentes de SecureBlackbox, y los del operador eran 73).
  // Una pagina de 50 de esos no vale para nada; el reparto por carpeta si,
  // porque dice a que "root" volver a llamar.
  var Ocultos := 0;
  var PorCarpeta := Default(TPorCarpeta);
  try
    for RootDir in Roots do
    begin
      if (RootDir.Trim = '') or not TDirectory.Exists(RootDir.Trim) then
        Continue;
      // Si quien llama NOMBRA la papelera (o una carpeta de artefactos) como
      // raiz, es que la quiere: misma regla que delphi_list. Apuntar aqui a
      // __delphi-patch contestaba total 0 teniendo dos .dproj dentro - "no
      // hay nada" cuando la verdad era "hay, y no te los enseno".
      var RaizEnArtefactos := SkipIdeArtifacts(
        IncludeTrailingPathDelimiter(RootDir.Trim));
      for Mask in TArray<string>.Create('*.dproj', '*.groupproj') do
        for F in WalkFiles(RootDir.Trim, Mask) do
        begin
          if not RaizEnArtefactos and (SkipIdeArtifacts(F) or InVault(F)) then
          begin
            // Contados, no tragados: un cero sin explicacion es la mentira
            // que llevamos todo el dia quitando de este servidor.
            Inc(Ocultos);
            Continue;
          end;
          if (Filt <> '') and not TPath.GetFileName(F).ToLower.Contains(Filt) then
            Continue;
          PorCarpeta.Add(F, RootDir.Trim);
          if Pag.Entra then
          begin
            Entry := Lista.Add(F);
            Entry.AddPair('kind', LowerCase(TPath.GetExtension(F)).Substring(1));
            if ReadOnlyRootOf(F) <> '' then
              Entry.AddPair('readOnly', TJSONBool.Create(True)); // referencia: se lee, no se toca
            // Which OTHER folders this project compiles against. Without it
            // nobody can explain how a test project with two units in its
            // uses builds against three from next door - it cost an agent a
            // call to delphi_config to find out (field round 11).
            if SameText(TPath.GetExtension(F), '.dproj') then
            begin
              var SP := ProjectSearchDirs(F);
              if Length(SP) > 0 then
              begin
                var SPArr := TJSONArray.Create;
                Entry.AddPair('compilesAgainst', SPArr);
                for var SDir in SP do
                  SPArr.Add(SDir);
              end;
            end;
            Repo := RepoOf(F, Branch);
            if (Repo <> '') and (Repos.IndexOf(Repo) < 0) then
            begin
              Repos.Add(Repo);
              Ramas.Add(Branch);
            end;
          end;
        end;
    end;
    Pag.Report(Return);
    if Pag.HayMas then
    begin
      Return.AddPair('note', MsgFmt(SN_PROJECTS_PAGE_FMT,
        [Pag.Mostrados, Pag.Total, Pag.Siguiente]));
      // Las 10 carpetas que mas acumulan, ordenadas: con esto el agente elige
      // "root" y deja de pasear paginas de cosas que no son suyas.
      PorCarpeta.Report(Return);
    end;
    if (Pag.Total = 0) and (Filt <> '') then
    begin
      // {"total":0} for a name that matches nothing reads as "this server has
      // no projects" (field round 10). Count them without the filter and say
      // which of the two it is.
      AllCount := 0;
      for RootDir in Roots do
        if (RootDir.Trim <> '') and TDirectory.Exists(RootDir.Trim) then
          for Mask in TArray<string>.Create('*.dproj', '*.groupproj') do
            for F in WalkFiles(RootDir.Trim, Mask) do
              if not (SkipIdeArtifacts(F) or InVault(F)) then
                Inc(AllCount);
      Return.AddPair('note', MsgFmt(SN_PROJECTS_NO_MATCH_FMT,
        [Params.Name.Trim, AllCount]));
    end;
    if Ocultos > 0 then
    begin
      Return.AddPair('hidden', TJSONNumber.Create(Ocultos));
      Return.AddPair('hiddenNote', MsgFmt(SN_PROJECTS_HIDDEN_FMT, [Ocultos]));
    end;
    if Saltadas <> '' then
      Return.AddPair('skippedRootsNote', MsgFmt(SN_PROJECTS_RAICES_SALTADAS_FMT, [Saltadas]));
    if Repos.Count > 0 then
    begin
      var RepoArr := TJSONArray.Create;
      Return.AddPair('repos', RepoArr);
      for var K := 0 to Repos.Count - 1 do
      begin
        var RO := TJSONObject.Create;
        RepoArr.AddElement(RO);
        RO.AddPair('dir', Repos[K]);
        if Ramas[K] <> '' then
          RO.AddPair('branch', Ramas[K]);
      end;
    end;
    // la lista conserva su nombre ('projects', como la de delphi_test
    // discover): solo files y dirs pasan a 'folders', porque se repetirian
    // dentro de cada carpeta (revisor de contrato de la 1.15.0)
    Lista.Cuelga(Return, 'projects');
    Result := Return.ToJSON;
  finally
    Ramas.Free;
    Repos.Free;
    Lista.Free;
    Return.Free;
  end;
end;

{ TDelphiFetchTool }

constructor TDelphiFetchTool.Create;
begin
  inherited;
  FName := 'delphi_fetch';
  FDescription := SD_FETCH;
end;

function TDelphiFetchTool.ExecuteWithParams(const Params: TDelphiFetchParams): string;
const
  MAX_CHUNK = 8 * 1024 * 1024;
  // Above SMALL_CHUNK the offset=0 answer carries the download link and NO
  // chunk (field 2026-08-21: a 72 MB installer pulled as base64 through a
  // 262K-token context). An explicit maxbytes <= SMALL_CHUNK is the opt-in
  // for inline chunks anyway (a client without a shell) - the parameter that
  // already exists doubles as the switch; nothing new to learn.
  // Era un umbral aparte de 4 MB: un zip de 1,37 MB llegaba entero en base64,
  // 3,6 millones de caracteres en la respuesta de un modelo (Hermes,
  // 5-oct-2026). Una medida para las dos cosas: lo que no cabe en un trozo
  // pequeno va por el enlace.
  SMALL_CHUNK = 1024 * 1024;
var
  FullPath, Sha: string;
  Stream: TFileStream;
  Size, ChunkLen: Int64;
  MaxB: Integer;
  Buf: TBytes;
  Return: TJSONObject;
  LinkOnly: Boolean;
begin
  // la guarda PRIMERO: con path vacio, GetFullPath lanzaba el texto de la
  // RTL ("Invalid characters in path"); la guarda dice que falta la ruta
  Result := ReadPathDenied(Params.Path); // downloading is reading
  if Result <> '' then
    Exit;
  FullPath := TPath.GetFullPath(Params.Path);
  Result := CarpetaEnVezDeFichero(FullPath);
  if Result <> '' then
    Exit;
  if not TFile.Exists(FullPath) then
    Exit(NoEsFichero(FullPath, MsgFmt(SR_WS_NO_EXISTE_FMT, [FullPath])));
  MaxB := Params.MaxBytes;
  if (MaxB <= 0) or (MaxB > MAX_CHUNK) then
    MaxB := MAX_CHUNK;
  if Params.Offset < 0 then
    Exit(MsgText(SR_WS_OFFSET_NEGATIVO));

  Stream := TFileStream.Create(FullPath, fmOpenRead or fmShareDenyWrite);
  try
    Size := Stream.Size;
    Sha := '';
    if Params.Offset = 0 then
      // Whole-file hash so the client can verify the reassembly. Cached by
      // (path, mtime, size): the /files download recomputed this same hash
      // right after, so one big zip was read end-to-end three times for one
      // download (hermes, release audit 2026-08-26).
      Sha := CachedFileSha256(FullPath);

    if Params.Offset > Size then
      Exit(MsgFmt(SR_WS_OFFSET_MAS_ALLA_FINAL_FMT, [Size]));
    LinkOnly := GFilesServed and (Size > SMALL_CHUNK) and (Params.Offset = 0) and
      ((Params.MaxBytes <= 0) or (Params.MaxBytes > SMALL_CHUNK));
    Stream.Position := Params.Offset;
    ChunkLen := Size - Params.Offset;
    if ChunkLen > MaxB then
      ChunkLen := MaxB;
    if LinkOnly then
      ChunkLen := 0;
    SetLength(Buf, ChunkLen);
    if ChunkLen > 0 then
      Stream.ReadBuffer(Buf[0], ChunkLen);

    Return := TJSONObject.Create;
    try
      Return.AddPair('path', FullPath);
      Return.AddPair('size', TJSONNumber.Create(Size));
      Return.AddPair('offset', TJSONNumber.Create(Params.Offset));
      Return.AddPair('bytes', TJSONNumber.Create(ChunkLen));
      Return.AddPair('eof', TJSONBool.Create(Params.Offset + ChunkLen >= Size));
      if Sha <> '' then
        Return.AddPair('sha256', Sha);
      if GFilesServed then
      begin
        // Relative on purpose: the client already knows the host:port it
        // talks to, and the server never guesses its own public address.
        // The path travels in its VIRTUAL form, URL-encoded (no real drive
        // letter ever leaves, encoded or not).
        Return.AddPair('download', DownloadLinkFor(FullPath));
        Return.AddPair('downloadNote', MsgText(SN_FETCH_DOWNLOAD));
      end;
      if LinkOnly then
        Return.AddPair('inline', TJSONBool.Create(False));
      // Una captura del escritorio se consume al recogerla ENTERA (David,
      // 25-sep-2026): recogida = ultimo trozo servido. Se dice en la
      // respuesta; una segunda peticion encontrara 'no existe'.
      if IsAgentCapture(FullPath) then
      begin
        // lo anuncia el MISMO decisor que borra (CapturaConsumible): una
        // captura de una referencia decia "consumida" y seguia en disco
        // (duodecima revision)
        var Consumida := (not LinkOnly) and (Params.Offset + ChunkLen >= Size) and
          CapturaConsumible(FullPath);
        Return.AddPair('consumedOnServer', TJSONBool.Create(Consumida));
        if Consumida then
          Return.AddPair('consumedNote', MsgText(SN_FETCH_CAPTURE_CONSUMED));
      end;
      if LinkOnly then
        Return.AddPair('note', MsgFmt(SN_FETCH_BIG_FMT,
          [FormatFloat('0.0', Size / (1024 * 1024), TFormatSettings.Invariant) + ' MB']))
      else
        Return.AddPair('chunkBase64', BytesToBase64(Buf)); // EL codificador de la casa
      Result := Return.ToJSON;
    finally
      Return.Free;
    end;
  finally
    Stream.Free;
  end;
  if (not LinkOnly) and (Params.Offset + ChunkLen >= Size) then
    ConsumeAgentCapture(FullPath); // ya servida entera: fuera del servidor
end;

{ TDelphiUploadTool }

constructor TDelphiUploadTool.Create;
begin
  inherited;
  FName := 'delphi_upload';
  FDescription := SD_WS_UPLOAD;
end;

function SubirNucleo(const Params: TDelphiUploadParams): string; forward;

function TDelphiUploadTool.ExecuteWithParams(const Params: TDelphiUploadParams): string;
begin
  // El cerrojo de escritura, como toda tool que escribe: un commit de
  // changeset que fallaba a mitad deshacia lo que esta tool escribia
  // entre medias, contestando OK a los dos (verificacion de la tercera
  // revision, 27-sep-2026, medido). Perder una edicion con OK es peor que
  // esperar (David).
  EnterFileEdit;
  try
    Result := SubirNucleo(Params);
  finally
    LeaveFileEdit;
  end;
end;

function SubirNucleo(const Params: TDelphiUploadParams): string;
var
  FullPath, Dir, Sha, Backup, Quarantine: string;
  Bytes: TBytes;
  Stream: TFileStream;
  Return: TJSONObject;
  Size, OldSize: Int64;
  Replaced: Boolean;
begin
  FullPath := TPath.GetFullPath(Params.Path);
  Result := WriteTargetDenied(FullPath); // writing: the strict jail + dead folders, never the library zone
  if Result <> '' then
    Exit;
  Result := CarpetaEnVezDeFichero(FullPath); // un fmCreate sobre una carpeta era un INTERNAL
  // ...y uno de solo lectura, SYS-006 INTERNAL "Cannot create file" (sexta revision)
  if Result = '' then
    Result := SoloLecturaDenegado(FullPath);
  if Result <> '' then
    Exit;
  if Params.Offset < 0 then
    Exit(MsgText(SR_WS_OFFSET_NEGATIVO));
  if SkipIdeArtifacts(LongCanonical(FullPath)) then
    Exit(MsgText(SR_WS_RUTA_ARTEFACTOS_IDE_HISTORY));
  // (las carpetas muertas: WriteTargetDenied, arriba)
  // An upload with no bytes is not an upload: the schema only demanded "path",
  // so a half-typed call landed here, opened the file with fmCreate and left
  // it at 0 bytes reporting success (field round 8). Nothing destructive may
  // ride on a call that carries no content.
  if (Params.Sha256.Trim <> '') and
     not TRegEx.IsMatch(Params.Sha256.Trim, '^[0-9A-Fa-f]{64}$') then
    Exit(MsgFmt(SR_UPLOAD_BAD_SHA_FMT, [Params.Sha256.Trim]));
  if (Params.ChunkSha256.Trim <> '') and
     not TRegEx.IsMatch(Params.ChunkSha256.Trim, '^[0-9A-Fa-f]{64}$') then
    Exit(MsgFmt(SR_UPLOAD_BAD_SHA_FMT, [Params.ChunkSha256.Trim]));
  if Params.ChunkBase64.Trim = '' then
  begin
    if TFile.Exists(FullPath) then
      Exit(MsgFmt(SR_UPLOAD_NO_CHUNK_FMT, [TFile.GetSize(FullPath)]));
    Exit(MsgText(SR_UPLOAD_NO_CHUNK_NEW));
  end;

  // EL decodificador de la casa (Lsp.Base64): alfabeto, longitud en grupos
  // de 4 y decodificacion, con el motivo si no. Delphi's decoder SKIPS
  // invalid characters instead of failing and takes any length: both wrote
  // a corrupt file that only the final sha caught (hermes, 2026-09-25).
  Result := Base64ToBytes(Params.ChunkBase64, 'chunkBase64', Bytes);
  if Result <> '' then
    Exit;

  // Per-chunk verification: a slip is caught at the chunk that carried it,
  // with nothing written, instead of at the end with the file in
  // quarantine (hermes, 2026-09-25).
  if Params.ChunkSha256.Trim <> '' then
  begin
    Sha := Sha256DeBytes(Bytes);
    if not SameText(Sha, Params.ChunkSha256.Trim) then
      Exit(MsgFmt(SR_UPLOAD_CHUNK_SHA_MISMATCH_FMT,
        [Sha, Params.ChunkSha256.Trim, Length(Bytes)]));
  end;

  // A designer this server cannot read is a designer nobody here can fix.
  // Measured 2026-08-25: upload was the one writer with no designer rule, and
  // an agent replaced a LIVE text .dfm of a compiling project with a 19-byte
  // TPF0 stream - lint then refused the file it had just written and the build
  // died in RLINK32. Every other writer refuses both binary shapes; this one
  // shipped them.
  if MatchText(TPath.GetExtension(FullPath), ['.dfm', '.fmx']) and
     IsBinaryDesignerBytes(Bytes) then // el nombrador de la forma: Lsp.DesignerBin
    Exit(MsgText(SR_UPLOAD_BINARY_DESIGNER));

  Dir := TPath.GetDirectoryName(FullPath);
  if (Dir <> '') and not TDirectory.Exists(Dir) then
    CrearCarpeta(Dir);

  // Non-destructive: a fresh upload (offset 0) TRUNCATES the target. If a file
  // is already there, copy it to the recoverable trash first - upload was the
  // only writer that could overwrite with no undo (field round 7). Skip the
  // trash's own tree so a backup never triggers another backup.
  Backup := '';
  // Solo se asignaban si el fichero ya existia: una subida NUEVA (o un
  // trozo con offset) podia contestar replaced=true con un previousSize
  // basura (W1036 en cada build, 26-sep).
  Replaced := False;
  OldSize := 0;
  if (Params.Offset = 0) and TFile.Exists(FullPath) then
  begin
    Replaced := True;
    OldSize := 0;
    try
      OldSize := TFile.GetSize(FullPath);
    except
    end;
    // Sin la copia de antes NO se escribe: se sustituia el fichero igual,
    // contestando exito con "backup FAILED" en un campo (quinta revision,
    // medido; sus gemelas se niegan). Perder es peor que no subir.
    if not SkipIdeArtifacts(FullPath, False) then
      try
        // la copia del contenido ACTUAL, sellada: la diaria (BackupFile) es
        // la de la primera version del dia y lo de despues se perdia (sexta revision)
        Backup := MaskDriveText('', GuardaContenidoActual(FullPath));
      except
        on E: Exception do
          Exit(MsgEnvuelve(SR_WS_FALLO_COPIA_SEGURIDAD_FMT, E.Message, [E.Message]));
      end;
  end;

  if Params.Offset = 0 then
    Stream := TFileStream.Create(FullPath, fmCreate)
  else
  begin
    if not TFile.Exists(FullPath) then
      Exit(MsgText(SR_WS_OFFSET_FICHERO_NO_EXISTE));
    Stream := TFileStream.Create(FullPath, fmOpenReadWrite or fmShareDenyWrite);
  end;
  try
    if Params.Offset > Stream.Size then
      Exit(MsgFmt(SR_WS_OFFSET_ENVIA_EN_ORDEN_FMT, [Params.Offset, Stream.Size]));
    // ...and an offset that lands INSIDE the file is just as wrong: the write
    // truncates whatever came after it, with no copy taken (this is not
    // offset=0, so the backup above did not run). Measured 2026-08-25: a
    // 14-byte file resumed at offset 5 came back 8 bytes long, six of them
    // gone and unrecoverable. Resuming means continuing at the END.
    if (Params.Offset > 0) and (Params.Offset < Stream.Size) then
      Exit(MsgFmt(SR_UPLOAD_OFFSET_INSIDE_FMT,
        [Params.Offset, Stream.Size, Stream.Size]));
    Stream.Position := Params.Offset;
    if Length(Bytes) > 0 then
      Stream.WriteBuffer(Bytes[0], Length(Bytes));
    Stream.Size := Stream.Position; // truncate any leftover from a previous file
    Size := Stream.Size;
  finally
    Stream.Free;
  end;

  Return := TJSONObject.Create;
  try
    Return.AddPair('path', FullPath);
    Return.AddPair('written', TJSONNumber.Create(Length(Bytes)));
    if Params.ChunkSha256.Trim <> '' then
      Return.AddPair('chunkVerified', TJSONBool.Create(True));
    Return.AddPair('size', TJSONNumber.Create(Size));
    Return.AddPair('nextOffset', TJSONNumber.Create(Size));
    // A fresh upload over an existing file REPLACES it. Say so, and say where
    // the previous content went: an agent that cannot see the copy assumes
    // there is none (measured, field round 8).
    if Replaced then
    begin
      Return.AddPair('replaced', TJSONBool.Create(True));
      Return.AddPair('previousSize', TJSONNumber.Create(OldSize));
      if Backup <> '' then
        Return.AddPair('backup', Backup);
      Return.AddPair('note', MsgFmt(SN_UPLOAD_REPLACED_FMT, [OldSize]));
    end;
    if Params.Sha256.Trim <> '' then
    begin
      Sha := CachedFileSha256(FullPath);
      Return.AddPair('sha256', Sha);
      Return.AddPair('verified', TJSONBool.Create(
        SameText(Sha, Params.Sha256.Trim)));
      if not SameText(Sha, Params.Sha256.Trim) then
      begin
        // The file on disk is now KNOWN to be wrong. Leaving it in place under
        // its real name means the next reader takes corruption for content:
        // park it aside and say where (field round 8).
        Quarantine := FullPath + '.corrupt';
        try
          // A second failed upload used to overwrite the first quarantine
          // with no copy at all - the one write path that did not respect
          // the trash (2026-08-25). Park the older one properly first.
          if TFile.Exists(Quarantine) then
          begin
            // sin su copia, la cuarentena de antes NO se borra: se perdia
            // (quinta revision). Si la copia falla, el fichero malo se queda
            // con su nombre y el error lo dice.
            GuardaContenidoActual(Quarantine); // la actual, sellada
            TFile.Delete(Quarantine);
          end;
          TFile.Move(FullPath, Quarantine);
          Return.AddPair('quarantined', Quarantine);
        except
          Quarantine := '';
        end;
        if Quarantine = '' then
          Quarantine := FullPath;
        Return.AddPair('error', MsgFmt(SR_UPLOAD_SHA_MISMATCH_FMT, [Quarantine]));
      end;
    end;
    Result := Return.ToJSON;
  finally
    Return.Free;
  end;
end;

{ TDelphiPackageTool }

constructor TDelphiPackageTool.Create;
begin
  inherited;
  FName := 'delphi_package';
  FDescription := SD_WS_PACKAGE;
end;

function TDelphiPackageTool.ExecuteWithParams(const Params: TDelphiPackageParams): string;
var
  Dir, OutZip, EnProceso, F, Rel: string;
  Zip: TZipFile;
  Return: TJSONObject;
  Count: Integer;
  TotalBytes: Int64;
begin
  // Without this the empty string reached TPath.GetFullPath and the dispatcher
  // wrapped an EArgumentException as "Error executing tool: Invalid characters
  // in path" - a crash where a missing parameter belonged (field round 8).
  if Params.Dir.Trim = '' then
    Exit(MsgText(SR_PACKAGE_NEED_DIR));
  Dir := TPath.GetFullPath(Params.Dir);
  Result := PathDenied(Dir);
  if Result <> '' then
    Exit;
  if not TDirectory.Exists(Dir) then
    if TFile.Exists(Dir) then
      Exit(MsgFmt(SR_LIST_IS_FILE_FMT, [Dir]))
    else
      Exit(MsgFmt(SR_WS_DIR_NOT_FOUND_FMT, [Dir]));

  if Params.OutFile <> '' then
    OutZip := TPath.GetFullPath(Params.OutFile)
  // la raiz de una unidad no tiene "al lado": el nombre por defecto quedaba
  // en "-deploy.zip" a secas y la negativa era la de una ruta relativa
  // (GUARD-021), que no decia que hacer (revision de la 1.9.0)
  else if TPath.GetFileName(SinBarraFinal(Dir)) = '' then
    Exit(MsgFmt(SR_PACKAGE_RAIZ_SIN_OUTFILE_FMT, [SinBarraFinal(Dir)]))
  else
    OutZip := TPath.Combine(TPath.GetDirectoryName(SinBarraFinal(Dir)),
      TPath.GetFileName(SinBarraFinal(Dir)) + '-deploy.zip');
  // el zip es un destino: la puerta de destino (jaula + carpetas muertas)
  Result := WriteTargetDenied(OutZip);
  if Result <> '' then
    Exit;
  // un outfile que es una CARPETA acababa en "alguien lo tiene abierto,
  // reintenta" - un bucle sin fin para quien obedece
  Result := CarpetaEnVezDeFichero(OutZip);
  if Result <> '' then
    Exit;
  // outfile=notas.txt la sustituia por un zip, sin copia y contestando exito
  // (tercera revision, 27-sep-2026, medido en vivo): el paquete es un .zip
  if not SameText(TPath.GetExtension(OutZip), '.zip') then
    Exit(MsgFmt(SR_PACKAGE_OUTFILE_ZIP_FMT, [OutZip]));
  // La carpeta del zip se crea, como en toda tool que escribe: una que no
  // existia o un FICHERO en el camino salian INTERNAL (GUARD-019 ahora, desde
  // CrearCarpeta). Y un .zip que ya estaba se copia antes de pisarlo: perder
  // es peor que una copia de mas (verificacion de la tercera ronda, David)
  CrearCarpeta(TPath.GetDirectoryName(OutZip));
  // El zip se arma con nombre propio y se pone en su sitio de un golpe al
  // final. Empaquetar sobre el nombre definitivo hacia que dos llamadas a la
  // vez sobre la misma carpeta se estorbasen - una borraba el zip que la otra
  // estaba escribiendo y saltaba "el proceso no tiene acceso al archivo"
  // (medido 2026-09-20). Ahora cada una arma el suyo y la ultima gana, entero.
  EnProceso := OutZip + '.' +
    FragmentoUnico + '.tmp';

  Count := 0;
  TotalBytes := 0;
  var Elfs := 0; // ejecutables de Linux (cabecera #$7F'ELF') que van dentro
  // Un zip que se cae a medias (SYS-027: un fichero que otro tiene abierto)
  // no deja su .tmp en el workspace: cada reintento dejaba otro (quinta
  // revision). El paquete es desechable; el temporal, mas.
  try
  Zip := TZipFile.Create;
  try
    Zip.Open(EnProceso, zmWrite);
    for F in WalkFiles(Dir, '*') do
    begin
      // Los temporales del servidor no son parte de ningun entregable:
      // ahi caen las capturas del escritorio del OPERADOR desde 1.0.12, y
      // este era el unico recorredor que las COPIABA fuera del workspace.
      // El formato se excluyo en cinco sitios y se olvido aqui
      // (auditoria 2026-09-21).
      if EnTemporal(F) then
        Continue;
      // un vault (de cualquier workspace) no va en un entregable: los otros
      // recorredores ya lo saltaban (octava revision)
      if InVault(F) then
        Continue;
      // ...ni la papelera: no es contenido (la regla de list y del copiador),
      // y un enlace aparcado en ella hacia que el zip se leyera a si mismo
      // (SYS-027 "repite" para siempre; octava revision)
      if EnPapelera(F) then
        Continue;
      if SameText(TPath.GetExtension(F), '.dcu') then
        Continue;
      if F.ToLower.Contains('\dcu\') then
        Continue;
      if SameText(TPath.GetFullPath(F), OutZip) or
         SameText(TPath.GetFullPath(F), EnProceso) then
        Continue;
      Rel := F.Substring(Length(IncludeTrailingPathDelimiter(Dir))).Replace('\', '/');
      Zip.Add(F, Rel);
      // Un zip hecho en Windows NO guarda permisos Unix: el binario de
      // Linux64 (un ELF, sin extension) sale del unzip sin el bit de
      // ejecucion y "no arranca" sin decir por que. Se cuentan para
      // avisarlo en la respuesta.
      if (TPath.GetExtension(F) = '') or SameText(TPath.GetExtension(F), '.so') then
        try
          var Fs := TFileStream.Create(F, fmOpenRead or fmShareDenyNone);
          try
            var Cab: array[0..3] of Byte;
            if (Fs.Read(Cab, 4) = 4) and (Cab[0] = $7F) and (Cab[1] = Ord('E')) and
               (Cab[2] = Ord('L')) and (Cab[3] = Ord('F')) and
               (TPath.GetExtension(F) = '') then
              Inc(Elfs);
          finally
            Fs.Free;
          end;
        except
          // no se pudo mirar: el aviso es una ayuda, no una condicion
        end;
      Inc(Count);
      Inc(TotalBytes, TFile.GetSize(F));
    end;
    Zip.Close;
  finally
    Zip.Free;
  end;
  except
    try
      if TFile.Exists(EnProceso) then
        TFile.Delete(EnProceso);
    except
    end;
    raise;
  end;
  // Un solo gesto del sistema: nadie ve nunca un zip a medias con el nombre
  // bueno (packages are disposable artifacts, always fresh). Reintentado unos
  // instantes: si DOS empaquetados del mismo sitio se cruzan, el destino esta
  // siendo reemplazado por el otro justo en ese momento y el rename rebota
  // (medido 2026-09-20 en la bateria de concurrencia).
  // Se COLOCA con el cerrojo de escritura, como todo escritor: la copia
  // sellada del .zip que habia y el rename, sin que otro escritor se cuele
  // entre los dos (sexta revision: dos empaquetados al mismo out= sellaban
  // la misma copia y el zip de en medio se perdia). Solo la colocacion: el
  // empaquetado, que tarda, no bloquea a nadie.
  var Renombrado := False;
  EnterFileEdit;
  try
    try
      GuardaContenidoActual(OutZip); // el .zip que habia, sellado (si lo habia)
    except
      try
        TFile.Delete(EnProceso);
      except
      end;
      raise;
    end;
    for var Intento := 1 to 5 do
    begin
      Renombrado := MoveFileEx(PChar(EnProceso), PChar(OutZip),
        MOVEFILE_REPLACE_EXISTING);
      if Renombrado then
        Break;
      Sleep(200);
    end;
  finally
    LeaveFileEdit;
  end;
  if not Renombrado then
  begin
    try
      TFile.Delete(EnProceso);
    except
    end;
    Exit(MsgFmt(SR_PACKAGE_RENAME_FMT, [OutZip]));
  end;

  Return := TJSONObject.Create;
  try
    Return.AddPair('zip', OutZip);
    Return.AddPair('filesCount', TJSONNumber.Create(Count)); // una cuenta: 'files' es una lista en la casa (1.15.0)
    Return.AddPair('uncompressedBytes', TJSONNumber.Create(TotalBytes));
    Return.AddPair('zipBytes', TJSONNumber.Create(TFile.GetSize(OutZip)));
    if Elfs > 0 then
      Return.AddPair('linuxNote', MsgFmt(SN_WS_LINUX_EXECUTABLES_FMT, [Elfs]));
    // The next step used to be prose and a model had to GUESS the zip
    // name (one invented Win64-Release-deploy.zip - hermes' blind eval).
    // Hand it the exact call instead.
    var NextCall := TJSONObject.Create;
    Return.AddPair('nextCall', NextCall);
    NextCall.AddPair('tool', 'delphi_fetch');
    var NextArgs := TJSONObject.Create;
    NextCall.AddPair('arguments', NextArgs);
    NextArgs.AddPair('path', OutZip);
    Return.AddPair('next', MsgText(SN_WS_DOWNLOAD_WITH_FETCH));
    Result := Return.ToJSON;
  finally
    Return.Free;
  end;
end;

initialization
  TMCPRegistry.RegisterTool('delphi_package',
    function: IMCPTool begin Result := TDelphiPackageTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_fetch',
    function: IMCPTool begin Result := TDelphiFetchTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_upload',
    function: IMCPTool begin Result := TDelphiUploadTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_search',
    function: IMCPTool begin Result := TDelphiSearchTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_projects',
    function: IMCPTool begin Result := TDelphiProjectsTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_installs',
    function: IMCPTool begin Result := TDelphiInstallsTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_workspace',
    function: IMCPTool begin Result := TDelphiWorkspaceTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_list',
    function: IMCPTool begin Result := TDelphiListTool.Create; end);
  GArranque := Now; // la unidad se inicializa al arrancar el proceso
  TMCPRegistry.RegisterTool('delphi_git',
    function: IMCPTool begin Result := TDelphiGitTool.Create; end);

end.
