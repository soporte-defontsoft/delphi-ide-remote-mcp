unit LinkLabel;

interface

uses
  System.Classes, FMX.StdCtrls;

procedure MakeLink(const ALabel: TLabel; const AOnClick: TNotifyEvent);

implementation

uses
  System.UITypes;

procedure MakeLink(const ALabel: TLabel; const AOnClick: TNotifyEvent);
begin
  // a FireMonkey TLabel is created with HitTest = False: clicks go through it
  ALabel.HitTest := True;
  ALabel.Cursor := crHandPoint;
  ALabel.OnClick := AOnClick;
end;

end.
