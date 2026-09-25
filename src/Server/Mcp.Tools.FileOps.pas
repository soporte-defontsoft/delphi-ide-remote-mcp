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
    [SchemaDescription('Absolute path of the file or folder to delete (inside the workspace roots). Moved to a recoverable trash, not hard-deleted')]
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
    [SchemaDescription('Absolute path of the file or folder to move (inside the workspace roots)')]
    [Required]
    [RutaDelServidor]
    property Path: string read FPath write FPath;
    [SchemaDescription('Destination absolute path (inside the workspace roots). Parent folders are created. Renames when the parent is the same')]
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
  Lsp.ProjectUnits;

var
  // El nombre de la carpeta de copias estaba escrito DOS veces, aqui y en
  // Lsp.Patch. Una constante repetida es una convencion esperando a
  // separarse: ahora la dice su duenno.
  BACKUP_SUB: string;

{ Where a deleted/overwritten item is parked, next to it: recoverable.
  La ruta entera la compone EL NOMBRADOR (Lsp.Patch): aqui solo se elige el
  cajon. Componerla a mano es como nacieron tres convenciones distintas para
  la misma papelera. }
function TrashPathFor(const APath: string): string;
begin
  Result := TPath.Combine(TrashDayDir(APath, 'deleted'),
    TrashStampedName(TPath.GetFileName(ExcludeTrailingPathDelimiter(APath))));
end;

function IsBackupPath(const APath: string): Boolean;
var
  N: string;
begin
  N := ExcludeTrailingPathDelimiter(APath.ToLower.Replace('/', '\'));
  // inside the trash, OR the trash folder itself (no trailing separator).
  Result := N.Contains('\' + BACKUP_SUB + '\') or N.EndsWith('\' + BACKUP_SUB);
end;

{ The trash/backup folder ITSELF (…\__delphi-patch), not something inside it.
  Moving/deleting the trash itself is refused; moving an item OUT of it (a
  restore) is allowed. }
function IsBackupRoot(const APath: string): Boolean;
begin
  Result := ExcludeTrailingPathDelimiter(APath.ToLower.Replace('/', '\'))
    .EndsWith('\' + BACKUP_SUB);
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

procedure WriteOwnerMarker(const ATrash: string); forward;

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
      if F.ToLower.EndsWith('.by') then
        Continue;
      if (Mejor = '') or (TFile.GetLastWriteTime(F) > TFile.GetLastWriteTime(Mejor)) then
        Mejor := F;
    end;
  except
    Exit('');
  end;
  Result := Mejor;
end;

procedure MoveToTrash(const APath: string; out ATrash: string);
begin
  ATrash := TrashPathFor(APath);
  CrearCarpeta(TPath.GetDirectoryName(ATrash));
  if TDirectory.Exists(APath) then
    // EL mudador (Lsp.Guard): renombrar o nada, con su guard. Nacio AQUI el
    // 2026-08-25 (TDirectory.Move, al no poder renombrar, copiaba y borraba
    // por su cuenta y vacio en la papelera una carpeta bloqueada) y se quedo
    // aqui solo: delphi_move siguio un mes con TDirectory.Move y se trajo a
    // la jaula y BORRO lo de detras de un junction (2026-09-25).
    MueveArbol(APath, ATrash)
  else
    TFile.Move(APath, ATrash);
  // Who trashed it, so a later purge can be told "yours only". A file with no
  // marker (or an unknown agent) is nobody's in particular and any caller may
  // purge it - which keeps the operator's own cleanup, and stdio, working.
  WriteOwnerMarker(ATrash);
end;

{ Drop "<trashpath>.by" holding the agent that trashed it, best-effort. }
procedure WriteOwnerMarker(const ATrash: string);
var
  Who: string;
begin
  Who := CurrentAgent;
  if Who = '' then
    Exit;
  try
    TFile.WriteAllText(ATrash + '.by', Who, TEncoding.ASCII);
  except
    // a missing marker just means "nobody's": never fatal
  end;
end;

{ The agent that owns a trashed item, '' when nobody is recorded. }
function TrashOwner(const APath: string): string;
begin
  Result := '';
  try
    if TFile.Exists(APath + '.by') then
      Result := TFile.ReadAllText(APath + '.by').Trim([' ', #9, #13, #10, #$FEFF]);
  except
    Result := '';
  end;
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
      Result := Format(SR_FILE_PURGE_NOT_YOURS_FMT, [Owner]);
    Exit;
  end;
  if not TDirectory.Exists(APath) then
    Exit;
  Others := TStringList.Create;
  try
    Others.Duplicates := dupIgnore;
    Others.Sorted := True;
    for F in TDirectory.GetFiles(APath, '*.by', TSearchOption.soAllDirectories) do
    begin
      // A marker only OWNS the copy sitting next to it. An orphan .by (its copy
      // already restored or purged) or a file someone just renamed to .by marks
      // nothing - counting its content as an owner let a planted .by make a
      // whole folder unpurgeable by anyone (measured 2026-08-25).
      Sib := Copy(F, 1, Length(F) - 3);
      if not (TFile.Exists(Sib) or TDirectory.Exists(Sib)) then
        Continue;
      Owner := TrashOwner(Sib);
      if (Owner <> '') and not SameText(Owner, Me) then
        Others.Add(Owner);
    end;
    if Others.Count > 0 then
      Result := Format(SR_FILE_PURGE_FOLDER_NOT_YOURS_FMT,
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

{ TDelphiDeleteTool }

constructor TDelphiDeleteTool.Create;
begin
  inherited;
  FName := 'delphi_delete';
  FDescription := 'Delete a file or folder inside the workspace. NOT a hard ' +
    'delete: the target is moved to a recoverable trash ' +
    '(__delphi-patch\<date>\deleted\ next to it), so a mistake can be undone. ' +
    'Jailed to the workspace roots, refused in read-only mode. A folder ' +
    'that is or holds a workspace root, a reference project or a read-only ' +
    'folder is refused (it would go along). Use it to ' +
    'clean up stray files and leftovers. Deleting a unit (.pas) also trashes ' +
    'its .dfm/.fmx and takes it out of every project that lists it - looked ' +
    'for from its folder UP to the edge of the workspace, however deep the ' +
    'unit sits (uses, CreateForm, DCCReference). To keep ' +
    'the file but drop it from a project use delphi_config command=remove-unit.';
end;

function TDelphiDeleteTool.ExecuteWithParams(const Params: TDelphiDeleteParams): string;
var
  Denied, Trash, ProjNote, DesignerNote, P, R, Ext: string;
  Projects: TArray<string>;
begin
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
      Exit(SR_FILE_PURGE_ONLY_TRASH);
    if IsBackupRoot(Params.Path) then
      Exit(SR_FILE_PURGE_NOT_ROOT);
    if not (TFile.Exists(Params.Path) or TDirectory.Exists(Params.Path)) then
      Exit('RECHAZADO: no existe ' + Params.Path);
    var CanonPurge := LongCanonical(Params.Path);
    if CanonPurge.ToLower.EndsWith('.by') then
    begin
      // A live marker for someone else's copy is off limits - removing it would
      // orphan their copy for the taking. But an orphan marker (copy already
      // restored/purged) or your own is yours to sweep: otherwise the trash
      // could never be left clean by the agent that made it.
      var SibMk := Copy(CanonPurge, 1, Length(CanonPurge) - 3);
      var Mk := TrashOwner(SibMk); // owner is THIS marker's content
      if (TFile.Exists(SibMk) or TDirectory.Exists(SibMk)) and
         (CurrentAgent <> '') and (Mk <> '') and not SameText(Mk, CurrentAgent) then
        Exit(Format(SR_FILE_PURGE_NOT_YOURS_FMT, [Mk]));
    end
    else
    begin
      // Yours only - and on a folder, that means everything inside it too.
      Denied := PurgeOwnershipDenied(Params.Path);
      if Denied <> '' then
        Exit(Denied);
    end;
    try
      if TDirectory.Exists(Params.Path) then
      begin
        // BorraArbol limpia atributos por entrada y NO cruza enlaces: el
        // junction cae como entrada y su destino ni se mira. El borrado
        // recursivo de la RTL entraba y borraba AL OTRO LADO (2026-09-21).
        BorraArbol(Params.Path);
      end
      else
      begin
        if (TFile.GetAttributes(Params.Path) * [TFileAttribute.faReadOnly]) <> [] then
          TFile.SetAttributes(Params.Path,
            TFile.GetAttributes(Params.Path) - [TFileAttribute.faReadOnly]);
        TFile.Delete(Params.Path);
      end;
    except
      on E: Exception do
        Exit(Format(SR_FILE_PURGE_FAILED_FMT,
          [TPath.GetFileName(ExcludeTrailingPathDelimiter(Params.Path)), E.Message]));
    end;
    if StillThere(Params.Path) then
      Exit(Format(SR_FILE_PURGE_FAILED_FMT,
        [TPath.GetFileName(ExcludeTrailingPathDelimiter(Params.Path)),
         'sigue ahi despues de borrarlo']));
    try
      if TFile.Exists(Params.Path + '.by') then
        TFile.Delete(Params.Path + '.by');
    except
    end;
    Exit(Format(SN_FILE_PURGED_FMT,
      [TPath.GetFileName(ExcludeTrailingPathDelimiter(Params.Path))]));
  end;
  if IsBackupPath(Params.Path) then
    Exit('RECHAZADO: ' + BACKUP_SUB + '\ es la papelera/copias de esta tool. ' +
      'No se borra desde aqui (purgala manualmente si de verdad quieres).');
  if not (TFile.Exists(Params.Path) or TDirectory.Exists(Params.Path)) then
    Exit('RECHAZADO: no existe ' + Params.Path);
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
    ClearReadOnlyTree(Params.Path);
    try
      TDirectory.Delete(Params.Path, False);
    except
      // fall through to the honest report below
    end;
    if not TDirectory.Exists(Params.Path) then
      Exit(Format(SN_FILE_DELETE_EMPTY_OK_FMT,
        [TPath.GetFileName(ExcludeTrailingPathDelimiter(Params.Path))]));
    Exit(Format(SR_FILE_DELETE_STUCK_FMT,
      [TPath.GetFileName(ExcludeTrailingPathDelimiter(Params.Path))]));
  end;
  ProjNote := '';
  DesignerNote := '';
  if TFile.Exists(Params.Path) and (TPath.GetExtension(Params.Path).ToLower = '.pas') then
  begin
    // a unit: take it out of the projects that list it (while the .pas is
    // still readable, so the form class/variable are known), then trash the
    // designer pair with it.
    Projects := ProjectsUsingUnit(Params.Path);
    for P in Projects do
    begin
      if PathDenied(P) <> '' then
      begin
        ProjNote := ProjNote + #10 + Format(SN_FILE_PROJECT_DENIED_FMT, [TPath.GetFileName(P)]);
        Continue;
      end;
      try
        R := RemoveProjectUnit(P, Params.Path, True);
      except
        on E: Exception do
          R := 'ERROR ' + E.Message;
      end;
      ProjNote := ProjNote + #10 + '    ' + TPath.GetFileName(P) + ': ' + R.Replace(#10, ' ');
    end;
    if Length(Projects) > 0 then
      ProjNote := Format(SN_FILE_PROJECTS_UPDATED_FMT, [Length(Projects),
        string.Join(', ', Projects)]) + ProjNote
    else
      ProjNote := SN_FILE_PROJECTS_NONE;
    for Ext in ['.dfm', '.fmx'] do
      if TFile.Exists(ChangeFileExt(Params.Path, Ext)) then
      try
        MoveToTrash(ChangeFileExt(Params.Path, Ext), Trash);
        DesignerNote := Format(SN_FILE_DESIGNER_TOO_FMT,
          [TPath.GetFileName(ChangeFileExt(Params.Path, Ext)), 'tambien a la papelera']);
      except
        on E: Exception do
          DesignerNote := Format(SN_FILE_DESIGNER_TOO_FMT,
            [TPath.GetFileName(ChangeFileExt(Params.Path, Ext)), 'ERROR ' + E.Message]);
      end;
  end
  else if TDirectory.Exists(Params.Path) then
  try
    // UNA CARPETA ENTERA: cada unit de dentro sale de los proyectos que la
    // listan, igual que una unit suelta. Se borraba la carpeta, se contestaba
    // "BORRADO" y el .dpr seguia listando units que ya no estaban: build roto
    // con F1026 y una respuesta de exito (medido en vivo el 2026-09-21, el
    // gemelo de lo que le pasaba a delphi_move). Un proyecto que vive DENTRO
    // de la carpeta se va con ella: no se toca.
    var Raiz := IncludeTrailingPathDelimiter(TPath.GetFullPath(Params.Path));
    var Cuantas := 0;
    for var U in TDirectory.GetFiles(Params.Path, '*.pas',
      TSearchOption.soAllDirectories) do
    begin
      if IsBackupPath(U) then
        Continue;
      for P in ProjectsUsingUnit(U) do
      begin
        if StartsText(Raiz, IncludeTrailingPathDelimiter(
             TPath.GetDirectoryName(TPath.GetFullPath(P)))) then
          Continue;
        if PathDenied(P) <> '' then
          R := Format(SN_FILE_PROJECT_DENIED_FMT, [TPath.GetFileName(P)])
        else
          try
            R := RemoveProjectUnit(P, U, True);
          except
            on E: Exception do
              R := 'ERROR ' + E.Message;
          end;
        Inc(Cuantas);
        ProjNote := ProjNote + #10 + '    ' + TPath.GetFileName(P) + ': ' + R.Replace(#10, ' ');
      end;
    end;
    if Cuantas > 0 then
      ProjNote := Format('  units de la carpeta quitadas de sus proyectos (%d):',
        [Cuantas]) + ProjNote;
  except
    // una subcarpeta ilegible no impide borrar: se quita lo que se vio
  end;
  try
    MoveToTrash(Params.Path, Trash);
  except
    on E: Exception do
    begin
      // A locked FOLDER move fails as a whole and leaves the tree intact: say so
      // plainly, because "error" used to read as "and who knows what it did".
      if TDirectory.Exists(Params.Path) then
        Exit(Format(SR_FILE_DELETE_LOCKED_FMT,
          [TPath.GetFileName(ExcludeTrailingPathDelimiter(Params.Path)),
           E.Message]));
      if (ProjNote <> '') or (DesignerNote <> '') then
        Exit(Format(SN_FILE_PARTIAL_FMT, ['al mover a la papelera', E.Message,
          #10 + DesignerNote + #10 + ProjNote]));
      Exit('ERROR al mover a la papelera: ' + E.Message);
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
      Result := Format(SR_FILE_DELETE_EMPTY_SHELL_FMT,
        [TPath.GetFileName(ExcludeTrailingPathDelimiter(Params.Path)), Trash])
    else
      Result := Format(SR_FILE_DELETE_PARTIAL_FMT,
        [TPath.GetFileName(ExcludeTrailingPathDelimiter(Params.Path)), Trash]);
    if DesignerNote <> '' then
      Result := Result + #10 + DesignerNote;
    if ProjNote <> '' then
      Result := Result + #10 + ProjNote;
    Exit;
  end;
  Result := Format('BORRADO %s (movido a la papelera recuperable).'#10 +
    '  copia: %s'#10'  Para recuperarlo: delphi_move con path=esa copia y ' +
    'dest=donde lo quieras (restaurar desde la papelera esta permitido).',
    [TPath.GetFileName(ExcludeTrailingPathDelimiter(Params.Path)), Trash]);
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
  FDescription := 'Move or rename a file or folder inside the workspace, or COPY ' +
    'it with copy=true. The destination must be inside the workspace ' +
    'roots, and so must the source of a move; the source of a COPY only ' +
    'has to be readable (your roots, your ReadOnlyRoots, the library ' +
    'zone): a copy is how something is brought in from a reference ' +
    'project, its original untouched. Parent ' +
    'folders of the destination are created. The source is copied to the ' +
    'recoverable trash first. Jailed, refused in read-only mode. A FOLDER ' +
    'moves only as a rename on the same drive, whole or not at all (links ' +
    'inside travel as links); to another drive, copy=true and then ' +
    'delphi_delete. A folder that is or holds a root, a reference or a ' +
    'read-only folder is refused. Moving or ' +
    'renaming a unit (.pas) moves its .dfm/.fmx with it, rewrites its "unit X;" ' +
    'header on a rename, and re-points every project that lists it: the .dpr ' +
    'uses and DCCReference, the uses of every other unit of the project and ' +
    'every qualified UnitOld.X reference in them - looked for from its folder UP to the edge of the ' +
    'workspace, however deep the unit sits. Moving a whole FOLDER re-points ' +
    'every unit inside it the same way: reorganise freely, the projects follow. ' +
    'copy=true is the same door with a different last step: the source stays, ' +
    'no trash copy is taken, a copied unit named differently gets its "unit X;" ' +
    'header rewritten and its .dfm/.fmx copied along, and NO project is ' +
    're-pointed (the copy is a new unit nobody lists yet: delphi_config ' +
    'add-unit). Refused for a folder holding a .dproj/.dpk - a project never ' +
    'lives in two places; start one from another with delphi_create.';
end;

function TDelphiMoveTool.ExecuteWithParams(const Params: TDelphiMoveParams): string;
var
  Denied, BackupNote, Ext, Enc, Src, OldStem, NewStem, ProjNote, P, R, PairNote: string;
  Projects, NoSeguidos: TArray<string>;
  IsUnit: Boolean;
begin
  if Params.Dest.Trim = '' then
    Exit('RECHAZADO: delphi_move necesita "dest" (ruta destino).');
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
    Exit('RECHAZADO: ' + BACKUP_SUB + '\ es la carpeta de papelera; no se mueve entera.');
  if IsBackupPath(Params.Dest) then
    Exit('RECHAZADO: no muevas ficheros DENTRO de la papelera (' + BACKUP_SUB +
      '\); es para las copias que hace la tool. Muevelos a una carpeta normal.');
  if not (TFile.Exists(Params.Path) or TDirectory.Exists(Params.Path)) then
    Exit('RECHAZADO: no existe el origen ' + Params.Path);
  if TFile.Exists(Params.Dest) or TDirectory.Exists(Params.Dest) then
    Exit('RECHAZADO: el destino ya existe: ' + Params.Dest + ' (no sobreescribo).');
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
      Exit(SR_MOVE_COPY_FROM_TRASH);
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
  var NombreReal := TPath.GetFileName(ExcludeTrailingPathDelimiter(Params.Path));
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
      Exit('RECHAZADO: una unit .pas solo se mueve a otro nombre .pas (' +
        TPath.GetFileName(Params.Dest) + ').');
    if not TRegEx.IsMatch(NewStem, '^[A-Za-z_]\w*(\.[A-Za-z_]\w*)*$') then
      Exit('RECHAZADO: ''' + NewStem + ''' no es un identificador valido de unit ' +
        '(el nombre del fichero es el nombre de la unit).');
    for Ext in ['.dfm', '.fmx'] do
      if TFile.Exists(ChangeFileExt(Params.Dest, Ext)) then
        Exit('RECHAZADO: ya existe ' + ChangeFileExt(Params.Dest, Ext) + ' (no sobreescribo).');
    if not Params.Copy then
      Projects := ProjectsUsingUnit(Params.Path, TPath.GetDirectoryName(Params.Dest));
  end;
  // UNA CARPETA ENTERA: se apunta ANTES de moverla que unit de dentro lista
  // que proyecto, porque despues las rutas viejas ya no existen. Una carpeta
  // se movia y la funcion se iba sin mirar ningun proyecto: contestaba
  // "MOVIDO", el .dpr seguia diciendo in 'Dominio\Modelos\UCliente.pas' y el
  // build moria con F1026 - reorganizar carpetas, que es justo decidir la
  // estructura, dejaba el proyecto sin compilar con una respuesta de exito
  // (medido en vivo el 2026-09-21). Un proyecto que vive DENTRO de la carpeta
  // viaja con ella y sus rutas relativas siguen valiendo: no se toca.
  var Mudanza := TStringList.Create; // proyecto|unit vieja
  try
  if TDirectory.Exists(Params.Path) and not DesdePapelera and not Params.Copy then
  try
    var Raiz := IncludeTrailingPathDelimiter(TPath.GetFullPath(Params.Path));
    for var U in TDirectory.GetFiles(Params.Path, '*.pas',
      TSearchOption.soAllDirectories) do
    begin
      if IsBackupPath(U) then
        Continue;
      for var Pr in ProjectsUsingUnit(U, Params.Dest) do
        if not StartsText(Raiz, IncludeTrailingPathDelimiter(
             TPath.GetDirectoryName(TPath.GetFullPath(Pr)))) then
          Mudanza.Add(Pr + '|' + TPath.GetFullPath(U));
    end;
  except
    // una subcarpeta ilegible no impide mover: se re-apunta lo que se vio
  end;
  try
    // Safety copy of the source into the trash before relocating... salvo que
    // el origen YA sea una copia de la papelera. Hacer una copia de una copia
    // dejaba una papelera DENTRO de la papelera, con el sello doblado, y cada
    // restauracion anadia otra capa (medido 2026-09-20). Lo que se restaura no
    // necesita red: la red es el.
    if Params.Copy then
      BackupNote := ''
    else if DesdePapelera then
      BackupNote := '(el origen ya estaba en la papelera: no hago copia de una copia)'
    else
    begin
      BackupNote := TrashPathFor(Params.Path);
      CrearCarpeta(TPath.GetDirectoryName(BackupNote));
      if TDirectory.Exists(Params.Path) then
        // EL copiador: no sigue un enlace a lo que no se puede leer (25-sep-2026)
        CopiaArbol(Params.Path, BackupNote, True, NoSeguidos)
      else
        TFile.Copy(Params.Path, BackupNote);
    end;
    CrearCarpeta(TPath.GetDirectoryName(TPath.GetFullPath(Params.Dest)));
    if Params.Copy then
    begin
      if TDirectory.Exists(Params.Path) then
      begin
        // EL copiador (Lsp.Guard): sin la papelera del origen (no es
        // contenido: ni se copia ni hay que borrarla despues) y sin seguir un
        // enlace a lo que este workspace no puede leer (25-sep-2026).
        CopiaArbol(Params.Path, Params.Dest, False, NoSeguidos);
      end
      else
        TFile.Copy(Params.Path, Params.Dest);
    end
    else if TDirectory.Exists(Params.Path) then
      MueveArbol(Params.Path, Params.Dest) // renombrar o nada
    else
      TFile.Move(Params.Path, Params.Dest);
    // Restoring a copy OUT of the trash leaves its owner marker behind with
    // nothing to mark: sweep it, so the agent that restores can leave the
    // trash clean instead of a litter of .by files only the operator can lift.
    if IsBackupPath(Params.Path) and TFile.Exists(Params.Path + '.by') then
      try
        TFile.Delete(Params.Path + '.by');
      except
      end;
  except
    on E: Exception do
      Exit('ERROR al ' + IfThen(Params.Copy, 'copiar', 'mover') + ': ' + E.Message);
  end;
  Result := Format('%s'#10'  de: %s'#10'  a:  %s',
    [IfThen(Params.Copy, 'COPIADO', 'MOVIDO'), Params.Path, Params.Dest]);
  if Length(NoSeguidos) > 0 then
    Result := Result + #10 + Format(SN_COPY_LINKS_NOT_FOLLOWED_FMT,
      [Length(NoSeguidos), string.Join(', ', NoSeguidos)]);
  if not Params.Copy then // una copia no necesita red: el origen sigue ahi
    Result := Result + #10 + '  (copia de seguridad en ' + BackupNote + ')';
  if Mudanza.Count > 0 then
  begin
    var RaizVieja := IncludeTrailingPathDelimiter(TPath.GetFullPath(Params.Path));
    var RaizNueva := IncludeTrailingPathDelimiter(TPath.GetFullPath(Params.Dest));
    var Notas := '';
    for var Linea in Mudanza do
    begin
      var Pr := Linea.Substring(0, Linea.IndexOf('|'));
      var Vieja := Linea.Substring(Linea.IndexOf('|') + 1);
      var Nueva := RaizNueva + Vieja.Substring(Length(RaizVieja));
      if PathDenied(Pr) <> '' then
        R := Format(SN_FILE_PROJECT_DENIED_FMT, [TPath.GetFileName(Pr)])
      else
        try
          R := RenameProjectUnit(Pr, Vieja, Nueva);
        except
          on E: Exception do
            R := 'ERROR ' + E.Message;
        end;
      Notas := Notas + #10 + '    ' + TPath.GetFileName(Pr) + ': ' + R.Replace(#10, ' ');
    end;
    Result := Result + #10 + Format('  units de la carpeta re-apuntadas en sus proyectos (%d):',
      [Mudanza.Count]) + Notas;
  end;
  finally
    Mudanza.Free;
  end;
  if not IsUnit then
    Exit;

  // the designer pair travels with the unit
  PairNote := '';
  for Ext in ['.dfm', '.fmx'] do
  begin
    var Gemelo := DesignerJunto(Params.Path, OldStem, Ext, DesdePapelera);
    if Gemelo = '' then
      Continue;
    try
      if Params.Copy then
        TFile.Copy(Gemelo, ChangeFileExt(Params.Dest, Ext))
      else
        TFile.Move(Gemelo, ChangeFileExt(Params.Dest, Ext));
      PairNote := Format(SN_FILE_DESIGNER_TOO_FMT,
        [TPath.GetFileName(ChangeFileExt(Params.Dest, Ext)),
         IfThen(Params.Copy, 'copiado con la unit', 'movido con la unit')]);
      if DesdePapelera and TFile.Exists(Gemelo + '.by') then
        try
          TFile.Delete(Gemelo + '.by');
        except
        end;
    except
      on E: Exception do
        PairNote := Format(SN_FILE_DESIGNER_TOO_FMT,
          [TPath.GetFileName(Gemelo), 'ERROR ' + E.Message]);
    end;
  end;
  if PairNote <> '' then
    Result := Result + #10 + PairNote;

  // a rename: the header must follow the file name
  if not SameText(OldStem, NewStem) then
  try
    Src := PatchLoadText(Params.Dest, Enc);
    Src := TRegEx.Replace(Src, '^(\s*unit\s+)' + TRegEx.Escape(OldStem) + '(\s*;)',
      '${1}' + NewStem + '${2}', [roIgnoreCase, roMultiline]);
    PatchSaveText(Params.Dest, Src, Enc);
    Result := Result + #10 + '  cabecera reescrita: unit ' + NewStem + ';';
  except
    on E: Exception do
      Result := Result + #10 + '  ERROR al reescribir la cabecera (sigue diciendo unit ' +
        OldStem + ';): ' + E.Message;
  end;

  ProjNote := '';
  for P in Projects do
  begin
    if PathDenied(P) <> '' then
    begin
      ProjNote := ProjNote + #10 + Format(SN_FILE_PROJECT_DENIED_FMT, [TPath.GetFileName(P)]);
      Continue;
    end;
    try
      R := RenameProjectUnit(P, Params.Path, Params.Dest);
    except
      on E: Exception do
        R := 'ERROR ' + E.Message;
    end;
    ProjNote := ProjNote + #10 + '    ' + TPath.GetFileName(P) + ': ' + R.Replace(#10, ' ');
  end;
  if Length(Projects) > 0 then
    ProjNote := Format(SN_FILE_PROJECTS_UPDATED_FMT, [Length(Projects),
      string.Join(', ', Projects)]) + ProjNote
  else if Params.Copy then
    ProjNote := SN_FILE_COPY_NO_PROJECT
  else
    ProjNote := SN_FILE_PROJECTS_NONE;
  Result := Result + #10 + ProjNote;
end;

initialization
  BACKUP_SUB := TrashFolderName;
  TMCPRegistry.RegisterTool('delphi_delete',
    function: IMCPTool begin Result := TDelphiDeleteTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_move',
    function: IMCPTool begin Result := TDelphiMoveTool.Create; end);

end.
