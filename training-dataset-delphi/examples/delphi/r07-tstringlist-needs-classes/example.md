---
id: r07-tstringlist-needs-classes
family: repair
language: delphi
framework: rtl
teaches: TStringList lives in System.Classes, not System.SysUtils; one missing unit breeds a cascade of E2066 - fix the first error
judge: dcc64 37.0 Win64 - broken gives exactly dcc.txt (compiled from a short path); fixed compiles and runs (verify/DatasetSpecTest: r07, and the unit of each class read through RTTI)
---

## user
This Delphi unit does not compile:

{{text:dcc.txt}}

{{code:broken/WordList.pas}}

## assistant
Only the first error matters: `TStringList` is declared in `System.Classes`, and the unit only uses `System.SysUtils`. Without the type, every line that touches `Words` is noise to the compiler - that is where the seven E2066 come from, and they go away with the first one. Add `System.Classes` to the implementation `uses` clause (only the implementation needs the type).

{{code:fixed/WordList.pas}}
