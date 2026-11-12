unit LeapYears;

interface

function IsLeap(const AYear: Word): Boolean;

implementation

uses
  System.SysUtils;

function IsLeap(const AYear: Word): Boolean;
begin
  // the RTL already knows the Gregorian rule: no second copy of it
  Result := IsLeapYear(AYear);
end;

end.
