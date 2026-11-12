---
id: r12-fmx-invented-unit
family: repair
language: delphi
framework: fmx
teaches: F2613 - FMX.Rectangle does not exist; TRectangle lives in FMX.Objects, and TComponent in System.Classes
judge: dcc64 37.0 Win64 - broken gives exactly dcc.txt (compiled from a short path); fixed compiles and runs, and the unit of each class is read through RTTI (verify/DatasetFmxSpecTest: r12)
---

## user
Delphi FireMonkey: the compiler cannot find the unit.

{{text:dcc.txt}}

{{code:broken/BadgeShape.pas}}

## assistant
There is no `FMX.Rectangle` unit. `TRectangle` lives in `FMX.Objects`, with the other shapes (`TCircle`, `TEllipse`...), `TText` and `TImage`. The owner type `TComponent`, used in the interface, comes from `System.Classes`, which the unit has to use as well.

{{code:fixed/BadgeShape.pas}}
