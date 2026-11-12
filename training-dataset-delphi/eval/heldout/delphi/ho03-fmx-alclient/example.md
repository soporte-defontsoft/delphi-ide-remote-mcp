---
id: ho03-fmx-alclient
family: repair
language: delphi
framework: fmx
teaches: alClient is not a FireMonkey name - FireMonkey aligns with TAlignLayout.Client -, and TAlignLayout itself needs FMX.Types in the uses clause
judge: dcc64 37.0 Win64 - broken gives exactly dcc.txt (compiled from a short path); TAlignLayout.Client with FMX.StdCtrls alone measured too (E2003 on TAlignLayout); fixed compiles and runs (verify/HeldoutFmxSpecTest: ho03)
varies: r21-fmx-talign u06-fmx-card-in-code u10-fmx-setting-row
---

## user
This Delphi FireMonkey (FMX) unit does not compile:

{{text:dcc.txt}}

{{code:broken/PanelFill.pas}}

## assistant
`alClient` is not a FireMonkey name. FireMonkey aligns a control with the scoped type `TAlignLayout`, so the value is `TAlignLayout.Client`. Changing the name is not enough: `TAlignLayout` is declared in `FMX.Types`, and with only `FMX.StdCtrls` in the `uses` clause the compiler stops at `TAlignLayout` instead. `FMX.Types` goes in the implementation `uses` clause, since only the body needs it.

{{code:fixed/PanelFill.pas}}
