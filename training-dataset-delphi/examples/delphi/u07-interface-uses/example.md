---
id: u07-interface-uses
family: task
language: delphi
framework: rtl
teaches: a type that appears in a declaration (a parameter, a result, a field) needs its unit in the INTERFACE uses; TRectF and TPointF live in System.Types, and TRectF already has CenterPoint
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: u07; the units of TRectF and TPointF read through RTTI)
---

## user
Write `CenterOf(const ARect: TRectF): TPointF` in Delphi: the centre point of a rectangle.

## assistant
`TRectF` and `TPointF` are declared in `System.Types`. Both appear in the declaration of the function, so the unit goes in the `uses` clause of the interface section: a unit named only in the implementation is not visible yet where the interface is compiled. And `TRectF` already knows its centre: `CenterPoint`.

{{code:Geometry.pas}}
