unit DailyAverage;

interface

function UnitsPerDay(const ATotalUnits, ADays: Integer): Integer;

implementation

function UnitsPerDay(const ATotalUnits, ADays: Integer): Integer;
begin
  Result := ATotalUnits / ADays;
end;

end.
