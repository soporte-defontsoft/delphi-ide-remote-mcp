unit PriceRounding;

interface

function RoundPrice(const AValue: Double): Double;
function LineTotal(const AUnitPrice: Double; const AQuantity: Integer): Double;
function WithTax(const AAmount, ARate: Double): Double;

implementation

uses
  System.Math;

function RoundPrice(const AValue: Double): Double;
begin
  // RoundTo (like Round) rounds a half to the EVEN digit: 0.125 -> 0.12.
  // SimpleRoundTo rounds a half away from zero: 0.125 -> 0.13
  Result := SimpleRoundTo(AValue, -2);
end;

function LineTotal(const AUnitPrice: Double; const AQuantity: Integer): Double;
begin
  Result := RoundPrice(AUnitPrice * AQuantity);
end;

function WithTax(const AAmount, ARate: Double): Double;
begin
  Result := RoundPrice(AAmount * (1 + ARate));
end;

end.
