unit SendStatus;

interface

function SentText: string;

implementation

function SentText: string;
begin
  // U+2714 HEAVY CHECK MARK, written outside the quotes
  Result := 'Sent ' + #$2714;
end;

end.
