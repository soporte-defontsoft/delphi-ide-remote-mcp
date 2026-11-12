unit ProductCodes;

interface

function NormalizeCode(const ACode: string): string;
function IsDiscontinued(const ACode: string): Boolean;
function IsSeasonal(const ACode: string): Boolean;

implementation

uses
  System.SysUtils, System.StrUtils;

const
  Discontinued: array[0..1] of string = ('A-100', 'B-220');
  Seasonal: array[0..1] of string = ('S-010', 'S-020');

function NormalizeCode(const ACode: string): string;
begin
  Result := UpperCase(Trim(ACode));
end;

function IsDiscontinued(const ACode: string): Boolean;
begin
  Result := IndexStr(NormalizeCode(ACode), Discontinued) >= 0;
end;

function IsSeasonal(const ACode: string): Boolean;
begin
  Result := IndexStr(NormalizeCode(ACode), Seasonal) >= 0;
end;

end.
