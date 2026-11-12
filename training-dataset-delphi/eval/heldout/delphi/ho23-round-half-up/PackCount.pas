unit PackCount;

interface

// A quantity (never negative) rounded to whole units, halves up: 2.5 gives 3
function WholeUnits(const AQuantity: Double): Integer;

implementation

uses
  System.Math;

function WholeUnits(const AQuantity: Double): Integer;
begin
  // Round would give 2 for 2.5: it rounds a half to the even number. SimpleRoundTo rounds a half up.
  Result := Trunc(SimpleRoundTo(AQuantity, 0));
end;

end.
