unit BackupFiles;

interface

function BackupFileName(const ADay: TDateTime): string;
function NightlyBackupFileName(const ADay: TDateTime): string;
function TryBackupDay(const AFileName: string; out ADay: TDateTime): Boolean;

implementation

uses
  System.SysUtils;

function BackupFileName(const ADay: TDateTime): string;
begin
  Result := 'backup_' + FormatDateTime('yyyy-mm-dd', ADay) + '.zip';
end;

function NightlyBackupFileName(const ADay: TDateTime): string;
begin
  Result := 'backup_' + FormatDateTime('yyyymmdd', ADay) + '.zip';
end;

function TryBackupDay(const AFileName: string; out ADay: TDateTime): Boolean;
var
  Y, M, D: Integer;
begin
  // backup_yyyy-mm-dd.zip: 21 characters
  ADay := 0;
  Result := (Length(AFileName) = 21) and AFileName.StartsWith('backup_') and AFileName.EndsWith('.zip') and
    (AFileName[12] = '-') and (AFileName[15] = '-') and
    TryStrToInt(Copy(AFileName, 8, 4), Y) and TryStrToInt(Copy(AFileName, 13, 2), M) and
    TryStrToInt(Copy(AFileName, 16, 2), D) and TryEncodeDate(Y, M, D, ADay);
end;

end.
