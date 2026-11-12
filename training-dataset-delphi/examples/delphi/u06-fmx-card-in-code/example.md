---
id: u06-fmx-card-in-code
family: task
language: delphi
framework: fmx
teaches: the unit of each FireMonkey piece - TRectangle/TText in FMX.Objects, TBrushKind in FMX.Graphics, TAlignLayout in FMX.Types, TAlphaColors in System.UITypes, TComponent in System.Classes
judge: dcc64 37.0 Win64 + run (verify/DatasetFmxSpecTest: u06 - the title, and a click on it reaching the card; units read through RTTI)
---

## user
In a Delphi FireMonkey app, build a card in code: a rounded white rectangle with a light grey border, and a title text that fills it. Write `NewCard(const AOwner: TComponent; const ATitle: string): TRectangle`.

## assistant
Each piece comes from its own unit: `TRectangle` and `TText` from `FMX.Objects`, `TBrushKind` from `FMX.Graphics`, `TAlignLayout` from `FMX.Types`, the `TAlphaColors` constants from `System.UITypes`, and `TComponent` from `System.Classes`. The title gets `HitTest := False`, so a click on it reaches the card.

{{code:CardBuilder.pas}}
