---
id: h02-fmx-child-takes-click
family: task
language: delphi
framework: fmx
teaches: FireMonkey gives a click to the top-most child under the point that has HitTest = True; decorative content (TText, TImage) takes the card's clicks until its HitTest is off, nested content included
judge: dcc64 37.0 Win64 + run (verify/DatasetFmxSpecTest: h02 - before, the title and the nested icon take the click; after, the card gets it)
---

## system
You write Delphi (RAD Studio 13) FireMonkey code.

## user
My card is a TRectangle with OnClick. Inside it there is a TText with the title and a TLayout holding a TImage icon. A click on the empty part of the card fires OnClick, but a click on the title or on the icon does nothing. Write a procedure `LetClicksThrough(const ACard: TControl)` that fixes it.

## assistant
FireMonkey asks the children first, from the top-most one down: the first child under the point with `HitTest = True` gets the click, and the card never hears of it. `TText` and `TImage` are created with `HitTest = True`, so they take the click. The icon does too, even inside a layout whose own `HitTest` is off, because the layout passes the question on to its children. Content that is only decoration should not be a click target: switch its `HitTest` off all the way down. A child that must keep its own click - a button inside the card - would be left out.

{{code:CardContent.pas}}
