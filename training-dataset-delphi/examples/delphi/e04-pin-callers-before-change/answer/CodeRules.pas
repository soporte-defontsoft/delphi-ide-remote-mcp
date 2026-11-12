unit CodeRules;

interface

function NormalizeCode(const ACode: string): string;
function IsDiscontinued(const ACode: string): Boolean;
function IsSeasonal(const ACode: string): Boolean;

implementation

uses
  System.SysUtils, System.StrUtils;

const
  Discontinued: array[0..1] of string = ('K-100', 'K-220');
  Seasonal: array[0..1] of string = ('W-010', 'W-020');

function NormalizeCode(const ACode: string): string;
begin
  // every space goes, inside included: ' k - 100 ' -> 'K-100'
  Result := UpperCase(ACode.Replace(' ', ''));
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
