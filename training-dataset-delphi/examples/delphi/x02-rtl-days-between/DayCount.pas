unit DayCount;

interface

function DaysApart(const AFrom, ATo: TDateTime): Integer;

implementation

uses
  System.DateUtils;

function DaysApart(const AFrom, ATo: TDateTime): Integer;
begin
  // whole 24-hour days, in either order
  Result := DaysBetween(AFrom, ATo);
end;

end.
