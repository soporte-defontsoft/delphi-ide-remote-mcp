unit Percentages;

interface

function ApplyDiscount(const AAmount, APercent: Currency): Currency;
function ApplySurcharge(const AAmount, APercent: Currency): Currency;
function Commission(const AAmount, APercent: Currency): Currency;

implementation

uses
  System.SysUtils;

function ApplyDiscount(const AAmount, APercent: Currency): Currency;
begin
  if (APercent < 0) or (APercent > 100) then
    raise EArgumentOutOfRangeException.Create('Percent must be between 0 and 100');
  Result := AAmount - AAmount * APercent / 100;
end;

function ApplySurcharge(const AAmount, APercent: Currency): Currency;
begin
  if (APercent < 0) or (APercent > 100) then
    raise EArgumentOutOfRangeException.Create('Percent must be between 0 and 100');
  Result := AAmount + AAmount * APercent / 100;
end;

function Commission(const AAmount, APercent: Currency): Currency;
begin
  if APercent > 100 then
    raise EArgumentOutOfRangeException.Create('Percent must be between 0 and 100');
  Result := AAmount * APercent / 100;
end;

end.
