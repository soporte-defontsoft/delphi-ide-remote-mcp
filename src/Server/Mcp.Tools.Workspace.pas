unit Mcp.Tools.Workspace;

{ Remote-work toolset: delphi_search, delphi_list, delphi_projects,
  delphi_installs, delphi_workspace, delphi_fetch, delphi_upload and
  delphi_package (delphi_git has a unit of its own since 8-oct-2026:
  Mcp.Tools.Git). Together with delphi_read/delphi_edit/delphi_build they
  give an agent on ANOTHER machine (e.g. Linux) full control of the Delphi
  projects living on this Windows box - no file share, no shell access.
  Paths in results are 1-based lines to match delphi_read numbering. }

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
  Lsp.Client,
  Lsp.Discovery,
  Lsp.References,
  Lsp.Listas, // TPagina, TPorCarpeta y el organizador de listas de ficheros
  Lsp.Guard,
  Lsp.Patch,
  Lsp.ShaCache,
  Lsp.Base64,     // BytesToBase64 / Base64ToBytes: el codificador de la casa
  Lsp.Dproj,      // RutasDeBusqueda: el search path de un .dproj, resuelto
  Lsp.Files,
  Mcp.Tools.Messages,
  Lsp.DesignerBin,
  Lsp.NetDrives, // SinBarraFinal
  Lsp.Pascal,
  Lsp.Regex, // TExprDelAgente: la expresion de delphi_search regex=true
  Lsp.Rutas,
  Lsp.Casa,
  Lsp.Settings,
  Lsp.Identidad,
  Lsp.Lugares,
  Lsp.Mascara;

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
  // reiniciar. Lo decide Lsp.Settings, el dueno del ini, que sabe lo que
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

end.
