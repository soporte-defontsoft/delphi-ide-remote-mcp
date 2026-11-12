unit TermsBox;

interface

uses
  FMX.StdCtrls;

// The "I accept the terms" box of a sign-up form: its caption, and not ticked
procedure SetupTermsBox(const ABox: TCheckBox);

implementation

procedure SetupTermsBox(const ABox: TCheckBox);
begin
  // a FireMonkey check box shows Text and is ticked through IsChecked
  ABox.Text := 'I accept the terms';
  ABox.IsChecked := False;
end;

end.
