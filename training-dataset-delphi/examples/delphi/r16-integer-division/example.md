---
id: r16-integer-division
family: repair
language: delphi
framework: rtl
teaches: E2010 - "/" always gives a floating-point result; "div" is the integer division
judge: dcc64 37.0 Win64 - broken gives exactly dcc.txt (compiled from a short path); fixed compiles and runs (verify/DatasetSpecTest: r16)
---

## user
Delphi: why does this not compile?

{{text:dcc.txt}}

{{code:broken/DailyAverage.pas}}

## assistant
In Delphi `/` always gives a floating-point result, even between two integers, and a floating-point value cannot be assigned to an `Integer`. For a whole number of units per day use `div`, the integer division, which truncates (`10 div 4` is 2). If you need the decimals, make the result a `Double` instead.

{{code:fixed/DailyAverage.pas}}
