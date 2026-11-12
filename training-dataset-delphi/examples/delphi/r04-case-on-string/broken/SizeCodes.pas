unit SizeCodes;

interface

function SizeOrder(const ASize: string): Integer;

implementation

function SizeOrder(const ASize: string): Integer;
begin
  case ASize of
    'S': Result := 1;
    'M': Result := 2;
    'L': Result := 3;
  else
    Result := 0;
  end;
end;

end.
