unit CardSetup;

interface

uses
  System.Classes, FMX.Layouts;

procedure MakeClickable(const ACard: TLayout; const AOnClick: TNotifyEvent);

implementation

procedure MakeClickable(const ACard: TLayout; const AOnClick: TNotifyEvent);
begin
  // a TLayout is created with HitTest = False: a container, not a click target
  ACard.HitTest := True;
  ACard.OnClick := AOnClick;
end;

end.
