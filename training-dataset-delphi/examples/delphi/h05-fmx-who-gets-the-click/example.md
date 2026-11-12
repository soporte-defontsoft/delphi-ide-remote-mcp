---
id: h05-fmx-who-gets-the-click
family: task
language: delphi
framework: fmx
teaches: how FireMonkey picks the control that gets a click (Visible and Enabled, children first from the top, HitTest, the rectangle) and how to ask it with IControl.ObjectAtPoint
judge: dcc64 37.0 Win64 + run (verify/DatasetFmxSpecTest: h05, and the 13 hit-testing facts)
---

## system
You write Delphi (RAD Studio 13) FireMonkey code.

## user
An OnClick in my FireMonkey app does not fire and I cannot see why. Write a helper `ControlAt(const ARoot: TControl; const AScreenPoint: TPointF): TFmxObject` that tells me which control really gets a click at a point, so I can log it.

## assistant
Ask FireMonkey the same question the form asks on every click: `ObjectAtPoint`. It is protected in `TControl`, but public through the `IControl` interface that every control implements. The rule it follows:

1. A control that is not `Visible` or not enabled is skipped, children included.
2. The children are asked first, from the top-most one down; the first that answers gets the click.
3. Only when no child answers does the control itself get it - if the point is inside its rectangle and its `HitTest` is `True`.
4. The rectangle counts, not the painted pixels: a transparent control on top still takes the click.

`nil` means none of them takes it: the click goes to whatever lies under `ARoot`. The point is in screen coordinates.

{{code:ClickProbe.pas}}
