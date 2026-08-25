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
  Lsp.Texts;   // SchemaDescription texts: attributes are interface-level

type
  TDelphiDeleteParams = class
  private
    FPath: string;
    FPurge: Boolean;
  public
    [SchemaDescription('Absolute path of the file or folder to delete (inside the workspace roots). Moved to a recoverable trash, not hard-deleted')]
    [Required]
    property Path: string read FPath write FPath;
    [SchemaDescription(SP_DELETE_PURGE)]
    property Purge: Boolean read FPurge write FPurge;
  end;

  TDelphiMoveParams = class
  private
    FPath: string;
    FDest: string;
  public
    [SchemaDescription('Absolute path of the file or folder to move (inside the workspace roots)')]
    [Required]
    property Path: string read FPath write FPath;
    [SchemaDescription('Destination absolute path (inside the workspace roots). Parent folders are created. Renames when the parent is the same')]
    [Required]
    property Dest: string read FDest write FDest;
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
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.RegularExpressions,
  MCPServer.Registration,
  Lsp.Guard,
  Lsp.Patch,
  Lsp.ProjectUnits;

const
  BACKUP_SUB = '__delphi-patch';

{ Where a deleted/overwritten item is parked, next to it: recoverable. }
function TrashPathFor(const APath: string): string;
var
  Dir, Day, Name: string;
begin
  Dir := TPath.GetDirectoryName(ExcludeTrailingPathDelimiter(APath));
  Day := FormatDateTime('yyyymmdd', Now);
  Name := TPath.GetFileName(ExcludeTrailingPathDelimiter(APath)) + '-' +
    FormatDateTime('hhnnsszzz', Now);
  Result := TPath.Combine(TPath.Combine(TPath.Combine(Dir, BACKUP_SUB), Day),
    TPath.Combine('deleted', Name));
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

procedure MoveToTrash(const APath: string; out ATrash: string);
begin
  ATrash := TrashPathFor(APath);
  TDirectory.CreateDirectory(TPath.GetDirectoryName(ATrash));
  if TDirectory.Exists(APath) then
  begin
    // A rename can fail for reasons nobody here can see - a handle somebody
    // else holds, a subfolder that is somebody's working directory. When it
    // does, copy the tree to the trash and then take away what CAN be taken
    // away, so the recoverable copy exists either way.
    try
      TDirectory.Move(APath, ATrash);
    except
      TDirectory.Copy(APath, ATrash);
      ClearReadOnlyTree(APath);
      try
        TDirectory.Delete(APath, True);
      except
        // leave it: the caller checks and REPORTS what is still there
      end;
    end;
  end
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
    'Jailed to the workspace roots, refused in read-only mode. Use it to ' +
    'clean up stray files and leftovers. Deleting a unit (.pas) also trashes ' +
    'its .dfm/.fmx and takes it out of every project in its folder or the ' +
    'parent folder that lists it (uses, CreateForm, DCCReference). To keep ' +
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
        ClearReadOnlyTree(Params.Path);
        TDirectory.Delete(Params.Path, True);
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
  end;
  try
    MoveToTrash(Params.Path, Trash);
  except
    on E: Exception do
    begin
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
  FDescription := 'Move or rename a file or folder inside the workspace. Both ' +
    'source and destination must be inside the workspace roots; parent ' +
    'folders of the destination are created. The source is copied to the ' +
    'recoverable trash first. Jailed, refused in read-only mode. Moving or ' +
    'renaming a unit (.pas) moves its .dfm/.fmx with it, rewrites its "unit X;" ' +
    'header on a rename, and re-points every project in its folder or the ' +
    'parent folder that lists it (uses + DCCReference).';
end;

function TDelphiMoveTool.ExecuteWithParams(const Params: TDelphiMoveParams): string;
var
  Denied, BackupNote, Ext, Enc, Src, OldStem, NewStem, ProjNote, P, R, PairNote: string;
  Projects: TArray<string>;
  IsUnit: Boolean;
begin
  if Params.Dest.Trim = '' then
    Exit('RECHAZADO: delphi_move necesita "dest" (ruta destino).');
  Denied := PathDenied(Params.Path);
  if Denied <> '' then
    Exit(Denied);
  Denied := PathDenied(Params.Dest);
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
  IsUnit := TFile.Exists(Params.Path) and (TPath.GetExtension(Params.Path).ToLower = '.pas');
  Projects := [];
  OldStem := TPath.GetFileNameWithoutExtension(Params.Path);
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
    Projects := ProjectsUsingUnit(Params.Path);
  end;
  try
    // Safety copy of the source into the trash before relocating.
    BackupNote := TrashPathFor(Params.Path);
    TDirectory.CreateDirectory(TPath.GetDirectoryName(BackupNote));
    if TDirectory.Exists(Params.Path) then
      TDirectory.Copy(Params.Path, BackupNote)
    else
      TFile.Copy(Params.Path, BackupNote);
    TDirectory.CreateDirectory(TPath.GetDirectoryName(TPath.GetFullPath(Params.Dest)));
    if TDirectory.Exists(Params.Path) then
      TDirectory.Move(Params.Path, Params.Dest)
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
      Exit('ERROR al mover: ' + E.Message);
  end;
  Result := Format('MOVIDO'#10'  de: %s'#10'  a:  %s'#10'  (copia de seguridad en %s)',
    [Params.Path, Params.Dest, BackupNote]);
  if not IsUnit then
    Exit;

  // the designer pair travels with the unit
  PairNote := '';
  for Ext in ['.dfm', '.fmx'] do
    if TFile.Exists(ChangeFileExt(Params.Path, Ext)) then
    try
      TFile.Move(ChangeFileExt(Params.Path, Ext), ChangeFileExt(Params.Dest, Ext));
      PairNote := Format(SN_FILE_DESIGNER_TOO_FMT,
        [TPath.GetFileName(ChangeFileExt(Params.Dest, Ext)), 'movido con la unit']);
    except
      on E: Exception do
        PairNote := Format(SN_FILE_DESIGNER_TOO_FMT,
          [TPath.GetFileName(ChangeFileExt(Params.Path, Ext)), 'ERROR ' + E.Message]);
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
  else
    ProjNote := SN_FILE_PROJECTS_NONE;
  Result := Result + #10 + ProjNote;
end;

initialization
  TMCPRegistry.RegisterTool('delphi_delete',
    function: IMCPTool begin Result := TDelphiDeleteTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_move',
    function: IMCPTool begin Result := TDelphiMoveTool.Create; end);

end.
