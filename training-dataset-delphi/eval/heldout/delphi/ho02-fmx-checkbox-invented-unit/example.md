---
id: ho02-fmx-checkbox-invented-unit
family: repair
language: delphi
framework: fmx
teaches: there is no FMX.CheckBox - TCheckBox lives in FMX.StdCtrls -, and a FireMonkey check box has Text and IsChecked, not Caption and Checked; a fatal F2613 stops the compiler before it reaches the other two lines
judge: dcc64 37.0 Win64 - broken gives exactly dcc.txt (compiled from a short path); fixed compiles and runs (verify/HeldoutFmxSpecTest: ho02, and the unit read from the class)
varies: r12-fmx-invented-unit r03-fmx-has-no-caption r06-fmx-unit-of-tedit u10-fmx-setting-row
---

## user
This Delphi FireMonkey (FMX) unit does not compile:

{{text:dcc.txt}}

{{code:broken/TermsBox.pas}}

## assistant
There is no `FMX.CheckBox`: FireMonkey's `TCheckBox` is declared in `FMX.StdCtrls`, together with the button, the label and the switch. F2613 is fatal, so the compiler stopped there and never reached the two lines that fail next: a FireMonkey check box shows its caption in `Text` and is ticked through `IsChecked`; `Caption` and `Checked` are not its names. Fix all three before compiling again.

{{code:fixed/TermsBox.pas}}
