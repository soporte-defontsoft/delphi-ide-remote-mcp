---
id: r22-fmx-tcombobox-unit
family: repair
language: delphi
framework: fmx
teaches: TComboBox and TListBox live in FMX.ListBox; FMX.Controls declares TControl, the base class, not the controls; one missing type breeds E2005 and a cascade of E2066
judge: dcc64 37.0 Win64 - broken gives exactly dcc.txt (compiled from a short path); fixed compiles and runs (verify/DatasetFmxSpecTest: r22, and the unit of each class read from the class)
---

## user
This Delphi FireMonkey (FMX) unit does not compile:

{{text:dcc.txt}}

{{code:broken/SizePicker.pas}}

## assistant
`FMX.Controls` declares `TControl`, the base class of the controls - not the controls themselves. `TComboBox` lives in `FMX.ListBox`, together with `TListBox`. The other five errors follow from the first one: the implementation repeats the unknown type (E2005), and every line that uses `ABox` cannot be read (E2066). `TComboBox` appears in the declaration of the procedure, so `FMX.ListBox` goes in the interface `uses` clause.

{{code:fixed/SizePicker.pas}}
