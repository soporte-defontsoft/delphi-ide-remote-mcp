unit Money;

interface

function TotalOf(const APrices: array of Currency): Currency;

implementation

function TotalOf(const APrices: array of Currency): Currency;
var
  Price: Currency;
begin
  // Currency is fixed-point with four decimals: 0.10 + 0.20 is exactly 0.30.
  // With Double it is not (binary floating point cannot hold 0.1 exactly).
  Result := 0;
  for Price in APrices do
    Result := Result + Price;
end;

end.
