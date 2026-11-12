unit FileStem;

interface

function ReportName(const AFileName: string): string;

implementation

uses
  System.SysUtils;

function ReportName(const AFileName: string): string;
begin
  // ChangeFileExt with an empty extension drops it: 'C:\data\sales.csv' -> 'sales'
  Result := ChangeFileExt(ExtractFileName(AFileName), '') + '-report.txt';
end;

end.
