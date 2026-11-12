---
id: ho05-fmx-badge-takes-click
family: task
language: delphi
framework: fmx
teaches: in FireMonkey the control on top takes the click when its HitTest is on - a TImage has it on by default -, so a decoration over a control turns HitTest off
judge: dcc64 37.0 Win64 + run (verify/HeldoutFmxSpecTest: ho05 - FireMonkey's own hit test before and after, with the badge still in its place)
varies: h02-fmx-child-takes-click h04-fmx-invisible-overlay h05-fmx-who-gets-the-click
---

## user
In this Delphi FireMonkey (FMX) unit, a click on the corner of the button where the badge sits does nothing: the button never gets it. Fix it.

{{code:given/AvatarBadge.pas}}

## assistant
The badge is a `TImage`, and an image takes clicks: its `HitTest` is `True` by default. It sits on top of the button's corner, so FireMonkey gives the click there to the badge, and the button never sees it. The badge is only a picture, so it lets the clicks through: `ABadge.HitTest := False`. It is drawn exactly as before; only the clicks change.

{{code:answer/AvatarBadge.pas}}
