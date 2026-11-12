unit InvoiceMath;

interface

type
  TInvoice = class
  private
    FBase: Currency;
  public
    constructor Create(const ABase: Currency);
    function Gross(const ATaxPercent: Currency): Currency;
  end;

implementation

constructor TInvoice.Create(const ABase: Currency);
begin
  inherited Create;
  FBase := ABase;
end;

function TInvoice.Gross: Currency;
begin
  Result := FBase;
end;

end.
