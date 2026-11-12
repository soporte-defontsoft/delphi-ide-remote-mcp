unit ExportNames;

interface

function ExportFileName(const AYear, ANumber: Integer): string;
function ArchiveFileName(const AYear, ANumber: Integer): string;
function TryParseExportFileName(const AName: string; out AYear, ANumber: Integer): Boolean;

implementation

uses
  System.SysUtils;

const
  ExportPrefix = 'export-';
  ExportSuffix = '.csv';

// The one writer of the name; TryParseExportFileName is its inverse
function ExportFileName(const AYear, ANumber: Integer): string;
begin
  Result := Format(ExportPrefix + '%d-%.4d' + ExportSuffix, [AYear, ANumber]);
end;

function ArchiveFileName(const AYear, ANumber: Integer): string;
begin
  Result := ExportFileName(AYear, ANumber);
end;

function TryParseExportFileName(const AName: string; out AYear, ANumber: Integer): Boolean;
var
  Middle: string;
  Dash: Integer;
begin
  AYear := 0;
  ANumber := 0;
  Result := False;
  if not (AName.StartsWith(ExportPrefix) and AName.EndsWith(ExportSuffix)) then
    Exit;
  Middle := Copy(AName, Length(ExportPrefix) + 1,
    Length(AName) - Length(ExportPrefix) - Length(ExportSuffix));
  Dash := Pos('-', Middle);
  if Dash = 0 then
    Exit;
  Result := TryStrToInt(Copy(Middle, 1, Dash - 1), AYear) and
    TryStrToInt(Copy(Middle, Dash + 1, MaxInt), ANumber);
end;

end.
