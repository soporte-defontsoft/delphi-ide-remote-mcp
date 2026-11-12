---
id: ho23-round-half-up
family: task
language: delphi
framework: rtl
teaches: Round rounds a half to the even number (Round(2.5) = 2); SimpleRoundTo rounds it away from zero
judge: dcc64 37.0 Win64 + run (verify/HeldoutSpecTest: ho23, and the halves of Round measured)
varies: e07-pin-callers-round-half-up x10-rtl-floor
---

## user
Write the Delphi unit `PackCount` with `function WholeUnits(const AQuantity: Double): Integer;`: a quantity of a product (never negative) rounded to whole units, halves up - 2.4 gives 2, 2.5 gives 3 and 3.5 gives 4.

## assistant
`Round` does not round halves up: it rounds a half to the even number, so `Round(2.5)` is 2 and `Round(3.5)` is 4. `SimpleRoundTo` (`System.Math`) rounds a half away from zero, which is "halves up" for a quantity that is never negative. With 0 digits it gives a whole number, and `Trunc` turns it into an `Integer`.

{{code:PackCount.pas}}
