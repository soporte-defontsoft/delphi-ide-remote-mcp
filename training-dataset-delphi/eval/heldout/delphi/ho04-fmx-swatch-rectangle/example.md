---
id: ho04-fmx-swatch-rectangle
family: task
language: delphi
framework: fmx
teaches: a FireMonkey shape is a TRectangle (FMX.Objects); its fill and its border are brushes whose kind is a TBrushKind (FMX.Graphics), and a new rectangle has a solid border until Stroke.Kind is None
judge: dcc64 37.0 Win64 + run (verify/HeldoutFmxSpecTest: ho04, the defaults of a new TRectangle, and the unit of each type read through RTTI)
varies: r10-fmx-invented-type r12-fmx-invented-unit u06-fmx-card-in-code
---

## user
Delphi FireMonkey (FMX): write the unit `ColorSwatch` with `function AddSwatch(const AParent: TFmxObject; const AColor: TAlphaColor): TRectangle;`. It adds to `AParent` a 24 x 24 square filled with `AColor` and with no border.

## assistant
The square is a `TRectangle`, from `FMX.Objects`. A new rectangle has a solid fill and a solid border, so the border has to be switched off with `Stroke.Kind := TBrushKind.None`. `TBrushKind` is declared in `FMX.Graphics` and `TAlphaColor` in `System.UITypes`. The interface `uses` clause needs `System.UITypes`, `FMX.Types` and `FMX.Objects`, because the signature names their types; the implementation adds `FMX.Graphics`.

{{code:ColorSwatch.pas}}
