---
id: h01-fmx-layout-click
family: task
language: delphi
framework: fmx
teaches: a FireMonkey TLayout is created with HitTest = False - it is a container, not a click target, so its OnClick never fires until HitTest is on
judge: dcc64 37.0 Win64 + run (verify/DatasetFmxSpecTest: h01 before/after, asked of TControl.ObjectAtPoint, and the HitTest defaults read from the classes)
---

## user
In a Delphi FireMonkey (FMX) app I use a TLayout as a clickable card, but its OnClick never fires. Why, and how do I fix it? Write a procedure `MakeClickable(const ACard: TLayout; const AOnClick: TNotifyEvent)` that sets the card up.

## assistant
A `TLayout` is created with `HitTest = False`: FireMonkey treats it as a container, not as a click target. A click on it is never given to it - it goes to whatever lies under the layout - so its `OnClick` never runs. Turn `HitTest` on, in the Object Inspector or in code. (`TLabel` is created the same way; `TRectangle`, `TText`, `TImage` and the buttons start with `HitTest = True`.)

{{code:CardSetup.pas}}
