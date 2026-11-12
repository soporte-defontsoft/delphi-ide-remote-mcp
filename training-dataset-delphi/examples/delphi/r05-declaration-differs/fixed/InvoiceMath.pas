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

function TInvoice.Gross(const ATaxPercent: Currency): Currency;
begin
  Result := FBase + FBase * ATaxPercent / 100;
end;

end.
