unit LapTimes;

interface

// A lap time under one hour as minutes:seconds.milliseconds - 83250 gives '01:23.250'
function LapText(const AMilliseconds: Integer): string;

implementation

uses
  System.SysUtils;

function LapText(const AMilliseconds: Integer): string;
begin
  // nn is the minutes; mm here would be the MONTH (it means minutes only right after an hour)
  Result := FormatDateTime('nn:ss.zzz', AMilliseconds / MSecsPerDay);
end;

end.
