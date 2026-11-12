unit TimeText;

interface

function MinuteSecond(const AValue: TDateTime): string;

implementation

uses
  System.SysUtils;

function MinuteSecond(const AValue: TDateTime): string;
begin
  // nn = minutes; mm here would be the MONTH (it only means minutes after an hour)
  Result := FormatDateTime('nn:ss', AValue);
end;

end.
