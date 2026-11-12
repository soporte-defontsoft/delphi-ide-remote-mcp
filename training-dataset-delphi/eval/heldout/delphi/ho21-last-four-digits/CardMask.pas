unit CardMask;

interface

// '**** ' and the last four digits of a card number (digits only, at least four)
function MaskCard(const ANumber: string): string;

implementation

function MaskCard(const ANumber: string): string;
begin
  // a string starts at 1, so its last four characters start at Length - 3
  Result := '**** ' + Copy(ANumber, Length(ANumber) - 3, 4);
end;

end.
