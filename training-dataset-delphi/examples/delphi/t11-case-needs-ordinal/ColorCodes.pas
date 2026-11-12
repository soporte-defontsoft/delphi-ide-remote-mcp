unit ColorCodes;

interface

function ColorCode(const AName: string): Integer;

implementation

uses
  System.StrUtils;

function ColorCode(const AName: string): Integer;
begin
  // case needs an ordinal value: turn the name into its index first
  case IndexText(AName, ['red', 'green', 'blue']) of
    0: Result := $0000FF;
    1: Result := $00FF00;
    2: Result := $FF0000;
  else
    Result := -1;
  end;
end;

end.
