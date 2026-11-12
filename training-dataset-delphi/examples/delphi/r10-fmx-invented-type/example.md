---
id: r10-fmx-invented-type
family: repair
language: delphi
framework: fmx
teaches: TFillType does not exist in FireMonkey; the kind of a brush is TBrushKind (FMX.Graphics)
judge: dcc64 37.0 Win64 - broken gives exactly dcc.txt (compiled from a short path); fixed compiles and runs, and TBrushKind's unit and values are read through RTTI (verify/DatasetFmxSpecTest: r10)
---

## user
This Delphi FireMonkey (FMX) unit does not compile:

{{text:dcc.txt}}

{{code:broken/CardStyle.pas}}

## assistant
`TFillType` does not exist. The kind of a FireMonkey brush (`Fill`, `Stroke`) is `TBrushKind` - `None`, `Solid`, `Gradient`, `Bitmap`, `Resource` - declared in `FMX.Graphics`. The E2066 on the next line follows from the first error.

{{code:fixed/CardStyle.pas}}
