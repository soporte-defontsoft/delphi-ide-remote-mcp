unit NameField;

interface

uses
  FMX.Editors;

procedure ClearName(const AEdit: TEdit);

implementation

procedure ClearName(const AEdit: TEdit);
begin
  AEdit.Text := '';
end;

end.
