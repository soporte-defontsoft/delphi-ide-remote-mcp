unit CodePrefix;

interface

function Prefix3(const ACode: string): string;

implementation

function Prefix3(const ACode: string): string;
begin
  // Copy counts from 1 and clips: a shorter code comes back whole
  Result := Copy(ACode, 1, 3);
end;

end.
