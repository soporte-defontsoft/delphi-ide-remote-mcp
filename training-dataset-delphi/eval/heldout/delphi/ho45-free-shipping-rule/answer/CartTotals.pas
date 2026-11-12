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

const
  FreeShippingFrom = 50;
  ShippingFee = 4.95;

// The one place of the rule: from FreeShippingFrom on, shipping is free
function HasFreeShipping(const ASubtotal: Currency): Boolean;
begin
  Result := ASubtotal >= FreeShippingFrom;
end;

function CartBanner(const ASubtotal: Currency): string;
begin
  if HasFreeShipping(ASubtotal) then
    Result := 'Free shipping!'
  else
    Result := Format('Add %.2f more for free shipping', [FreeShippingFrom - ASubtotal], TFormatSettings.Invariant);
end;

function ShippingCost(const ASubtotal: Currency): Currency;
begin
  if HasFreeShipping(ASubtotal) then
    Result := 0
  else
    Result := ShippingFee;
end;

function CheckoutTotal(const ASubtotal: Currency): Currency;
begin
  Result := ASubtotal + ShippingCost(ASubtotal);
end;

end.
