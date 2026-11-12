unit SizeCodes;

interface

function SizeOrder(const ASize: string): Integer;

implementation

uses
  System.StrUtils;

function SizeOrder(const ASize: string): Integer;
begin
  // case needs an ordinal value: look the string up and branch on its index
  case IndexStr(ASize, ['S', 'M', 'L']) of
    0: Result := 1;
    1: Result := 2;
    2: Result := 3;
  else
    Result := 0;
  end;
end;

end.
