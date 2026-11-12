---
id: t12-currency-for-money
family: task
language: delphi
framework: rtl
teaches: money goes in Currency (fixed-point, four decimals), not Double - with Double 0.1 + 0.2 is not 0.3
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: t12, and the Double fact)
---

## user
In Delphi, add up a list of prices. The total must be exact to the cent: 0.10 + 0.20 has to give 0.30. Write `TotalOf(const APrices: array of Currency): Currency`.

## assistant
Use `Currency` for money. It is a fixed-point type with four decimals, so `0.10 + 0.20` is exactly `0.30`. `Double` is binary floating point: it cannot hold 0.1 exactly, and `0.1 + 0.2 = 0.3` is False with it.

{{code:Money.pas}}
