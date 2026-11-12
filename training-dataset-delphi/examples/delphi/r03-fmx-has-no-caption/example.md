---
id: r03-fmx-has-no-caption
family: repair
language: delphi
framework: fmx
teaches: a FireMonkey TButton has no Caption; its text is Text
judge: dcc64 37.0 Win64 - broken gives exactly dcc.txt (verify/DatasetBrokenProbe); fixed compiles and runs (verify/DatasetFmxSpecTest: r03)
---

## user
This is a Delphi FireMonkey (FMX) unit and it does not compile:

{{text:dcc.txt}}

{{code:broken/PayButton.pas}}

## assistant
A FireMonkey `TButton` has no `Caption` property: its text is `Text`, as in every FireMonkey text control.

{{code:fixed/PayButton.pas}}
