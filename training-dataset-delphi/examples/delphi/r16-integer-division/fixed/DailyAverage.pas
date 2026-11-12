unit DailyAverage;

interface

function UnitsPerDay(const ATotalUnits, ADays: Integer): Integer;

implementation

function UnitsPerDay(const ATotalUnits, ADays: Integer): Integer;
begin
  // "/" always gives a real number; "div" is the integer division (it truncates)
  Result := ATotalUnits div ADays;
end;

end.
