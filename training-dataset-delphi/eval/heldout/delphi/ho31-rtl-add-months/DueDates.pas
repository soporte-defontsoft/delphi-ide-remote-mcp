unit DueDates;

interface

// The same day AMonths months later (earlier when negative), or the last day of that month when it is shorter;
// the time of day stays
function DueDate(const AStart: TDateTime; const AMonths: Integer): TDateTime;

implementation

uses
  System.SysUtils;

function DueDate(const AStart: TDateTime; const AMonths: Integer): TDateTime;
begin
  // IncMonth already stops at the last day of a shorter month, and keeps the time
  Result := IncMonth(AStart, AMonths);
end;

end.
