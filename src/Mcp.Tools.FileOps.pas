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
    property Path: string read FPath write FPath;
  end;

  TDelphiMoveParams = class
  private
    FPath: string;
    FDest: string;
  public
    [SchemaDescription('Absolute path of the file or folder to move (inside the workspace roots)')]
    property Path: string read FPath write FPath;
    [SchemaDescription('Destination absolute path (inside the workspace roots). Parent folders are created. Renames when the parent is the same')]
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
  MCPServer.Registration,
  Lsp.Guard;

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
    'clean up stray files and leftovers.';
end;

function TDelphiDeleteTool.ExecuteWithParams(const Params: TDelphiDeleteParams): string;
var
  Denied, Trash: string;
begin
  Denied := PathDenied(Params.Path);
  if Denied <> '' then
    Exit(Denied);
  if IsBackupPath(Params.Path) then
    Exit('RECHAZADO: ' + BACKUP_SUB + '\ es la papelera/copias de esta tool. ' +
      'No se borra desde aqui (purgala manualmente si de verdad quieres).');
  if not (TFile.Exists(Params.Path) or TDirectory.Exists(Params.Path)) then
    Exit('RECHAZADO: no existe ' + Params.Path);
  try
    MoveToTrash(Params.Path, Trash);
  except
    on E: Exception do
      Exit('ERROR al mover a la papelera: ' + E.Message);
  end;
  Result := Format('BORRADO %s (movido a la papelera recuperable).'#10 +
    '  copia: %s'#10'  Para recuperarlo, delphi_move desde esa ruta.',
    [TPath.GetFileName(ExcludeTrailingPathDelimiter(Params.Path)), Trash]);
end;

{ TDelphiMoveTool }

constructor TDelphiMoveTool.Create;
begin
  inherited;
  FName := 'delphi_move';
  FDescription := 'Move or rename a file or folder inside the workspace. Both ' +
    'source and destination must be inside the workspace roots; parent ' +
    'folders of the destination are created. The source is copied to the ' +
    'recoverable trash first. Jailed, refused in read-only mode.';
end;

function TDelphiMoveTool.ExecuteWithParams(const Params: TDelphiMoveParams): string;
var
  Denied, BackupNote: string;
begin
  if Params.Dest.Trim = '' then
    Exit('RECHAZADO: delphi_move necesita "dest" (ruta destino).');
  Denied := PathDenied(Params.Path);
  if Denied <> '' then
    Exit(Denied);
  Denied := PathDenied(Params.Dest);
  if Denied <> '' then
    Exit(Denied);
  if IsBackupPath(Params.Path) or IsBackupPath(Params.Dest) then
    Exit('RECHAZADO: ' + BACKUP_SUB + '\ es la papelera/copias de esta tool; no se mueve por aqui.');
  if not (TFile.Exists(Params.Path) or TDirectory.Exists(Params.Path)) then
    Exit('RECHAZADO: no existe el origen ' + Params.Path);
  if TFile.Exists(Params.Dest) or TDirectory.Exists(Params.Dest) then
    Exit('RECHAZADO: el destino ya existe: ' + Params.Dest + ' (no sobreescribo).');
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
end;

initialization
  TMCPRegistry.RegisterTool('delphi_delete',
    function: IMCPTool begin Result := TDelphiDeleteTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_move',
    function: IMCPTool begin Result := TDelphiMoveTool.Create; end);

end.
