unit DayKeys;

interface

function DayKey(const ADate: TDateTime): string;
function ArchiveDayKey(const ADate: TDateTime): string;
function TryDayKeyToDate(const AKey: string; out ADate: TDateTime): Boolean;

implementation

uses
  System.SysUtils;

// The one writer of a day key (yyyymmdd); TryDayKeyToDate is its inverse
function DayKey(const ADate: TDateTime): string;
begin
  Result := FormatDateTime('yyyymmdd', ADate);
end;

function ArchiveDayKey(const ADate: TDateTime): string;
begin
  Result := DayKey(ADate);
end;

function TryDayKeyToDate(const AKey: string; out ADate: TDateTime): Boolean;
var
  Y, M, D: Integer;
begin
  ADate := 0;
  Result := (Length(AKey) = 8) and TryStrToInt(Copy(AKey, 1, 4), Y) and
    TryStrToInt(Copy(AKey, 5, 2), M) and TryStrToInt(Copy(AKey, 7, 2), D) and
    (Y > 0) and (M > 0) and (D > 0) and TryEncodeDate(Y, M, D, ADate);
end;

end.
