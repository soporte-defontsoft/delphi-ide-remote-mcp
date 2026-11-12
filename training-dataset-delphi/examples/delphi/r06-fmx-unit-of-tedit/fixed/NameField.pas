unit NameField;

interface

uses
  FMX.Edit;

procedure ClearName(const AEdit: TEdit);

implementation

procedure ClearName(const AEdit: TEdit);
begin
  AEdit.Text := '';
end;

end.
