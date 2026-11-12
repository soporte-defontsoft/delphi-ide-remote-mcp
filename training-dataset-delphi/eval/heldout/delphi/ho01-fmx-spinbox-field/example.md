---
id: ho01-fmx-spinbox-field
family: task
language: delphi
framework: fmx
teaches: TSpinBox lives in FMX.SpinBox, a unit of its own; TAlignLayout and TFmxObject live in FMX.Types
judge: dcc64 37.0 Win64 + run (verify/HeldoutFmxSpecTest: ho01, and the unit read from the class)
varies: r22-fmx-tcombobox-unit r19-fmx-tmemo-unit u10-fmx-setting-row r21-fmx-talign
---

## user
Delphi FireMonkey (FMX): write the unit `QuantityField` with `function AddQuantityField(const AParent: TFmxObject): TSpinBox;`. It adds to `AParent` a spin box for a quantity from 1 to 99, starting at 1, aligned to the top of its parent.

## assistant
`TSpinBox` lives in `FMX.SpinBox`, a unit of its own - not `FMX.StdCtrls`, not `FMX.Edit`. The type of `Align` is `TAlignLayout`, declared in `FMX.Types` together with `TFmxObject`. Both units go in the interface `uses` clause, since the signature names their types. The parent owns the box, so the box is freed with it; `Min` and `Max` are set before `Value`, which a spin box keeps inside its range.

{{code:QuantityField.pas}}
