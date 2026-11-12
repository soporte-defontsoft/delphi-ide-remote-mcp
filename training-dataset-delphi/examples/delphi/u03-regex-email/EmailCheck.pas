unit EmailCheck;

interface

function LooksLikeEmail(const AText: string): Boolean;

implementation

uses
  System.RegularExpressions;

function LooksLikeEmail(const AText: string): Boolean;
begin
  // a plausibility check (something@something.something), not a full RFC 5322 validator
  Result := TRegEx.IsMatch(AText, '^[^@\s]+@[^@\s]+\.[^@\s]+$');
end;

end.
