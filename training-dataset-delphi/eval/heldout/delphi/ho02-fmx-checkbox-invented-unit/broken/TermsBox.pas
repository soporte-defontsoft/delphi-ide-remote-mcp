unit TermsBox;

interface

uses
  FMX.CheckBox;

// The "I accept the terms" box of a sign-up form: its caption, and not ticked
procedure SetupTermsBox(const ABox: TCheckBox);

implementation

procedure SetupTermsBox(const ABox: TCheckBox);
begin
  ABox.Caption := 'I accept the terms';
  ABox.Checked := False;
end;

end.
