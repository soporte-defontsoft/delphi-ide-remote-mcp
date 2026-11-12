unit IsoStamp;

interface

function ParseStamp(const AText: string): TDateTime;

implementation

uses
  System.DateUtils;

function ParseStamp(const AText: string): TDateTime;
begin
  // a time without an offset is read as UTC, and the default (AReturnUTC = True)
  // returns it as written; False would convert it to the local time zone
  Result := ISO8601ToDate(AText);
end;

end.
