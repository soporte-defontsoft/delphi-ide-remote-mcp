---
id: r19-fmx-tmemo-unit
family: repair
language: delphi
framework: fmx
teaches: a FireMonkey TMemo has a unit of its own, FMX.Memo - FMX.StdCtrls has TLabel and TButton but not the memo; a type used in a declaration needs its unit in the interface uses
judge: dcc64 37.0 Win64 - broken gives exactly dcc.txt (compiled from a short path); fixed compiles and runs (verify/DatasetFmxSpecTest: r19, and the unit of each control read from the class)
---

## user
This Delphi FireMonkey (FMX) unit does not compile:

{{text:dcc.txt}}

{{code:broken/MemoLog.pas}}

## assistant
`FMX.StdCtrls` has `TLabel` and `TButton`, but not the memo: a FireMonkey `TMemo` has a unit of its own, `FMX.Memo`. The other two errors follow from the first one - the implementation repeats the unknown type (E2005) and the line that uses it cannot be read (E2066). `TMemo` appears in the declaration of the procedure, so `FMX.Memo` goes in the interface `uses` clause.

{{code:fixed/MemoLog.pas}}
