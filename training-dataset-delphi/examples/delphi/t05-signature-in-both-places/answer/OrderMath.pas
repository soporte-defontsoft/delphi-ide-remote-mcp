unit OrderMath;

interface

type
  TOrder = class
  private
    FAmount: Currency;
  public
    constructor Create(const AAmount: Currency);
    function Total(const ADiscountPercent: Currency): Currency;
  end;

implementation

constructor TOrder.Create(const AAmount: Currency);
begin
  inherited Create;
  FAmount := AAmount;
end;

function TOrder.Total(const ADiscountPercent: Currency): Currency;
begin
  Result := FAmount - FAmount * ADiscountPercent / 100;
end;

end.
