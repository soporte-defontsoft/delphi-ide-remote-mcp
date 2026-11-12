---
id: r13-sort-needs-icomparer
family: repair
language: delphi
framework: rtl
teaches: E2250 - TList<T>.Sort takes an IComparer<T>, not a function; wrap it with TComparer<T>.Construct (System.Generics.Defaults)
judge: dcc64 37.0 Win64 - broken gives exactly dcc.txt (compiled from a short path); fixed compiles and runs (verify/DatasetSpecTest: r13)
---

## system
You write Delphi (RAD Studio 13) code.

## user
Sorting my list of records does not compile:

{{text:dcc.txt}}

{{code:broken/TaskOrder.pas}}

## assistant
`TList<T>.Sort` has no overload that takes a function: it takes an `IComparer<T>` (or nothing, for the default comparer). Wrap the anonymous function with `TComparer<T>.Construct`, from `System.Generics.Defaults`, and pass that.

{{code:fixed/TaskOrder.pas}}
