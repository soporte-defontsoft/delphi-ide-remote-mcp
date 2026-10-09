unit Mcp.Tools.FileOps;

{ delphi_delete and delphi_move: remove or relocate files/folders inside the
  workspace, safely. delete is NOT a hard delete - the target is moved to a
  recoverable trash (__delphi-patch\<date>\deleted\...) next to it, the same
  place delphi_edit keeps its backups. move copies the source to trash first,
  then relocates it. Both are jailed and refused in read-only mode. }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Texts,   // SchemaDescription texts: attributes are interface-level
  Lsp.Attributes;  // [RutaDelServidor]: que parametro es una ruta NUESTRA

type
  TDelphiDeleteParams = class
  private
    FPath: string;
    FPurge: Boolean;
  public
    [SchemaDescription(SP_FILE_PATH)]
    [Required]
    [RutaDelServidor]
    property Path: string read FPath write FPath;
    [SchemaDescription(SP_DELETE_PURGE)]
    property Purge: Boolean read FPurge write FPurge;
  end;

  TDelphiMoveParams = class
  private
    FPath: string;
    FDest: string;
    FCopy: Boolean;
  public
    [SchemaDescription(SP_FILE_PATH_2)]
    [Required]
    [RutaDelServidor]
    property Path: string read FPath write FPath;
    [SchemaDescription(SP_FILE_DEST)]
    [Required]
    [RutaDelServidor]
    property Dest: string read FDest write FDest;
    [SchemaDescription(SP_MOVE_COPY)]
    property Copy: Boolean read FCopy write FCopy;
  end;

  TDelphiDeleteTool = class(TMCPToolBase<TDelphiDeleteParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiDeleteParams): string; override;
  public
    constructor Create; override;
  end;

  TDelphiMoveTool = class(TMCPToolBase<TDelphiMoveParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiMoveParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.RegularExpressions,
  MCPServer.Registration,
  Lsp.Guard,
  Lsp.Patch,
  Lsp.ProjectUnits,
  Lsp.Dproj,     // DprojDe: el .dproj de un .dpr/.dpk, un solo nombrador
  Lsp.NetDrives,
  Lsp.Pascal,
  Lsp.Scaffold,
  Lsp.Rutas,
  Lsp.Casa,
  Lsp.Identidad,
  Lsp.TodoONada;

function IsBackupPath(const APath: string): Boolean;
begin
  // inside the trash, OR the trash folder itself: EL lector de Lsp.Guard,
  // sobre la ruta larga (aqui se miraba el texto y __DELP~1 no era papelera)
  Result := EnPapelera(APath);
end;

{ The trash/backup folder ITSELF (…\__delphi-patch), not something inside it.
  Moving/deleting the trash itself is refused; moving an item OUT of it (a
  restore) is allowed. }
function IsBackupRoot(const APath: string): Boolean;
var
  EsLaCarpeta: Boolean;
begin
  Result := EnPapelera(APath, EsLaCarpeta) and EsLaCarpeta;
end;

{ Clear the read-only bit on a whole tree. Git marks every object file
  read-only, and Windows refuses to delete one - which is why deleting a
  folder holding a .git left an empty shell behind that no retry could ever
  remove, while every attempt copied the tree to the trash again (measured
  2026-08-25: five copies of the same folder). }
procedure ClearReadOnlyTree(const ADir: string);
var
  F: string;
begin
  try
    for F in TDirectory.GetFiles(ADir, '*', TSearchOption.soAllDirectories) do
      try
        if (TFile.GetAttributes(F) * [TFileAttribute.faReadOnly]) <> [] then
          TFile.SetAttributes(F, TFile.GetAttributes(F) - [TFileAttribute.faReadOnly]);
      except
        // one stubborn file must not stop the rest
      end;
  except
    // an unreadable tree is handled by the caller, which checks the result
  end;
end;

{ El gemelo designer de una unit: al lado, si es un fichero vivo; y buscando
  por el nombre ORIGINAL si venimos de la papelera, donde cada copia lleva SU
  propio sello de hora - el del .dfm no es el del .pas, se guardaron con
  milisegundos distintos (medido: .pas-215825250 junto a .dfm-215825248). Por
  eso aqui no vale calcular el nombre: hay que buscarlo. '' si no hay gemelo. }
function DesignerJunto(const ASrc, AStem, AExt: string;
  ADesdePapelera: Boolean): string;
var
  Dir, Mejor: string;
begin
  Result := '';
  if not ADesdePapelera then
  begin
    if TFile.Exists(ChangeFileExt(ASrc, AExt)) then
      Result := ChangeFileExt(ASrc, AExt);
    Exit;
  end;
  Dir := TPath.GetDirectoryName(ASrc);
  Mejor := '';
  try
    for var F in TDirectory.GetFiles(Dir, AStem + AExt + '-*') do
    begin
      // ".by" es el marcador de quien lo tiro, no el fichero
      if EsMarcaDeDueno(F) then
        Continue;
      if (Mejor = '') or (TFile.GetLastWriteTime(F) > TFile.GetLastWriteTime(Mejor)) then
        Mejor := F;
    end;
  except
    Exit('');
  end;
  Result := Mejor;
end;

{ La copia en la papelera de algo que al final no se hizo (un move que
  fallo, el form de un borrado de unit que se deshizo), fuera: es nuestra y
  recien hecha, y dejarla sumaba una copia por reintento; con su marca de
  dueno y las carpetas que se crearon para ella (octava revision). Nunca
  lanza. }
{ Quita la marca de dueno (.by) de una copia de la papelera, si la tiene.
  Nunca lanza: una marca que se queda es inofensiva. UNO: estaba a mano en
  cuatro sitios (novena revision). }
procedure QuitaMarcaDeDueno(const ACopia: string);
begin
  try
    if TFile.Exists(MarcaDeDueno(ACopia)) then
      TFile.Delete(MarcaDeDueno(ACopia));
  except
  end;
end;

procedure QuitaCopiaDeSeguridad(const ACopia, AAncestro: string);
begin
  if ACopia = '' then
    Exit;
  try
    if TDirectory.Exists(ACopia) then
      BorraArbol(ACopia)
    else if TFile.Exists(ACopia) then
      BorraLoNuestro(ACopia); // la copia de un +R es +R (decima revision)
  except
    // se queda: es una copia en la papelera, no hace dano
  end;
  QuitaMarcaDeDueno(ACopia);
  QuitaCarpetasCreadas(ExtractFileDir(ACopia), AAncestro);
end;

procedure MoveToTrash(const APath: string; out ATrash, AAncestro: string); overload;
var
  Ancestro: string;
begin
  // un FICHERO de solo lectura no se borra, como no se edita ni se pisa
  // (SYS-029: puede ser deliberado); el changeset delete ya lo decia y
  // delphi_delete lo borraba: UNA regla (septima revision)
  if TFile.Exists(APath) then
  begin
    var Motivo := SoloLecturaDenegado(APath);
    if Motivo <> '' then
      raise Exception.Create(Motivo);
  end;
  ATrash := TrashPathFor(APath, CAJON_BORRADOS);
  Ancestro := PrimerAncestroQueExiste(TPath.GetDirectoryName(ATrash));
  CrearCarpeta(TPath.GetDirectoryName(ATrash));
  try
    if TDirectory.Exists(APath) then
      // EL mudador (Lsp.Guard): renombrar o nada, con su guard. Nacio AQUI el
      // 2026-08-25 (TDirectory.Move, al no poder renombrar, copiaba y borraba
      // por su cuenta y vacio en la papelera una carpeta bloqueada) y se quedo
      // aqui solo: delphi_move siguio un mes con TDirectory.Move y se trajo a
      // la jaula y BORRO lo de detras de un junction (2026-09-25).
      MueveArbol(APath, ATrash)
    else
      TFile.Move(APath, ATrash);
  except
    // un borrado que no se hizo no deja su cajon del dia vacio (FILE-036
    // decia "no he tocado NADA" con deleted\ recien creado; septima)
    QuitaCarpetasCreadas(TPath.GetDirectoryName(ATrash), Ancestro);
    raise;
  end;
  // Who trashed it, so a later purge can be told "yours only". A file with no
  // marker (or an unknown agent) is nobody's in particular and any caller may
  // purge it - which keeps the operator's own cleanup, and stdio, working.
  WriteOwnerMarker(ATrash);
  AAncestro := Ancestro; // para quien tenga que deshacerlo (QuitaCopiaDeSeguridad)
end;

procedure MoveToTrash(const APath: string; out ATrash: string); overload;
var
  Ancestro: string;
begin
  MoveToTrash(APath, ATrash, Ancestro);
end;

{ Who else's work is inside this purge, '' when none.

  Measured 2026-08-25 by a probe agent: the per-FILE check below worked, so it
  purged the DATE FOLDER instead and took every agent's copies inside with it -
  the check asked for "<folder>.by", which never exists, read that as "nobody's"
  and deleted the tree. A guard that only looks at the path it was handed is no
  guard on a recursive delete. Now a folder is refused if it holds a single
  marker belonging to somebody else, and it names them. }
function PurgeOwnershipDenied(const APathIn: string): string;
var
  Me, Owner, F, Sib, APath: string;
  Others: TStringList;
begin
  Result := '';
  APath := LongCanonical(APathIn);
  Me := CurrentAgent;
  // No identity (stdio, the operator's own console) is trusted with everything.
  if Me = '' then
    Exit;
  if TFile.Exists(APath) then
  begin
    Owner := TrashOwner(APath);
    if (Owner <> '') and not SameText(Owner, Me) then
      Result := MsgFmt(SR_FILE_PURGE_NOT_YOURS_FMT, [Owner]);
    Exit;
  end;
  if not TDirectory.Exists(APath) then
    Exit;
  Others := TStringList.Create;
  try
    Others.Duplicates := dupIgnore;
    Others.Sorted := True;
    for F in WalkFiles(APath, MascaraDeMarcas) do
    begin
      // A marker only OWNS the copy sitting next to it. An orphan .by (its copy
      // already restored or purged) or a file someone just renamed to .by marks
      // nothing - counting its content as an owner let a planted .by make a
      // whole folder unpurgeable by anyone (measured 2026-08-25).
      Sib := CopiaDeLaMarca(F);
      if not (TFile.Exists(Sib) or TDirectory.Exists(Sib)) then
        Continue;
      Owner := TrashOwner(Sib);
      if (Owner <> '') and not SameText(Owner, Me) then
        Others.Add(Owner);
    end;
    if Others.Count > 0 then
      Result := MsgFmt(SR_FILE_PURGE_FOLDER_NOT_YOURS_FMT,
        [Others.Count, Others.CommaText]);
  finally
    Others.Free;
  end;
end;

{ Whether anything is still standing where the caller asked us to delete. }
function StillThere(const APath: string): Boolean;
begin
  Result := TFile.Exists(APath) or TDirectory.Exists(APath);
end;

{ Borrar DE VERDAD, sin papelera: una carpeta por el borrador con guard
  (no cruza enlaces: el junction cae como entrada y su destino ni se
  mira), un fichero quitandole antes el solo-lectura. '' si ya no esta;
  si no, la negativa. Los dos unicos sitios de donde algo se va para
  siempre lo comparten: la purga de la papelera y el borrado dentro de una
  temporal del servidor. }
function BorraDeVerdad(const APath: string): string;
begin
  Result := '';
  try
    if TDirectory.Exists(APath) then
      // La RTL recursiva entraba y borraba AL OTRO LADO de un junction
      // (2026-09-21): BorraArbol no.
      BorraArbol(APath)
    else
      BorraLoNuestro(APath);
  except
    on E: Exception do
      Exit(MsgFmt(SR_FILE_PURGE_FAILED_FMT,
        [TPath.GetFileName(SinBarraFinal(APath)), E.Message]));
  end;
  if StillThere(APath) then
    Result := MsgFmt(SR_FILE_PURGE_FAILED_FMT,
      [TPath.GetFileName(SinBarraFinal(APath)),
       MsgText(SF_FILE_SIGUE_AHI_DESPUES_BORRARLO)]);
end;

{ Las carpetas de la papelera que una purga deja VACIAS, de abajo arriba y
  hasta la propia papelera: purgar la ultima copia dejaba "deleted", la del
  dia y __delphi-patch en la raiz para siempre (vistas en la raiz de un NAS,
  1-oct-2026). RemoveDir solo quita una carpeta vacia (y de un enlace, el
  enlace): se para en la primera que no lo esta, y nunca sube de la papelera. }
procedure RecogeVacias(const ADesde: string);
var
  P: string;
  EsLaPapelera: Boolean;
begin
  P := SinBarraFinal(ADesde);
  while (P <> '') and IsBackupPath(P) do
  begin
    EsLaPapelera := IsBackupRoot(P);
    // un ENLACE no es una carpeta vacia: RemoveDir lo quitaria tenga lo que
    // tenga detras (revision de la 1.9.0). Ahi se para
    if EsEnlace(P) or not RemoveDir(P) then
      Break;
    if EsLaPapelera then
      Break;
    P := TPath.GetDirectoryName(P);
  end;
end;

{ TDelphiDeleteTool }

constructor TDelphiDeleteTool.Create;
begin
  inherited;
  FName := 'delphi_delete';
  FDescription := SD_FILE_DELETE;
end;

function BorrarNucleo(const Params: TDelphiDeleteParams): string; forward;

function TDelphiDeleteTool.ExecuteWithParams(const Params: TDelphiDeleteParams): string;
begin
  // El cerrojo de escritura, como toda tool que escribe: un commit de
  // changeset que fallaba a mitad deshacia lo que esta tool escribia
  // entre medias, contestando OK a los dos (verificacion de la tercera
  // revision, 27-sep-2026, medido). Perder una edicion con OK es peor que
  // esperar (David).
  EnterFileEdit;
  try
    Result := BorrarNucleo(Params);
  finally
    LeaveFileEdit;
  end;
end;

function BorrarNucleo(const Params: TDelphiDeleteParams): string;
var
  Denied, Trash, ProjNote, DesignerNote, P, R, Ext: string;
  Projects: TArray<string>;
  // borrar una UNIT es todo o nada: sus proyectos, su form y ella
  FotoUnit: TFotoDeFicheros;
  HayFotoUnit: Boolean;
  // las copias del form en la papelera y desde donde crearon carpetas
  CopiasForm, AncestrosForm: TArray<string>;

  { Lo que ya habia cambiado vuelve, y la respuesta lo dice con la causa. }
  function DeshaceUnit(const ACausa: string): string;
  var
    NoVolvio: string;
    I: Integer;
  begin
    NoVolvio := FotoUnit.Restaura;
    // algo no volvio: la copia de la papelera se queda, puede ser la unica
    if NoVolvio <> '' then
      Exit(MsgFmt(SR_FOTO_NO_VOLVIO_FMT, [NoVolvio, ACausa]));
    // el form volvio de la foto: su copia en la papelera sobra (se
    // quedaba suelta en deleted\; octava revision)
    for I := 0 to High(CopiasForm) do
      QuitaCopiaDeSeguridad(CopiasForm[I], AncestrosForm[I]);
    Result := MsgConCausa(SR_FILE_UNIT_DESHECHO_FMT, ACausa,
      [TPath.GetFileName(Params.Path), ACausa]);
  end;

begin
  HayFotoUnit := False;
  CopiasForm := [];
  AncestrosForm := [];
  Denied := PathDenied(Params.Path);
  if Denied <> '' then
    Exit(Denied);
  // PURGE: the one way anything leaves for good, and it only reaches INSIDE
  // the trash. The rule that a live file always goes to the recoverable copy
  // first is what makes every other write safe, so it does not bend; but an
  // agent that made a mess had no way to clean it up, and five of them in one
  // day left 112 MB of copies nobody could remove through MCP (measured
  // 2026-08-25). Worse, a file that should never have existed survived its
  // own delete, still inside the jail and still downloadable.
  if Params.Purge then
  begin
    if not IsBackupPath(Params.Path) then
      Exit(MsgText(SR_FILE_PURGE_ONLY_TRASH));
    // ...y que este en la papelera DE VERDAD, no solo por su texto: un enlace
    // que se borra va a la papelera como enlace, y un fichero nombrado a
    // traves de el es el VIVO de detras. Se purgaba - borrado para siempre,
    // sin copia, con un "it was a copy in the trash" (medido en la revision
    // de la 1.9.0). El enlace mismo si esta alli: se juzga por donde esta.
    try
      if not IsBackupPath(RutaDelEnlace(SinBarraFinal(TPath.GetFullPath(Params.Path)))) then
        Exit(MsgText(SR_FILE_PURGE_ONLY_TRASH));
    except
      Exit(MsgText(SR_FILE_PURGE_ONLY_TRASH)); // lo que no se puede resolver no se purga
    end;
    if IsBackupRoot(Params.Path) then
      Exit(MsgText(SR_FILE_PURGE_NOT_ROOT));
    if not (TFile.Exists(Params.Path) or TDirectory.Exists(Params.Path)) then
      Exit(MsgFmt(SR_NO_EXISTE_FMT, [Params.Path]));
    var CanonPurge := LongCanonical(Params.Path);
    if EsMarcaDeDueno(CanonPurge) then
    begin
      // A live marker for someone else's copy is off limits - removing it would
      // orphan their copy for the taking. But an orphan marker (copy already
      // restored/purged) or your own is yours to sweep: otherwise the trash
      // could never be left clean by the agent that made it.
      var SibMk := CopiaDeLaMarca(CanonPurge);
      var Mk := TrashOwner(SibMk); // owner is THIS marker's content
      if (TFile.Exists(SibMk) or TDirectory.Exists(SibMk)) and
         (CurrentAgent <> '') and (Mk <> '') and not SameText(Mk, CurrentAgent) then
        Exit(MsgFmt(SR_FILE_PURGE_NOT_YOURS_FMT, [Mk]));
    end
    else
    begin
      // Yours only - and on a folder, that means everything inside it too.
      Denied := PurgeOwnershipDenied(Params.Path);
      if Denied <> '' then
        Exit(Denied);
    end;
    Denied := BorraDeVerdad(Params.Path);
    if Denied <> '' then
      Exit(Denied);
    QuitaMarcaDeDueno(Params.Path);
    RecogeVacias(TPath.GetDirectoryName(SinBarraFinal(CanonPurge)));
    Exit(MsgFmt(SN_FILE_PURGED_FMT,
      [TPath.GetFileName(SinBarraFinal(Params.Path))]));
  end;
  // De un temporal no se restaura nada (lo dicen la purga del arranque y
  // los listados): la copia a la papelera era un temporal mas, guardado
  // DENTRO de la propia temporal y escondido de todo listado hasta la
  // siguiente purga (visto el 26-sep-2026 al limpiar dos capturas de 6 MB).
  // Se borra de verdad, y ANTES de la regla de la papelera: una papelera
  // que ya este dentro de una temporal es un temporal mas. La carpeta de
  // temporales misma no: es de todos los agentes del servidor y se vacia
  // sola al arrancar.
  var EsLaTemporal: Boolean;
  if EnTemporal(Params.Path, EsLaTemporal) then
  begin
    if EsLaTemporal then
      Exit(MsgFmt(SR_FILE_DELETE_TEMP_ROOT_FMT, [Params.Path]));
    if not StillThere(Params.Path) then
      Exit(MsgFmt(SR_NO_EXISTE_FMT, [Params.Path]));
    Denied := BorraDeVerdad(Params.Path);
    if Denied <> '' then
      Exit(Denied);
    Exit(MsgFmt(SN_FILE_DELETE_TEMP_FMT,
      [TPath.GetFileName(SinBarraFinal(Params.Path))]));
  end;
  if IsBackupPath(Params.Path) then
    Exit(MsgFmt(SR_FILE_PAPELERA_NO_SE_BORRA_FMT, [TrashFolderName]));
  if not (TFile.Exists(Params.Path) or TDirectory.Exists(Params.Path)) then
    Exit(MsgFmt(SR_NO_EXISTE_FMT, [Params.Path]));
  // Una carpeta a la papelera se lleva TODO lo de dentro: ni ser ni contener
  // una raiz, una referencia o una carpeta de solo lectura. La puerta de
  // arriba solo mira la ruta que le pasan (2026-09-25). Tambien la vacia:
  // una raiz de otro workspace sin nada dentro sigue siendo suya.
  if TDirectory.Exists(Params.Path) then
  begin
    Denied := ProtegidoDenegado(Params.Path);
    if Denied <> '' then
      Exit(Denied);
  end;
  // An empty folder needs no copy: retrying a half-finished delete used to
  // dump the (empty) tree into the trash again on every attempt.
  if TDirectory.Exists(Params.Path) and
     (Length(TDirectory.GetFileSystemEntries(Params.Path)) = 0) then
  begin
    // la carpeta VACIA no pasa por el mudador: lo NUESTRO se suelta aqui. Una
    // carpeta que algo de fuera vacio (git, al cambiar de rama) con el motor
    // dentro era un cascaron que no se dejaba quitar (29-sep-2026)
    SueltaLoNuestroBajo(Params.Path);
    try
      ClearReadOnlyTree(Params.Path);
      try
        TDirectory.Delete(Params.Path, False);
      except
        // fall through to the honest report below
      end;
    finally
      YaNoSeQuita(Params.Path);
    end;
    if not TDirectory.Exists(Params.Path) then
      Exit(MsgFmt(SN_FILE_DELETE_EMPTY_OK_FMT,
        [TPath.GetFileName(SinBarraFinal(Params.Path))]));
    Exit(MsgFmt(SR_FILE_DELETE_STUCK_FMT,
      [TPath.GetFileName(SinBarraFinal(Params.Path))]));
  end;
  ProjNote := '';
  DesignerNote := '';
  if TFile.Exists(Params.Path) and (TPath.GetExtension(Params.Path).ToLower = '.pas') then
  begin
    // a unit: take it out of the projects that list it (while the .pas is
    // still readable, so the form class/variable are known), then trash the
    // designer pair with it.
    Projects := ProjectsUsingUnit(Params.Path);
    // TODO O NADA (quinta revision): un .dproj que otro proceso tenia abierto
    // dejaba el .dpr cambiado y la unit borrada, con un exito que escondia el
    // error. La foto: cada proyecto (.dpr/.dpk y su .dproj) y el form.
    var RutasFoto: TArray<string> := [];
    for P in Projects do
      RutasFoto := RutasFoto + [P, DprojDe(P)];
    for Ext in DESIGNER_EXTS do
      RutasFoto := RutasFoto + [ChangeFileExt(Params.Path, Ext)];
    FotoUnit.Toma(RutasFoto);
    HayFotoUnit := True;
    for P in Projects do
    begin
      if PathDenied(P) <> '' then
      begin
        ProjNote := ProjNote + #10 + MsgFmt(SN_FILE_PROJECT_DENIED_FMT, [TPath.GetFileName(P)]);
        Continue;
      end;
      try
        FotoUnit.Vigila(P);
        R := RemoveProjectUnit(P, Params.Path, True);
      except
        on E: Exception do
          Exit(DeshaceUnit(MsgExcepcion(E.ClassName, E.Message)));
      end;
      if EsFallo(R) then
        Exit(DeshaceUnit(R));
      FotoUnit.Anota(P);
      FotoUnit.Anota(DprojDe(P));
      ProjNote := ProjNote + #10 + '    ' + TPath.GetFileName(P) + ': ' + R.Replace(#10, ' ');
    end;
    if Length(Projects) > 0 then
      ProjNote := MsgFmt(SN_FILE_PROJECTS_UPDATED_FMT, [Length(Projects),
        string.Join(', ', Projects)]) + ProjNote
    else
      ProjNote := MsgText(SN_FILE_PROJECTS_NONE);
    for Ext in DESIGNER_EXTS do
      if TFile.Exists(ChangeFileExt(Params.Path, Ext)) then
      try
        var AncestroForm: string;
        MoveToTrash(ChangeFileExt(Params.Path, Ext), Trash, AncestroForm);
        CopiasForm := CopiasForm + [Trash];
        AncestrosForm := AncestrosForm + [AncestroForm];
        FotoUnit.Anota(ChangeFileExt(Params.Path, Ext));
        DesignerNote := MsgFmt(SN_FILE_DESIGNER_TOO_FMT,
          [TPath.GetFileName(ChangeFileExt(Params.Path, Ext)), MsgText(SF_FILE_TAMBIEN_A_PAPELERA)]);
      except
        on E: Exception do
          Exit(DeshaceUnit(MsgExcepcion(E.ClassName, E.Message)));
      end;
  end
  else if TDirectory.Exists(Params.Path) then
  begin
    // UNA CARPETA ENTERA: cada unit de dentro sale de los proyectos que la
    // listan, igual que una unit suelta. Se borraba la carpeta, se contestaba
    // "BORRADO" y el .dpr seguia listando units que ya no estaban: build roto
    // con F1026 y una respuesta de exito (medido en vivo el 2026-09-21, el
    // gemelo de lo que le pasaba a delphi_move). Un proyecto que vive DENTRO
    // de la carpeta se va con ella: no se toca.
    var Raiz := IncludeTrailingPathDelimiter(TPath.GetFullPath(Params.Path));
    var Cuantas := 0;
    // TODO O NADA, como la unit suelta (sexta revision): las units salian de
    // sus proyectos y, si luego no se podia mover la carpeta, la respuesta
    // decia "no he tocado NADA" con los .dpr/.dproj ya cambiados. Primero se
    // ven TODOS los pares proyecto-unit, se toma la foto de cada proyecto, y
    // un fallo en cualquiera lo deshace todo.
    var ProyPares, UnitPares: TArray<string>;
    var UnitsDentro: TArray<string> := [];
    try
      UnitsDentro := TDirectory.GetFiles(Params.Path, '*.pas',
        TSearchOption.soAllDirectories);
    except
      // una subcarpeta ilegible no impide borrar: se miran las que se ven
    end;
    var Fotos := TStringList.Create;
    try
      try
        Fotos.Sorted := True;
        Fotos.Duplicates := dupIgnore;
        for var U in UnitsDentro do
        begin
          if IsBackupPath(U) then
            Continue;
          for P in ProjectsUsingUnit(U) do
          begin
            if StartsText(Raiz, IncludeTrailingPathDelimiter(
                 TPath.GetDirectoryName(TPath.GetFullPath(P)))) then
              Continue;
            ProyPares := ProyPares + [P];
            UnitPares := UnitPares + [U];
            Fotos.Add(P);
            Fotos.Add(DprojDe(P));
          end;
        end;
        FotoUnit.Toma(Fotos.ToStringArray);
        HayFotoUnit := True;
      except
        // un proyecto que no se deja leer (otro proceso lo tiene) NO es
        // "ningun proyecto la lista": el except de fuera se lo tragaba, se
        // decia BORRADO y el .dpr seguia listando la unit (novena revision).
        // Todavia no se ha tocado nada
        on E: Exception do
          Exit(MsgExcepcion(E.ClassName, E.Message));
      end;
    finally
      Fotos.Free;
    end;
    for var I := 0 to High(ProyPares) do
    begin
      P := ProyPares[I];
      if PathDenied(P) <> '' then
        R := MsgFmt(SN_FILE_PROJECT_DENIED_FMT, [TPath.GetFileName(P)])
      else
      begin
        try
          FotoUnit.Vigila(P);
          R := RemoveProjectUnit(P, UnitPares[I], True);
        except
          on E: Exception do
            Exit(DeshaceUnit(MsgExcepcion(E.ClassName, E.Message)));
        end;
        if EsFallo(R) then
          Exit(DeshaceUnit(R));
        FotoUnit.Anota(P);
        FotoUnit.Anota(DprojDe(P));
      end;
      Inc(Cuantas);
      ProjNote := ProjNote + #10 + '    ' + TPath.GetFileName(P) + ': ' + R.Replace(#10, ' ');
    end;
    if Cuantas > 0 then
      ProjNote := MsgFmt(SN_FILE_UNITS_CARPETA_QUITADAS_FMT,
        [Cuantas]) + ProjNote;
  end;
  try
    MoveToTrash(Params.Path, Trash);
  except
    on E: Exception do
    begin
      // A locked FOLDER move fails as a whole and leaves the tree intact: say so
      // plainly, because "error" used to read as "and who knows what it did".
      if TDirectory.Exists(Params.Path) then
      begin
        // ...y los proyectos de fuera que ya soltaron sus units vuelven a
        // listarlas: "no he tocado NADA" tiene que ser verdad
        if HayFotoUnit then
        begin
          var NoVolvio := FotoUnit.Restaura;
          if NoVolvio <> '' then
            Exit(MsgFmt(SR_FOTO_NO_VOLVIO_FMT, [NoVolvio, E.Message]));
        end;
        // la CAUSA manda, como en sus gemelas (el fichero suelto, delphi_move):
        // una negativa con etiqueta (la papelera enlazada, un enlace a un
        // antepasado) sale tal cual; "algo la tiene abierta" solo si Windows
        // dijo eso; otro fallo, con su texto. Se decia "cierralo y repite" de
        // todo, tambien de una ruta demasiado larga (septima revision)
        if EsFallo(E.Message) then
          Exit(E.Message);
        if MotivoDelSistema(E.Message) <> '' then
          Exit(MsgFmt(SR_FILE_DELETE_LOCKED_FMT,
            [TPath.GetFileName(SinBarraFinal(Params.Path)),
             E.Message]));
        Exit(MsgFmt(SR_FILE_CARPETA_NO_MOVIDA_FMT,
          [TPath.GetFileName(SinBarraFinal(Params.Path)),
           E.Message]));
      end;
      // una unit: sus proyectos y su form vuelven (todo o nada)
      if HayFotoUnit then
        Exit(DeshaceUnit(MsgExcepcion(E.ClassName, E.Message)));
      if (ProjNote <> '') or (DesignerNote <> '') then
        Exit(MsgFmt(SR_FILE_PARTIAL_FMT, [MsgText(SF_FILE_AL_MOVER_PAPELERA), E.Message,
          #10 + DesignerNote + #10 + ProjNote]));
      Exit(MsgEnvuelve(SR_FILE_ERROR_MOVER_PAPELERA_FMT, E.Message));
    end;
  end;
  // Say BORRADO only if it is gone. An auditor working through MCP found a
  // folder still standing after a cheerful "BORRADO ... movido a la papelera"
  // (2026-08-25): the copy had been made, the original had not gone, and
  // nothing in the answer said so. A delete that half-happened must read as a
  // delete that half-happened.
  if StillThere(Params.Path) then
  begin
    // "the original could NOT be taken away" read as "nothing happened",
    // while in fact the whole content had already moved out and only the
    // empty shell was left (measured 2026-08-25). Say which of the two it is.
    if TDirectory.Exists(Params.Path) and
       (Length(TDirectory.GetFileSystemEntries(Params.Path)) = 0) then
      Result := MsgFmt(SN_FILE_DELETE_EMPTY_SHELL_FMT,
        [TPath.GetFileName(SinBarraFinal(Params.Path)), Trash])
    else
      Result := MsgFmt(SR_FILE_DELETE_PARTIAL_FMT,
        [TPath.GetFileName(SinBarraFinal(Params.Path)), Trash]);
    if DesignerNote <> '' then
      Result := Result + #10 + DesignerNote;
    if ProjNote <> '' then
      Result := Result + #10 + ProjNote;
    Exit;
  end;
  Result := MsgFmt(SK_FILE_BORRADO_PAPELERA_FMT,
    [TPath.GetFileName(SinBarraFinal(Params.Path)), Trash]);
  if DesignerNote <> '' then
    Result := Result + #10 + DesignerNote;
  if ProjNote <> '' then
    Result := Result + #10 + ProjNote;
end;

{ TDelphiMoveTool }

constructor TDelphiMoveTool.Create;
begin
  inherited;
  FName := 'delphi_move';
  FDescription := SD_FILE_MOVE;
end;

function MoverNucleo(const Params: TDelphiMoveParams): string; forward;

function TDelphiMoveTool.ExecuteWithParams(const Params: TDelphiMoveParams): string;
begin
  // El cerrojo de escritura, como toda tool que escribe: un commit de
  // changeset que fallaba a mitad deshacia lo que esta tool escribia
  // entre medias, contestando OK a los dos (verificacion de la tercera
  // revision, 27-sep-2026, medido). Perder una edicion con OK es peor que
  // esperar (David).
  if Params.Copy then // una copia no toca lo de nadie y puede ser grande
    Exit(MoverNucleo(Params));
  EnterFileEdit;
  try
    Result := MoverNucleo(Params);
  finally
    LeaveFileEdit;
  end;
end;

function MoverNucleo(const Params: TDelphiMoveParams): string;
var
  Denied, BackupNote, Ext, Enc, Src, OldStem, NewStem, ProjNote, P, R, PairNote: string;
  Projects, NoSeguidos, NoSegCopia: TArray<string>;
  IsUnit: Boolean;
  AncestroCopia, CarpetaDestino, AncestroDestino: string;
  // los designers ya movidos (de, a) y la foto de lo que se reescribe: mover
  // una UNIT es todo o nada, como borrarla
  DisenosDe, DisenosA: TArray<string>;
  FotoUnit: TFotoDeFicheros;
  // la copia diaria que deja la reescritura de la cabecera: si el move se
  // deshace, se va con el (un move que no se hizo no deja copias; la
  // carpeta de destino se quedaba por ella)
  CopiaCabecera, AncestroCabecera: string;
  HabiaCopiaCabecera: Boolean;

  { La mudanza de las rutas relativas (ReubicaArbol), AL FINAL: con el
    designer ya junto a la unit y la cabecera reescrita, que es lo que
    RenameProjectUnit lee. Iba antes: un proyecto HERMANO perdia el nombre
    del form, y un rename fallaba y se contaba como hecho (revision del
    26-sep-2026). Es tambien lo que re-apunta las units de una CARPETA en
    los proyectos de fuera: aqui habia un recorrido propio, y eran dos. }
  function Reubicacion(ADesdePapelera: Boolean): string;
  begin
    Result := '';
    if ADesdePapelera or not (TDirectory.Exists(Params.Dest) or TFile.Exists(Params.Dest)) then
      Exit;
    var Reubica := ReubicaArbol(Params.Path, Params.Dest, Params.Copy);
    if Reubica <> '' then
      Result := #10 + Reubica;
  end;

  { TODO O NADA: lo que el move ya reescribio vuelve de la foto (la cabecera
    en el destino, los proyectos), los designers ya movidos y la unit vuelven
    (o sus copias se quitan), y la respuesta es el rechazo. Lo que NO vuelve
    se dice (SYS-018) con la causa sola. Era el deshacer del form (MOVE-017)
    en linea; un proyecto que no se dejaba re-apuntar no deshacia nada. }
  function DeshaceMove(const ARechazo, ACausa: string): string;
  var
    NoVolvio: string;
  begin
    NoVolvio := FotoUnit.Restaura;
    for var K := High(DisenosA) downto 0 do
      try
        if Params.Copy then
          BorraLoNuestro(DisenosA[K]) // la copia de un +R es +R
        else
          TFile.Move(DisenosA[K], DisenosDe[K]);
      except
        on E2: Exception do
          NoVolvio := NoVolvio + IfThen(NoVolvio <> '', #10) + '  ' +
            DisenosA[K] + ': ' + E2.Message.Trim;
      end;
    try
      if Params.Copy then
        BorraLoNuestro(Params.Dest)
      else
        TFile.Move(Params.Dest, Params.Path);
    except
      on E2: Exception do
        NoVolvio := NoVolvio + IfThen(NoVolvio <> '', #10) + '  ' +
          Params.Dest + ': ' + E2.Message.Trim;
    end;
    QuitaCopiaDeSeguridad(BackupNote, AncestroCopia);
    if (CopiaCabecera <> '') and not HabiaCopiaCabecera then
      QuitaCopiaDeSeguridad(CopiaCabecera, AncestroCabecera);
    if NoVolvio <> '' then
      Exit(MsgFmt(SR_FOTO_NO_VOLVIO_FMT, [NoVolvio, ACausa]));
    QuitaCarpetasCreadas(CarpetaDestino, AncestroDestino);
    Result := ARechazo;
  end;

begin
  if Params.Dest.Trim = '' then
    Exit(MsgText(SR_FILE_DELPHI_MOVE_NECESITA_DEST));
  // El ORIGEN: mover lo quita de su sitio, asi que pasa la puerta de
  // ESCRITURA; copiar solo lo LEE, asi que pasa la de LECTURA: tus raices,
  // tus ReadOnlyRoots, la zona de biblioteca. Traer algo de un proyecto de
  // referencia es justo para lo que existen (David, 25-sep-2026); el
  // original no se toca y un proyecto entero sigue sin poder duplicarse.
  if Params.Copy then
    Denied := ReadPathDenied(Params.Path)
  else
    Denied := PathDenied(Params.Path);
  if Denied <> '' then
    Exit(Denied);
  // El destino no cae en temporales, __history ni papelera (aprobado por
  // David, 25-sep-2026). Sacar algo de ahi (restaurar, guardar una captura)
  // es el ORIGEN, y ese sigue siendo libre dentro de la jaula.
  Denied := WriteTargetDenied(Params.Dest);
  if Denied <> '' then
    Exit(Denied);
  // Moving an item OUT of the trash is a RESTORE - allowed (what delphi_delete
  // tells the agent to do). What is refused: moving the trash FOLDER itself,
  // and moving anything INTO the trash by hand.
  if IsBackupRoot(Params.Path) then
    Exit(MsgFmt(SR_FILE_PAPELERA_NO_SE_MUEVE_FMT, [TrashFolderName]));
  if IsBackupPath(Params.Dest) then
    Exit(MsgFmt(SR_FILE_NO_MUEVAS_DENTRO_PAPELERA_FMT, [TrashFolderName]));
  if not (TFile.Exists(Params.Path) or TDirectory.Exists(Params.Path)) then
    Exit(MsgFmt(SR_FILE_NO_EXISTE_ORIGEN_FMT, [Params.Path]));
  if TFile.Exists(Params.Dest) or TDirectory.Exists(Params.Dest) then
    Exit(MsgFmt(SR_FILE_DESTINO_YA_EXISTE_FMT, [Params.Dest]));
  // un FICHERO que va a una ruta con separador final: esa ruta nombra una
  // CARPETA, y dest es el NUEVO nombre (GUARD-025). Se creaba la carpeta, se
  // dejaba una copia en la papelera y fallaba INTERNAL (octava revision)
  if TFile.Exists(Params.Path) and (CarpetaEnVezDeFichero(Params.Dest) <> '') then
    Exit(CarpetaEnVezDeFichero(Params.Dest));
  // UNA CARPETA se mueve renombrandola o nada (MueveArbol, Lsp.Guard). Se
  // pregunta ANTES de la copia de seguridad: un rechazo no deja copias de
  // algo que no se va a mover.
  if TDirectory.Exists(Params.Path) and not Params.Copy then
  begin
    Denied := MovidoDenegado(Params.Path, Params.Dest);
    if Denied <> '' then
      Exit(Denied);
  end;
  // copy=true: misma puerta, dos rechazos mas. Desde la papelera se RESTAURA
  // (move), no se copia; y una carpeta con proyecto dentro no se duplica: un
  // proyecto nunca vive en dos sitios (David, 24-sep-2026).
  if Params.Copy then
  begin
    if IsBackupPath(Params.Path) then
      Exit(MsgText(SR_MOVE_COPY_FROM_TRASH));
    // La decision de la copia, en Lsp.Guard: mira lo que CopiaArbol VA a
    // copiar (fichero suelto incluido, .dpr incluido, enlaces con su regla),
    // y un destino dentro del origen (se copiaria sin fin).
    Denied := CopiaDenegada(Params.Path, Params.Dest);
    if Denied <> '' then
      Exit(Denied);
  end;
  // Una copia de la papelera se llama "UFicha.pas-215825250": su extension
  // REAL esta detras del sello de hora. Sin esto, restaurar un formulario
  // dejaba el .dfm dentro de la papelera y la unit fuera, sin designer.
  var DesdePapelera := IsBackupPath(Params.Path);
  var NombreReal := TPath.GetFileName(SinBarraFinal(Params.Path));
  if DesdePapelera then
  begin
    var Orig := TrashOriginalName(NombreReal);
    if Orig <> '' then
      NombreReal := Orig;
  end;
  IsUnit := TFile.Exists(Params.Path) and
    (TPath.GetExtension(NombreReal).ToLower = '.pas');
  Projects := [];
  OldStem := TPath.GetFileNameWithoutExtension(NombreReal);
  NewStem := TPath.GetFileNameWithoutExtension(Params.Dest);
  if IsUnit then
  begin
    if TPath.GetExtension(Params.Dest).ToLower <> '.pas' then
      Exit(MsgFmt(SR_MOVE_UNIT_SOLO_SE_MUEVE_FMT, [TPath.GetFileName(Params.Dest)]));
    if not EsIdentificador(NewStem, True) then // EL identificador (Lsp.Pascal)
      Exit(MsgFmt(SR_FILE_IDENTIFICADOR_UNIT_FMT, [NewStem]));
    // un nombre NUEVO, la regla entera (Lsp.Scaffold): renombrar a Begin o a
    // System pasaba; mover una unit que ya se llama asi, no se toca
    if not MismoIdentificador(OldStem, NewStem) and (BadUnitName(NewStem) <> '') then
      Exit(BadUnitName(NewStem));
    for Ext in DESIGNER_EXTS do
      if TFile.Exists(ChangeFileExt(Params.Dest, Ext)) then
        Exit(MsgFmt(SR_FILE_YA_EXISTE_NO_SOBREESCRIBO_FMT, [ChangeFileExt(Params.Dest, Ext)]));
    // renombrarla es reescribir su cabecera (unit X;): con el atributo +R no
    // se puede, y se movia igual - MOVED con "unit UOld;" en UNew.pas y el
    // proyecto roto. Se dice ANTES de mover (novena revision)
    if not Params.Copy and not MismoIdentificador(OldStem, NewStem) and (SoloLecturaDenegado(Params.Path) <> '') then
      Exit(SoloLecturaDenegado(Params.Path));
    if not Params.Copy then
      Projects := ProjectsUsingUnit(Params.Path, TPath.GetDirectoryName(Params.Dest));
  end;
  // la carpeta que YA existia por encima de la copia de seguridad: lo que se
  // cree debajo se quita si el move falla (octava revision)
  AncestroCopia := '';
  CopiaCabecera := '';
  HabiaCopiaCabecera := False;
  // ...y la que ya existia por encima del destino: un move que falla quita
  // las que creo para el (se quedaban vacias; novena revision)
  CarpetaDestino := TPath.GetDirectoryName(TPath.GetFullPath(Params.Dest));
  AncestroDestino := PrimerAncestroQueExiste(CarpetaDestino);
  try
    // La carpeta de destino PRIMERO: si no se puede (GUARD-019, un fichero en
    // el camino) no se ha movido nada y tampoco debe quedar una copia del
    // origen en la papelera (quinta revision).
    CrearCarpeta(CarpetaDestino);
    // Safety copy of the source into the trash before relocating... salvo que
    // el origen YA sea una copia de la papelera. Hacer una copia de una copia
    // dejaba una papelera DENTRO de la papelera, con el sello doblado, y cada
    // restauracion anadia otra capa (medido 2026-09-20). Lo que se restaura no
    // necesita red: la red es el.
    if Params.Copy then
      BackupNote := ''
    else if DesdePapelera then
      BackupNote := '' // su nota es otra (SN_FILE_SIN_COPIA_DESDE_PAPELERA)
    else if EsEnlace(SinBarraFinal(Params.Path)) then
      // un ENLACE se mueve como enlace y lo de detras no se toca: nada que
      // guardar, y copiarlo era copiar su destino (una junction a un
      // antepasado copiaba la jaula en su papelera y fallaba; octava revision)
      BackupNote := ''
    else
    begin
      BackupNote := TrashPathFor(Params.Path, CAJON_BORRADOS);
      AncestroCopia := PrimerAncestroQueExiste(TPath.GetDirectoryName(BackupNote));
      CrearCarpeta(TPath.GetDirectoryName(BackupNote));
      if TDirectory.Exists(Params.Path) then
        // EL copiador, SIN seguir enlaces: el move los lleva como enlaces, y
        // copiar lo de detras metia una junction a la raiz en su propia
        // papelera (MOVE-012). En su lista: no es lo que el agente copia
        // (su FILE-032 se leia como del move; novena revision)
        CopiaArbol(Params.Path, BackupNote, True, NoSegCopia, False)
      else
        TFile.Copy(Params.Path, BackupNote);
    end;
    if Params.Copy then
    begin
      if TDirectory.Exists(Params.Path) then
      begin
        // EL copiador (Lsp.Guard): sin la papelera del origen (no es
        // contenido: ni se copia ni hay que borrarla despues) y sin seguir un
        // enlace a lo que este workspace no puede leer (25-sep-2026). A una
        // carpeta de descarga (__tmp-) y luego su nombre: una copia que falla
        // a mitad se quita ENTERA (el borrador la acepta: la acaba de crear
        // el servidor) y no se queda a medias en el destino, donde el
        // "repite" del mensaje daba FILE-025 (novena revision)
        var Bajada := NuevaCarpetaDescarga(CarpetaDestino);
        try
          CopiaArbol(Params.Path, Bajada, False, NoSeguidos);
          MueveArbol(Bajada, Params.Dest); // renombrar o nada
        except
          on E: Exception do
          begin
            var Queda := '';
            try
              BorraArbol(Bajada);
            except
              Queda := Bajada;
            end;
            if TDirectory.Exists(Bajada) then
              Queda := Bajada;
            // lo que se queda, se dice (decima revision)
            if Queda <> '' then
              raise Exception.Create(E.Message.TrimRight + #10 +
                MsgFmt(SF_MOVE_BAJADA_QUEDA_FMT, [Queda]));
            raise;
          end;
        end;
      end
      else
        CopiaNuestra(Params.Path, Params.Dest); // la copia es del agente: sin el +R del original
    end
    else if TDirectory.Exists(Params.Path) then
      MueveArbol(Params.Path, Params.Dest) // renombrar o nada
    else
      TFile.Move(Params.Path, Params.Dest);
    // Restoring a copy OUT of the trash leaves its owner marker behind with
    // nothing to mark: sweep it, so the agent that restores can leave the
    // trash clean instead of a litter of .by files only the operator can lift.
    // (la de una UNIT, despues de su form: si el form falla vuelve a la
    // papelera, y sin su marca la purgaba otro agente; novena revision)
    if IsBackupPath(Params.Path) and not IsUnit then
      QuitaMarcaDeDueno(Params.Path);
  except
    on E: Exception do
    begin
      // un move que no se hizo no deja su copia de seguridad ni su cajon:
      // cada reintento dejaba otra (octava revision). Ni la copia a medias
      // de un copy=true (el destino no existia: es suya) ni las carpetas
      // de destino que creo (novena revision)
      QuitaCopiaDeSeguridad(BackupNote, AncestroCopia);
      // (la de una carpeta la quita su propia bajada. La de un FICHERO no se
      // borra: CopyFile ya quita lo suyo, y copy=true va sin cerrojo - si
      // falla porque el destino YA existe, es de otro; se borraba, decima)
      QuitaCarpetasCreadas(CarpetaDestino, AncestroDestino);
      Exit(IfThen(Params.Copy, MsgEnvuelve(SR_MOVE_ERROR_AL_COPIAR_FMT, E.Message), MsgEnvuelve(SR_MOVE_ERROR_AL_MOVER_FMT, E.Message)));
    end;
  end;
  Result := IfThen(Params.Copy, MsgFmt(SK_MOVE_COPIADO_FMT, [Params.Path, Params.Dest]),
    MsgFmt(SK_MOVE_MOVIDO_FMT, [Params.Path, Params.Dest]));
  if Length(NoSeguidos) > 0 then
    Result := Result + #10 + MsgFmt(SN_COPY_LINKS_NOT_FOLLOWED_FMT,
      [Length(NoSeguidos), string.Join(', ', NoSeguidos)]);
  // una copia no necesita red: el origen sigue ahi. Y lo que sale de la
  // papelera tampoco: salia "(backup in (the source was already...))"
  if not Params.Copy then
    if DesdePapelera then
      Result := Result + #10 + MsgText(SN_FILE_SIN_COPIA_DESDE_PAPELERA)
    else if BackupNote <> '' then // un enlace no lleva copia (lo de detras no se toca)
      Result := Result + #10 + MsgFmt(SN_FILE_COPIA_SEGURIDAD_EN_FMT, [BackupNote]);
  if not IsUnit then
    Exit(Result + Reubicacion(DesdePapelera));

  // TODO O NADA desde aqui, como borrarla (FILE-039): la foto de lo que el
  // move va a REESCRIBIR - la unit en su sitio nuevo (su cabecera) y cada
  // proyecto que la lista (.dpr, .dproj y, en un rename, las units que
  // reescribe: la lista de FicherosDelRename, la misma del propio rename).
  // Los designers no: van y vuelven por su nombre (DeshaceMove). Un
  // proyecto que no se dejaba re-apuntar salia MOVED con el proyecto roto
  // (medido en vivo, 28-sep-2026)
  var RutasFoto := TStringList.Create;
  try
    RutasFoto.Sorted := True;
    RutasFoto.Duplicates := dupIgnore;
    RutasFoto.Add(Params.Dest);
    for P in Projects do
      if PathDenied(P) = '' then
      begin
        RutasFoto.Add(P);
        RutasFoto.Add(DprojDe(P));
        if not MismoIdentificador(OldStem, NewStem) then
        begin
          var NoEscritos: TArray<string>;
          RutasFoto.AddStrings(FicherosDelRename(P, Params.Dest, NoEscritos));
        end;
      end;
    try
      FotoUnit.Toma(RutasFoto.ToStringArray);
    except
      // un proyecto que no se deja LEER (otro proceso lo tiene) no se va a
      // poder re-apuntar: la unit vuelve, y se dice cual (por su nombre,
      // como los otros dos emisores de MOVE-019; r11b H7)
      on E: Exception do
      begin
        var Nombres := '';
        for var Q in Projects do
          Nombres := Nombres + IfThen(Nombres <> '', ', ') + TPath.GetFileName(Q);
        Exit(DeshaceMove(MsgFmt(SR_MOVE_PROYECTO_NO_VA_FMT, [Nombres,
          E.Message.Trim, Params.Path]), MsgFmt(SF_MOVE_PROYECTO_NO_VA_FMT,
          [Nombres, E.Message.Trim])));
      end;
    end;
  finally
    RutasFoto.Free;
  end;

  // the designer pair travels with the unit
  PairNote := '';
  // los designers ya movidos (de, a): si falla el siguiente vuelven (con
  // .dfm y .fmx, el .dfm se quedaba en el destino; novena revision)
  for Ext in DESIGNER_EXTS do
  begin
    var Gemelo := DesignerJunto(Params.Path, OldStem, Ext, DesdePapelera);
    if Gemelo = '' then
      Continue;
    try
      if Params.Copy then
        CopiaNuestra(Gemelo, ChangeFileExt(Params.Dest, Ext))
      else
        TFile.Move(Gemelo, ChangeFileExt(Params.Dest, Ext));
      DisenosDe := DisenosDe + [Gemelo];
      DisenosA := DisenosA + [ChangeFileExt(Params.Dest, Ext)];
      // una nota por designer: con .dfm Y .fmx solo se nombraba el ultimo (decima)
      PairNote := PairNote + IfThen(PairNote <> '', #10) + MsgFmt(SN_FILE_DESIGNER_TOO_FMT,
        [TPath.GetFileName(ChangeFileExt(Params.Dest, Ext)),
         IfThen(Params.Copy, MsgText(SF_MOVE_COPIADO_CON_UNIT), MsgText(SF_MOVE_MOVIDO_CON_UNIT))]);
    except
      on E: Exception do
        // TODO O NADA: una unit sin su form es un proyecto roto que decia
        // MOVED. Los designers ya movidos y la unit vuelven (o sus copias
        // se quitan) y ningun proyecto se toca: todavia no se ha
        // re-apuntado ninguno (octava revision). Lo que NO vuelve se dice
        // (SYS-018): decia "the unit is back" aunque no volviera (novena)
        Exit(DeshaceMove(MsgFmt(SR_MOVE_FORM_NO_VA_FMT, [TPath.GetFileName(Gemelo),
          E.Message.Trim, Params.Path]), MsgFmt(SF_MOVE_FORM_NO_VA_FMT,
          [TPath.GetFileName(Gemelo), E.Message.Trim])));
    end;
  end;
  if PairNote <> '' then
    Result := Result + #10 + PairNote;

  // a rename: the header must follow the file name. La encuentra SU lector
  // (con directivas detras: "unit X platform;"); si no esta o dice otro
  // nombre, no se toca y se DICE - MOVE-015 decia "rewritten" sin mirar si la
  // regex habia cambiado algo, y el build caia en E1038 (decima revision)
  if not MismoIdentificador(OldStem, NewStem) then
  try
    Src := PatchLoadText(Params.Dest, Enc);
    var Cab: string;
    var Ini: Integer;
    if CabeceraDeUnit(Src, Cab, Ini) and MismoIdentificador(Cab, OldStem) then
    begin
      Src := Copy(Src, 1, Ini - 1) + NewStem + Copy(Src, Ini + Length(Cab), MaxInt);
      CopiaCabecera := CopiaDiariaDe(Params.Dest);
      HabiaCopiaCabecera := TFile.Exists(CopiaCabecera);
      AncestroCabecera := PrimerAncestroQueExiste(TPath.GetDirectoryName(CopiaCabecera));
      PatchSaveText(Params.Dest, Src, Enc);
      FotoUnit.Anota(Params.Dest); // lo que dejo el move: el deshacer lo devuelve
      Result := Result + #10 + MsgFmt(SN_MOVE_CABECERA_REESCRITA_FMT, [NewStem]);
    end
    else
      Result := Result + #10 + MsgFmt(SN_MOVE_CABECERA_NO_ENCONTRADA_FMT, [OldStem, NewStem]);
  except
    on E: Exception do
      Result := Result + #10 + MsgFmt(SN_MOVE_ERROR_REESCRIBIR_CABECERA_FMT, [OldStem, E.Message]);
  end;

  ProjNote := '';
  for P in Projects do
  begin
    if PathDenied(P) <> '' then
    begin
      ProjNote := ProjNote + #10 + MsgFmt(SN_FILE_PROJECT_DENIED_FMT, [TPath.GetFileName(P)]);
      Continue;
    end;
    // TODO O NADA, como su form (MOVE-017): un proyecto que no se deja
    // re-apuntar (su .dpr o su .dproj en +R, abierto sin compartir) salia
    // MOVED con la unit en su sitio nuevo y el proyecto apuntando al viejo,
    // "ERROR" en una nota que decia "nothing was written" con el .dpr ya
    // reescrito (medido en vivo, 28-sep-2026)
    try
      FotoUnit.Vigila(P);
      R := RenameProjectUnit(P, Params.Path, Params.Dest);
    except
      on E: Exception do
        Exit(DeshaceMove(MsgFmt(SR_MOVE_PROYECTO_NO_VA_FMT, [TPath.GetFileName(P),
          E.Message.Trim, Params.Path]), MsgFmt(SF_MOVE_PROYECTO_NO_VA_FMT,
          [TPath.GetFileName(P), E.Message.Trim])));
    end;
    if EsFallo(R) then
      Exit(DeshaceMove(MsgFmt(SR_MOVE_PROYECTO_NO_VA_FMT, [TPath.GetFileName(P), R,
        Params.Path]), MsgFmt(SF_MOVE_PROYECTO_NO_VA_FMT, [TPath.GetFileName(P), R])));
    FotoUnit.Anota(P);
    FotoUnit.Anota(DprojDe(P));
    // ...y todo lo que ese rename pudo reescribir (las units del proyecto y
    // la propia en su sitio nuevo): sin anotar, el deshacer las tomaba por
    // cambiadas "por otro" y dejaba la unit vieja con la cabecera nueva
    // (undecima revision, r11a: dos proyectos y una unit que se nombra)
    if not MismoIdentificador(OldStem, NewStem) then
    begin
      var NoEsc: TArray<string>;
      for var Fr in FicherosDelRename(P, Params.Dest, NoEsc) do
        FotoUnit.Anota(Fr);
    end;
    ProjNote := ProjNote + #10 + '    ' + TPath.GetFileName(P) + ': ' + R.Replace(#10, ' ');
  end;
  // lo restaurado ya no vuelve a la papelera: fuera sus marcas (la de la
  // unit y las de sus designers). AL FINAL: quitadas antes del bucle de
  // proyectos, un MOVE-019 devolvia la copia a la papelera sin dueno y otro
  // agente podia purgarla (r11a H4)
  if DesdePapelera then
  begin
    QuitaMarcaDeDueno(Params.Path);
    for var K := 0 to High(DisenosDe) do
      QuitaMarcaDeDueno(DisenosDe[K]);
  end;
  if Length(Projects) > 0 then
    ProjNote := MsgFmt(SN_FILE_PROJECTS_UPDATED_FMT, [Length(Projects),
      string.Join(', ', Projects)]) + ProjNote
  else if Params.Copy then
    ProjNote := MsgText(SN_FILE_COPY_NO_PROJECT)
  else
    ProjNote := MsgText(SN_FILE_PROJECTS_NONE);
  Result := Result + #10 + ProjNote + Reubicacion(DesdePapelera);
end;

initialization
  TMCPRegistry.RegisterTool('delphi_delete',
    function: IMCPTool begin Result := TDelphiDeleteTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_move',
    function: IMCPTool begin Result := TDelphiMoveTool.Create; end);

end.
