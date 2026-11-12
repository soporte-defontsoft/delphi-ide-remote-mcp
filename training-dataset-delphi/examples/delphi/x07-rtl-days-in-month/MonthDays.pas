unit MonthDays;

interface

function DaysIn(const AYear, AMonth: Word): Word;

implementation

uses
  System.DateUtils;

function DaysIn(const AYear, AMonth: Word): Word;
begin
  Result := DaysInAMonth(AYear, AMonth); // leap years included
end;

end.
