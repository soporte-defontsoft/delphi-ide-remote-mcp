unit DayKeys;

interface

function DayKey(const ADate: TDateTime): string;
function ArchiveDayKey(const ADate: TDateTime): string;

implementation

uses
  System.SysUtils, System.DateUtils;

function DayKey(const ADate: TDateTime): string;
begin
  Result := FormatDateTime('yyyymmdd', ADate);
end;

function ArchiveDayKey(const ADate: TDateTime): string;
begin
  Result := Format('%d%d%d', [YearOf(ADate), MonthOf(ADate), DayOf(ADate)]);
end;

end.
