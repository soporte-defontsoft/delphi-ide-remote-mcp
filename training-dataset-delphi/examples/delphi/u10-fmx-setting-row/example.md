---
id: u10-fmx-setting-row
family: task
language: delphi
framework: fmx
teaches: the unit of each FireMonkey piece - TLayout in FMX.Layouts, TSwitch and TLabel in FMX.StdCtrls, TAlignLayout and TFmxObject in FMX.Types; a builder returns the control its caller needs
judge: dcc64 37.0 Win64 + run (verify/DatasetFmxSpecTest: u10 - one row in the parent, the switch on the right, the caption; the units and TSwitch's IsChecked/OnSwitch read from the classes)
---

## user
In a Delphi FireMonkey app, write `AddSettingRow(const AParent: TFmxObject; const ACaption: string): TSwitch`: it adds a row to `AParent` with the caption on the left and an on/off switch on the right, and returns the switch.

## assistant
Each piece comes from its own unit: `TLayout` from `FMX.Layouts`, `TSwitch` and `TLabel` from `FMX.StdCtrls`, `TAlignLayout` and `TFmxObject` from `FMX.Types`. `TFmxObject` and `TSwitch` appear in the declaration, so their units go in the interface `uses`; `FMX.Layouts` only in the implementation. The row aligns to the top, the switch to the right, and the label takes the rest (`Client`). The parent owns the row and the row owns the rest, so everything is freed with the parent. The function returns the switch, so that the caller can read `IsChecked` and assign `OnSwitch`.

{{code:SettingRow.pas}}
