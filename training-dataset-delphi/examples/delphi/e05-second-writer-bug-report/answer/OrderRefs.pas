unit OrderRefs;

interface

function OrderRef(const AYear, ANumber: Integer): string;
function ArchiveOrderRef(const AYear, ANumber: Integer): string;
function TryParseOrderRef(const ARef: string; out AYear, ANumber: Integer): Boolean;

implementation

uses
  System.SysUtils;

// The one writer of an order reference; TryParseOrderRef is its inverse
function OrderRef(const AYear, ANumber: Integer): string;
begin
  Result := Format('ORD-%d-%.5d', [AYear, ANumber]);
end;

function ArchiveOrderRef(const AYear, ANumber: Integer): string;
begin
  Result := OrderRef(AYear, ANumber);
end;

function TryParseOrderRef(const ARef: string; out AYear, ANumber: Integer): Boolean;
begin
  // ORD-yyyy-nnnnn: 14 characters
  AYear := 0;
  ANumber := 0;
  Result := (Length(ARef) = 14) and ARef.StartsWith('ORD-') and (ARef[9] = '-') and
    TryStrToInt(Copy(ARef, 5, 4), AYear) and TryStrToInt(Copy(ARef, 10, 5), ANumber);
end;

end.
