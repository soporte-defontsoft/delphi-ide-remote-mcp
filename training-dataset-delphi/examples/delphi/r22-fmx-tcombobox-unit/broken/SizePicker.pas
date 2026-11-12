unit SizePicker;

interface

uses
  FMX.Controls;

procedure FillSizes(const ABox: TComboBox);

implementation

procedure FillSizes(const ABox: TComboBox);
begin
  ABox.Items.Clear;
  ABox.Items.Add('Small');
  ABox.Items.Add('Medium');
  ABox.Items.Add('Large');
end;

end.
