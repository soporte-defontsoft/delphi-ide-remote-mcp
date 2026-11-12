unit WeekNumbers;

interface

// The ISO 8601 week number of a date (weeks start on Monday; week 1 holds the year's first Thursday)
function IsoWeek(const ADate: TDateTime): Integer;

implementation

uses
  System.DateUtils;

function IsoWeek(const ADate: TDateTime): Integer;
begin
  // WeekOfTheYear follows ISO 8601: 3 January 2021 is in week 53 (of 2020), 30 December 2024 in week 1
  Result := WeekOfTheYear(ADate);
end;

end.
