unit DecimalText;

interface

function ParseDecimal(const AText: string): Double;

implementation

uses
  System.SysUtils;

function ParseDecimal(const AText: string): Double;
begin
  Result := StrToFloat(AText);
end;

end.
