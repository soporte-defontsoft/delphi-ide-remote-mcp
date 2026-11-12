---
id: g01-never-swallow-errors
family: task
language: delphi
framework: rtl
teaches: an empty except silences every error, the ones nobody expected too; check the expected case (TryStrToInt) and report it
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: g01 - the sum of the numbers and the count of the rest)
---

## user
A colleague wrapped `StrToInt` in an empty `try..except` in this Delphi unit, so that bad lines do not stop the import. Fix it properly: bad lines must not stop the sum, but the caller has to know how many there were.

{{code:given/QuantityList.pas}}

## assistant
An empty `except` silences every error, the ones nobody expected too, and the caller never learns that lines were dropped. Check the case you do expect - a line that is not a number - with `TryStrToInt`, and report it: here as a count the caller receives. Any other error is still raised, where somebody will see it.

{{code:answer/QuantityList.pas}}
