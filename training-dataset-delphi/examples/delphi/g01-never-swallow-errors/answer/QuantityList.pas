unit QuantityList;

interface

// Sums the quantities of the lines; ABad returns how many lines were not a number
function SumQuantities(const ALines: array of string; out ABad: Integer): Integer;

implementation

uses
  System.SysUtils;

function SumQuantities(const ALines: array of string; out ABad: Integer): Integer;
var
  Line: string;
  Quantity: Integer;
begin
  Result := 0;
  ABad := 0;
  for Line in ALines do
    if TryStrToInt(Trim(Line), Quantity) then
      Inc(Result, Quantity)
    else
      Inc(ABad); // the case we expect is checked and reported, not swallowed
end;

end.
