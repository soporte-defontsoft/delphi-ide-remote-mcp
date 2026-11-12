---
id: h04-fmx-invisible-overlay
family: task
language: delphi
framework: fmx
teaches: FireMonkey hit-tests a control's rectangle, not its pixels - Opacity 0, no fill or a transparent colour do not let clicks through; a Visible overlay keeps taking them
judge: dcc64 37.0 Win64 + run (verify/DatasetFmxSpecTest: h04, and the facts on no fill, Opacity 0, Visible and Enabled)
---

## user
In my Delphi FireMonkey form, a TRectangle covers the whole form to dim it while a long task runs. When the task ends I set its Opacity to 0, but now no button under it responds to clicks. Write `ShowBusy(const AOverlay: TRectangle; const ABusy: Boolean)` the right way.

## assistant
FireMonkey decides who gets a click by the control's rectangle, not by what it paints: `Opacity = 0`, no fill or a transparent colour change nothing. A `Visible` overlay on top keeps taking every click, so the buttons under it never get one. Hide it when it is not in use (`Visible := False`; a disabled control is skipped as well); while it shows, blocking the clicks is exactly its job. If an overlay must stay visible and still let the clicks through, set its `HitTest` to `False`.

{{code:BusyOverlay.pas}}
