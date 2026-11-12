---
id: r21-fmx-talign
family: repair
language: delphi
framework: fmx
teaches: FireMonkey has no TAlign - its alignment type is TAlignLayout (FMX.Types); with FMX.Types in the uses, only the name is wrong
judge: dcc64 37.0 Win64 - broken gives exactly dcc.txt (compiled from a short path, FMX.Types in its uses); fixed compiles and runs (verify/DatasetFmxSpecTest: r21; TAlignLayout read through RTTI)
---

## user
This Delphi FireMonkey (FMX) unit does not compile:

{{text:dcc.txt}}

{{code:broken/ToolbarSetup.pas}}

## assistant
FireMonkey has no `TAlign`. Its alignment type is `TAlignLayout`, declared in `FMX.Types` - the unit is already in the `uses` clause, so only the name is wrong: `ABar.Align := TAlignLayout.Top`. The other values go the same way (`TAlignLayout.Bottom`, `Right`, `Client`...).

{{code:fixed/ToolbarSetup.pas}}
