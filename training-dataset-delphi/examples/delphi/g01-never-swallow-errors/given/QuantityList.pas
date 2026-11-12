unit QuantityList;

interface

function SumQuantities(const ALines: array of string): Integer;

implementation

uses
  System.SysUtils;

function SumQuantities(const ALines: array of string): Integer;
var
  Line: string;
begin
  Result := 0;
  for Line in ALines do
    try
      Inc(Result, StrToInt(Trim(Line)));
    except
    end;
end;

end.
