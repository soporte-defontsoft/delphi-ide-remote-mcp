unit PhoneBook;

interface

// The digits of a phone number, with '+' first for an international one ('00' at the start counts as '+'):
// '+34 600-12 34 56' and '0034 600 123 456' both give '+34600123456'
function NormalizePhone(const APhone: string): string;

implementation

uses
  System.SysUtils;

function NormalizePhone(const APhone: string): string;
var
  C: Char;
begin
  Result := '';
  for C in Trim(APhone) do
    if CharInSet(C, ['0'..'9']) or ((C = '+') and (Result = '')) then
      Result := Result + C;
  if Result.StartsWith('00') then
    Result := '+' + Copy(Result, 3, MaxInt);
end;

end.
