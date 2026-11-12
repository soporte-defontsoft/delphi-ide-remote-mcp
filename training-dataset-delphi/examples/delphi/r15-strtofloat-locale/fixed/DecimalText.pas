unit DecimalText;

interface

function ParseDecimal(const AText: string): Double;

implementation

uses
  System.SysUtils;

function ParseDecimal(const AText: string): Double;
begin
  // the file's decimal point is not the user's: parse with the invariant settings
  Result := StrToFloat(AText, TFormatSettings.Invariant);
end;

end.
