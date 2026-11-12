unit StatusLabel;

interface

uses
  FMX.StdCtrls;

procedure ShowReady(const ALabel: TLabel);

implementation

procedure ShowReady(const ALabel: TLabel);
begin
  // FireMonkey text controls show their text in Text
  ALabel.Text := 'Ready';
end;

end.
