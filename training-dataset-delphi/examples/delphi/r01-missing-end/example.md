---
id: r01-missing-end
family: repair
language: delphi
framework: rtl
teaches: a missing end shifts every later end one level; read the compiler's line numbers as symptoms
judge: dcc64 37.0 Win64 - broken gives exactly dcc.txt (verify/DatasetBrokenProbe); fixed compiles and runs (verify/DatasetSpecTest: r01)
---

## user
This Delphi unit does not compile. The compiler says:

{{text:dcc.txt}}

{{code:broken/StockSum.pas}}

## assistant
Both messages come from one missing `end`. The `begin` after `for ... do` opens a block that is never closed, so every later `end` closes one level too early: the `end;` meant for the function closes the loop, and the unit's `end.` closes the function - the compiler wants a `;` there (line 20) and then runs out of file looking for the rest of the unit (line 22). Close the loop's block:

{{code:fixed/StockSum.pas}}
