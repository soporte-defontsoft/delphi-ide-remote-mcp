unit OrderMath;

interface

type
  TOrder = class
  private
    FAmount: Currency;
  public
    constructor Create(const AAmount: Currency);
    function Total: Currency;
  end;

implementation

constructor TOrder.Create(const AAmount: Currency);
begin
  inherited Create;
  FAmount := AAmount;
end;

function TOrder.Total: Currency;
begin
  Result := FAmount;
end;

end.
