unit ReportLines;

interface

function InvoiceLine(const ANumber: Integer; const ADate: TDateTime): string;
function DeliveryLine(const ANumber: Integer; const ADate: TDateTime): string;

implementation

uses
  System.SysUtils;

function InvoiceLine(const ANumber: Integer; const ADate: TDateTime): string;
begin
  Result := Format('Invoice %d - %s', [ANumber, FormatDateTime('yyyy-mm-dd', ADate)]);
end;

function DeliveryLine(const ANumber: Integer; const ADate: TDateTime): string;
begin
  Result := Format('Delivery %d - %s', [ANumber, FormatDateTime('yyyy-mm-dd', ADate)]);
end;

end.
