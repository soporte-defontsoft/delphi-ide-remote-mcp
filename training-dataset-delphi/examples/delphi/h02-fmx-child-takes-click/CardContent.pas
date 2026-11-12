unit CardContent;

interface

uses
  FMX.Controls;

// Lets the clicks on a card's decorative content reach the card itself
procedure LetClicksThrough(const ACard: TControl);

implementation

procedure LetClicksThrough(const ACard: TControl);
var
  Child: TControl;
begin
  for Child in ACard.Controls do
  begin
    Child.HitTest := False;
    // content nested in a layout would still take the click: go all the way down
    LetClicksThrough(Child);
  end;
end;

end.
