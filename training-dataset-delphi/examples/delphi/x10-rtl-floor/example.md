---
id: x10-rtl-floor
family: landscape
language: delphi
framework: rtl
teaches: Floor (System.Math) rounds toward minus infinity; Trunc and div round toward zero - the same for positive values, wrong for negative ones
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: x10 - bands on both sides of zero; facts: Trunc, div and Floor on negative values); the answer calls Floor (must_contain)
must_contain: Floor(AValue / 5)
---

## user
Write `BandOf(const AValue: Double): Integer` in Delphi. Values are grouped in bands 5 wide: from 0 up to (not including) 5 is band 0, from 5 up to 10 is band 1, from -5 up to 0 is band -1, and so on.

## assistant
The band is the value divided by 5, rounded DOWN - toward minus infinity: that is `Floor`, in `System.Math`. `Trunc` rounds toward zero instead, and so does `div` on integers: the same for positive values, wrong for negative ones. `Trunc(-2.5 / 5)` is `0`, but `-2.5` belongs to band `-1`, which is `Floor(-0.5)`. Likewise `(-7) div 5` is `-1`, while `Floor(-7 / 5)` is `-2`.

{{code:ValueBands.pas}}
