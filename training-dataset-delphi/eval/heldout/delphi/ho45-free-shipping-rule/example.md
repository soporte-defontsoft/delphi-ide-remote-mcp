---
id: ho45-free-shipping-rule
family: every-place
language: delphi
framework: rtl
teaches: a bug in one copy of a rule is fixed where the rule should live; the total asks the shipping cost instead of repeating it
judge: dcc64 37.0 Win64 + run (verify/HeldoutSpecTest: ho45 - at 50 the invoice charges nothing, and the banner, the invoice and the checkout agree around the threshold); the comparison is written once (once)
once: >=
varies: e01-rule-in-one-place p04-rule-in-one-place
---

## user
A customer with exactly 50.00 in the cart saw "Free shipping!" and paid no shipping at checkout, but the invoice shows a shipping line of 4.95. Fix this Delphi unit.

{{code:given/CartTotals.pas}}

## assistant
The free-shipping rule is written three times, and the copy in `ShippingCost` drifted: it says "more than 50" where the other two say "50 or more". Fixing that one comparison would leave three copies waiting for the next change of the threshold. The rule goes in one place, `HasFreeShipping`, with the threshold and the fee as constants; the banner and the invoice ask it, and the checkout total is the subtotal plus `ShippingCost`, so the three cannot disagree again.

{{code:answer/CartTotals.pas}}
