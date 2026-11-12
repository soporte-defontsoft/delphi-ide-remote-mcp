unit FileStem;

interface

function ReportName(const AFileName: string): string;

implementation

uses
  System.SysUtils;

function ReportName(const AFileName: string): string;
begin
  Result := ChangeExt(ExtractFileName(AFileName)) + '-report.txt';
end;

end.
