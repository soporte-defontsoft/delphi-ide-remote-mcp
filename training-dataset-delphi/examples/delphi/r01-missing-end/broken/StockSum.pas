unit StockSum;

interface

function SumPositive(const AValues: array of Integer): Integer;

implementation

function SumPositive(const AValues: array of Integer): Integer;
var
  Value: Integer;
begin
  Result := 0;
  for Value in AValues do
  begin
    if Value > 0 then
      Inc(Result, Value);
end;

end.
