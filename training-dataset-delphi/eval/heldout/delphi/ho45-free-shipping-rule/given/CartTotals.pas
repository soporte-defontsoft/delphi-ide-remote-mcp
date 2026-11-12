unit CartTotals;

interface

// What the cart page shows under the subtotal
function CartBanner(const ASubtotal: Currency): string;
// The shipping line of the invoice
function ShippingCost(const ASubtotal: Currency): Currency;
// What the checkout charges
function CheckoutTotal(const ASubtotal: Currency): Currency;

implementation

uses
  System.SysUtils;

function CartBanner(const ASubtotal: Currency): string;
begin
  if ASubtotal >= 50 then
    Result := 'Free shipping!'
  else
    Result := Format('Add %.2f more for free shipping', [50 - ASubtotal], TFormatSettings.Invariant);
end;

function ShippingCost(const ASubtotal: Currency): Currency;
begin
  if ASubtotal > 50 then
    Result := 0
  else
    Result := 4.95;
end;

function CheckoutTotal(const ASubtotal: Currency): Currency;
begin
  if ASubtotal >= 50 then
    Result := ASubtotal
  else
    Result := ASubtotal + 4.95;
end;

end.
