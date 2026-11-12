---
id: t02-fmx-label-text
family: task
language: delphi
framework: fmx
teaches: FireMonkey text controls show their text in the Text property
judge: dcc64 37.0 Win64, compile only (verify/DatasetCompileFmx)
---

## user
This is a Delphi FireMonkey (FMX) application. Write a procedure that makes a label show "Ready".

## assistant
In FireMonkey, `TLabel` (unit `FMX.StdCtrls`) shows its text in the `Text` property, like the other FireMonkey text controls (`TButton`, `TEdit`...).

{{code:StatusLabel.pas}}
