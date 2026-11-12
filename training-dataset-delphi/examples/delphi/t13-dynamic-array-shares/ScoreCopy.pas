unit ScoreCopy;

interface

function WithBonus(const AScores: TArray<Integer>; const ABonus: Integer): TArray<Integer>;

implementation

function WithBonus(const AScores: TArray<Integer>; const ABonus: Integer): TArray<Integer>;
var
  I: Integer;
begin
  // a dynamic array is a reference: "Result := AScores" would SHARE it, and adding the
  // bonus would change the caller's array too. Copy makes an independent array.
  Result := Copy(AScores);
  for I := 0 to High(Result) do
    Inc(Result[I], ABonus);
end;

end.
