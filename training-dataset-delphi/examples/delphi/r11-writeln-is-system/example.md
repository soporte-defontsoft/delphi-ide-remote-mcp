---
id: r11-writeln-is-system
family: repair
language: delphi
framework: rtl
teaches: WriteLn is a standard routine of System - never qualified with another unit, nothing to add to uses
judge: dcc64 37.0 Win64 - broken gives exactly dcc.txt (compiled from a short path); fixed compiles and runs (verify/DatasetSpecTest: r11)
---

## user
Delphi: why does this not compile? I even qualified `WriteLn` with its unit.

{{text:dcc.txt}}

{{code:broken/ConsoleReport.pas}}

## assistant
`WriteLn` is not in System.SysUtils: it is a standard routine of the `System` unit, which every unit uses implicitly. `System.SysUtils.WriteLn` names something that does not exist. Call it plain, `WriteLn(...)`, with nothing to add to the `uses` clause. It writes to the console of a console application.

{{code:fixed/ConsoleReport.pas}}
