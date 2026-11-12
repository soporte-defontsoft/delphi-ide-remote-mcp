---
id: h03-fmx-label-click
family: task
language: delphi
framework: fmx
teaches: a FireMonkey TLabel is created with HitTest = False, so its OnClick does not fire until HitTest is on
judge: dcc64 37.0 Win64 + run (verify/DatasetFmxSpecTest: h03 before/after)
---

## user
Delphi FireMonkey: I want a TLabel that works like a link - clicking it opens the help. I assigned its OnClick, but nothing happens. Write `MakeLink(const ALabel: TLabel; const AOnClick: TNotifyEvent)`.

## assistant
A FireMonkey `TLabel` is created with `HitTest = False`: clicks go through it to whatever is underneath, so its `OnClick` never runs. Turn `HitTest` on; a hand cursor tells the user it is clickable.

{{code:LinkLabel.pas}}
