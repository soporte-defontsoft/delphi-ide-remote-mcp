unit InvoiceRefs;

interface

function InvoiceRef(const AYear, ANumber: Integer): string;
function TryParseInvoiceRef(const ARef: string; out AYear, ANumber: Integer): Boolean;
function ReminderSubject(const AYear, ANumber: Integer): string;

implementation

uses
  System.SysUtils;

function InvoiceRef(const AYear, ANumber: Integer): string;
begin
  Result := Format('INV-%d-%.5d', [AYear, ANumber]);
end;

function TryParseInvoiceRef(const ARef: string; out AYear, ANumber: Integer): Boolean;
begin
  // INV-yyyy-nnnnn: 14 characters
  AYear := 0;
  ANumber := 0;
  Result := (Length(ARef) = 14) and ARef.StartsWith('INV-') and (ARef[9] = '-') and
    TryStrToInt(Copy(ARef, 5, 4), AYear) and TryStrToInt(Copy(ARef, 10, 5), ANumber);
end;

function ReminderSubject(const AYear, ANumber: Integer): string;
begin
  Result := 'Payment reminder: ' + InvoiceRef(AYear, ANumber);
end;

end.
