unit ReportLines;

interface

function InvoiceLine(const ANumber: Integer; const ADate: TDateTime): string;
function DeliveryLine(const ANumber: Integer; const ADate: TDateTime): string;
function ReturnLine(const ANumber: Integer; const ADate: TDateTime): string;

implementation

uses
  System.SysUtils;

// The one place that knows the shape of a document line
function DocumentLine(const AKind: string; const ANumber: Integer;
  const ADate: TDateTime): string;
begin
  Result := Format('%s %d - %s', [AKind, ANumber, FormatDateTime('yyyy-mm-dd', ADate)]);
end;

function InvoiceLine(const ANumber: Integer; const ADate: TDateTime): string;
begin
  Result := DocumentLine('Invoice', ANumber, ADate);
end;

function DeliveryLine(const ANumber: Integer; const ADate: TDateTime): string;
begin
  Result := DocumentLine('Delivery', ANumber, ADate);
end;

function ReturnLine(const ANumber: Integer; const ADate: TDateTime): string;
begin
  Result := DocumentLine('Return', ANumber, ADate);
end;

end.
