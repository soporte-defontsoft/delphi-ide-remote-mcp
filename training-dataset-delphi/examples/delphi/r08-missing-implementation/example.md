---
id: r08-missing-implementation
family: repair
language: delphi
framework: rtl
teaches: a unit without the implementation keyword - the first error (E2004 Identifier redeclared) misleads; the cause is the line that says 'IMPLEMENTATION' expected
judge: dcc64 37.0 Win64 - broken gives exactly dcc.txt (compiled from a short path); fixed compiles and runs (verify/DatasetSpecTest: r08)
---

## user
I get these errors and I do not understand the first one - `Add` is declared only once:

{{text:dcc.txt}}

{{code:broken/ScoreBoard.pas}}

## assistant
The unit has no `implementation` section: the method body is written straight after the interface. There, `procedure TScoreBoard.Add` reads as a second declaration (E2004, redeclared), so its body sees neither the parameter nor the field (E2003), and the class method is left without a body (E2065). The line that names the cause is line 20: `'IMPLEMENTATION' expected`. Here the first error is only a symptom: when a unit reports "redeclared" and "unsatisfied forward" for the same method, look for the missing `implementation`.

{{code:fixed/ScoreBoard.pas}}
