unit CustomerText;

interface

function FullName(const AFirst, ALast: string): string;
function CustomerLabel(const AFirst, ALast: string): string;

implementation

uses
  System.SysUtils;

function FullName(const AFirst, ALast: string): string;
begin
  Result := Trim(Trim(AFirst) + ' ' + Trim(ALast));
end;

function CustomerLabel(const AFirst, ALast: string): string;
begin
  Result := 'Customer: ' + FullName(AFirst, ALast);
end;

end.
