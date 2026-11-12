unit SizePicker;

interface

uses
  FMX.ListBox;

procedure FillSizes(const ABox: TComboBox);

implementation

procedure FillSizes(const ABox: TComboBox);
begin
  // TComboBox and TListBox live in FMX.ListBox; FMX.Controls has TControl, the base class
  ABox.Items.Clear;
  ABox.Items.Add('Small');
  ABox.Items.Add('Medium');
  ABox.Items.Add('Large');
end;

end.
