unit PayButton;

interface

uses
  FMX.StdCtrls;

procedure ShowPay(const AButton: TButton);

implementation

procedure ShowPay(const AButton: TButton);
begin
  AButton.Text := 'Pay';
end;

end.
