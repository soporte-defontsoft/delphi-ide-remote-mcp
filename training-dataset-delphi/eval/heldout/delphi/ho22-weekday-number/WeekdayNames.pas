unit WeekdayNames;

interface

// The ISO number of an English weekday name in any case: Monday 1 to Sunday 7; anything else 0
function WeekdayNumber(const AName: string): Integer;

implementation

uses
  System.StrUtils;

function WeekdayNumber(const AName: string): Integer;
begin
  // a case statement needs an ordinal value; IndexText compares without regard to case, and gives -1 when
  // nothing matches
  Result := IndexText(AName, ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday']) + 1;
end;

end.
