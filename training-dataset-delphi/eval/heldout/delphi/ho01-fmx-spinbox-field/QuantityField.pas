unit QuantityField;

interface

uses
  FMX.Types,
  FMX.SpinBox;

// A spin box for a quantity from 1 to 99, starting at 1, aligned to the top of its parent
function AddQuantityField(const AParent: TFmxObject): TSpinBox;

implementation

function AddQuantityField(const AParent: TFmxObject): TSpinBox;
begin
  // TSpinBox lives in FMX.SpinBox; TAlignLayout and TFmxObject in FMX.Types
  Result := TSpinBox.Create(AParent);
  Result.Parent := AParent;
  Result.Align := TAlignLayout.Top;
  Result.Min := 1;
  Result.Max := 99;
  Result.Value := 1;
end;

end.
