---
id: e07-pin-callers-round-half-up
family: landscape
language: delphi
framework: rtl
teaches: before changing a shared helper, pin what its callers already do with tests (DUnitX), then change it and run them again; RoundTo, like Round, rounds a half to the even digit and SimpleRoundTo away from zero
judge: dcc64 37.0 Win64 + DUnitX through delphi_test (verify/DatasetPinTest: 3/3); the premise measured once - on the given unit the two pinning tests pass and the new one fails (0.12); the rounding facts in verify/DatasetSpecTest (e07)
must_contain: SimpleRoundTo(AValue, -2)
---

## user
A price with half a cent must round up: `RoundPrice(0.125)` must give `0.13`, and today it gives `0.12`. Change `RoundPrice` in this Delphi unit.

{{code:given/PriceRounding.pas}}

## assistant
`RoundTo`, like `Round`, rounds a half to the even digit: `RoundTo(0.125, -2)` is `0.12`, and `Round(2.5)` is `2`. `SimpleRoundTo` rounds a half away from zero: `0.13`. But `RoundPrice` is shared - `LineTotal` and `WithTax` both depend on it - so before changing it, pin down what they already do with tests and run them on the current code: they pass. Then add a test for the new rule (on the current code it fails with `0.12`), make the change, and run them all again: the new rule must not move anything that already worked.

First the tests, with DUnitX:

{{code:answer/PriceRoundingTests.pas}}

Then the change:

{{code:answer/PriceRounding.pas}}
