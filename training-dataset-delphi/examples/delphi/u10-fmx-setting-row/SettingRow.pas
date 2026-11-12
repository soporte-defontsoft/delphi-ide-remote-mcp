unit SettingRow;

interface

uses
  FMX.Types, FMX.StdCtrls;

// A row with the caption on the left and a switch on the right, added to AParent.
// It returns the switch, so that the caller can read IsChecked and assign OnSwitch.
function AddSettingRow(const AParent: TFmxObject; const ACaption: string): TSwitch;

implementation

uses
  FMX.Layouts;

function AddSettingRow(const AParent: TFmxObject; const ACaption: string): TSwitch;
var
  Row: TLayout;
  Caption: TLabel;
begin
  Row := TLayout.Create(AParent);
  Row.Align := TAlignLayout.Top;
  Row.Height := 44;
  Row.Parent := AParent;

  Result := TSwitch.Create(Row);
  Result.Align := TAlignLayout.Right;
  Result.Parent := Row;

  Caption := TLabel.Create(Row);
  Caption.Align := TAlignLayout.Client;
  Caption.Text := ACaption;
  Caption.Parent := Row;
end;

end.
