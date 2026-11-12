---
id: r06-fmx-unit-of-tedit
family: repair
language: delphi
framework: fmx
teaches: F2613 - FMX.Editors does not exist; a FireMonkey TEdit lives in FMX.Edit (the unit of each control, asked of the class)
judge: dcc64 37.0 Win64 - broken gives exactly dcc.txt (verify/DatasetBrokenProbe); fixed compiles and runs, and the unit of each control is read from the class (verify/DatasetFmxSpecTest: r06)
---

## user
This Delphi FireMonkey (FMX) unit does not compile:

{{text:dcc.txt}}

{{code:broken/NameField.pas}}

## assistant
There is no `FMX.Editors` unit: a FireMonkey `TEdit` lives in `FMX.Edit`. The other common controls: `TLabel` and `TButton` in `FMX.StdCtrls`, `TListBox` and `TComboBox` in `FMX.ListBox`, `TMemo` in `FMX.Memo`.

{{code:fixed/NameField.pas}}
