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
  MCPServer.Types;

type
  TDelphiDeleteParams = class
  private
    FPath: string;
  public
    [SchemaDescription('Absolute path of the file or folder to delete (inside the workspace roots). Moved to a recoverable trash, not hard-deleted')]
    [Required]
    property Path: string read FPath write FPath;
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
  System.IOUtils,
  System.StrUtils,
  System.RegularExpressions,
  MCPServer.Registration,
  Lsp.Guard,
  Lsp.Patch,
  Lsp.Texts,
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

procedure MoveToTrash(const APath: string; out ATrash: string);
begin
  ATrash := TrashPathFor(APath);
  TDirectory.CreateDirectory(TPath.GetDirectoryName(ATrash));
  if TDirectory.Exists(APath) then
    TDirectory.Move(APath, ATrash)
  else
    TFile.Move(APath, ATrash);
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
  if IsBackupPath(Params.Path) then
    Exit('RECHAZADO: ' + BACKUP_SUB + '\ es la papelera/copias de esta tool. ' +
      'No se borra desde aqui (purgala manualmente si de verdad quieres).');
  if not (TFile.Exists(Params.Path) or TDirectory.Exists(Params.Path)) then
    Exit('RECHAZADO: no existe ' + Params.Path);
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
        R := RemoveProjectUnit(P, Params.Path);
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
