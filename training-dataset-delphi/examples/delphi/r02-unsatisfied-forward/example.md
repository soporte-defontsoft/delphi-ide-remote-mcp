---
id: r02-unsatisfied-forward
family: repair
language: delphi
framework: rtl
teaches: E2065 - a method declared in the class has no body in the implementation
judge: dcc64 37.0 Win64 - broken gives exactly dcc.txt (verify/DatasetBrokenProbe); fixed compiles and runs (verify/DatasetSpecTest: r02)
---

## system
You write Delphi (RAD Studio 13) code.

## user
Fix this unit. The compiler stops with:

{{text:dcc.txt}}

{{code:broken/Counters.pas}}

## assistant
E2065 means a routine was declared but never implemented: `TCounter.Reset` is in the class declaration, and the implementation section has no `procedure TCounter.Reset`. Every method declared in a class needs its body, unless it is `abstract`. Here `Reset` sets the counter back to zero:

{{code:fixed/Counters.pas}}
