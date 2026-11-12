---
id: u09-fmx-scroll-list
family: task
language: delphi
framework: fmx
teaches: a FireMonkey TVertScrollBox (FMX.Layouts) takes its children into its Content - set Parent to the box; TLabel in FMX.StdCtrls, TAlignLayout in FMX.Types
judge: dcc64 37.0 Win64 + run (verify/DatasetFmxSpecTest: u09 - three labels in the box's Content; the units read from the class)
---

## user
In a Delphi FireMonkey app, write `FillList(const ABox: TVertScrollBox; const AItems: array of string)`: one label per item, stacked from the top, that scroll when there are more than fit.

## assistant
`TVertScrollBox` lives in `FMX.Layouts`, `TLabel` in `FMX.StdCtrls` and `TAlignLayout` in `FMX.Types`. Each label is created with the box as its owner (it is freed with the box), gets `Align := TAlignLayout.Top` so that they stack, and `Parent := ABox`: the scroll box hands its children to its `Content`, the part that scrolls. The box appears in the declaration, so `FMX.Layouts` goes in the interface `uses`; the other two only in the implementation.

{{code:ScrollList.pas}}
