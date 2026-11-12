unit LotCodes;

interface

// The code of a production lot: its line and the day it was made, 'L3-20260307'
function LotCode(const ALine: Integer; const ADay: TDateTime): string;
// The code the label printer puts on each box of a lot
function LabelLotCode(const ALine: Integer; const ADay: TDateTime): string;
// Reads a lot code back: its line and its day
function TryParseLotCode(const ACode: string; out ALine: Integer; out ADay: TDateTime): Boolean;

implementation

uses
  System.SysUtils;

function LotCode(const ALine: Integer; const ADay: TDateTime): string;
begin
  Result := Format('L%d-%s', [ALine, FormatDateTime('yyyymmdd', ADay)]);
end;

function LabelLotCode(const ALine: Integer; const ADay: TDateTime): string;
begin
  Result := 'L' + IntToStr(ALine) + '-' + FormatDateTime('dd.mm.yyyy', ADay);
end;

function TryParseLotCode(const ACode: string; out ALine: Integer; out ADay: TDateTime): Boolean;
var
  Dash, Y, M, D: Integer;
  Day: string;
begin
  Result := False;
  ALine := 0;
  ADay := 0;
  Dash := Pos('-', ACode);
  if (Copy(ACode, 1, 1) <> 'L') or (Dash < 3) or not TryStrToInt(Copy(ACode, 2, Dash - 2), ALine) then
    Exit;
  Day := Copy(ACode, Dash + 1, MaxInt);
  if (Length(Day) <> 8) or not TryStrToInt(Copy(Day, 1, 4), Y) or not TryStrToInt(Copy(Day, 5, 2), M) or
    not TryStrToInt(Copy(Day, 7, 2), D) then
    Exit;
  Result := TryEncodeDate(Y, M, D, ADay);
end;

end.
