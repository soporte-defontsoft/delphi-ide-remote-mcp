unit AvatarBadge;

interface

uses
  FMX.Objects,
  FMX.StdCtrls;

// Puts the badge image over the top-right corner of the button
procedure PlaceBadge(const AButton: TButton; const ABadge: TImage);

implementation

procedure PlaceBadge(const AButton: TButton; const ABadge: TImage);
begin
  ABadge.Parent := AButton.Parent;
  ABadge.SetBounds(AButton.Position.X + AButton.Width - 12, AButton.Position.Y - 4, 16, 16);
  ABadge.BringToFront;
  // a TImage takes clicks (HitTest is True by default): the badge on top would keep the ones meant for the
  // button below it
  ABadge.HitTest := False;
end;

end.
