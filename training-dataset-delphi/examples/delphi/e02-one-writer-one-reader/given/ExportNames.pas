unit ExportNames;

interface

function ExportFileName(const AYear, ANumber: Integer): string;
function ArchiveFileName(const AYear, ANumber: Integer): string;

implementation

uses
  System.SysUtils;

function ExportFileName(const AYear, ANumber: Integer): string;
begin
  Result := Format('export-%d-%.4d.csv', [AYear, ANumber]);
end;

function ArchiveFileName(const AYear, ANumber: Integer): string;
begin
  Result := 'export-' + IntToStr(AYear) + '-' + IntToStr(ANumber) + '.csv';
end;

end.
