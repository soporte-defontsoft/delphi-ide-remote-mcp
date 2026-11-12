---
id: ho11-tcomparer-needs-defaults
family: repair
language: delphi
framework: rtl
teaches: TComparer lives in System.Generics.Defaults, not in System.Generics.Collections (which has TArray and TList); CompareStr needs System.SysUtils - two missing units, and the error after each one is its echo
judge: dcc64 37.0 Win64 - broken gives exactly dcc.txt (compiled from a short path); fixed compiles and runs (verify/HeldoutSpecTest: ho11, and the unit of each type read from the type)
varies: r13-sort-needs-icomparer t07-sort-generic-list r07-tstringlist-needs-classes
---

## user
This Delphi unit does not compile:

{{text:dcc.txt}}

{{code:broken/NameOrder.pas}}

## assistant
Two units are missing. `TComparer<T>` is declared in `System.Generics.Defaults`: `System.Generics.Collections` has `TArray` and `TList<T>`, not the comparers. The E2029 on the same line is the compiler reading `TComparer<string>` as a comparison once the name is unknown. `CompareStr` is in `System.SysUtils`, and the E2089 after it is its echo. With the three units in the implementation `uses` clause the sort compiles: shortest names first, and names of the same length in alphabetical order.

{{code:fixed/NameOrder.pas}}
