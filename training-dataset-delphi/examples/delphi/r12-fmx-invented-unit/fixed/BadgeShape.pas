unit BadgeShape;

interface

uses
  System.Classes, FMX.Objects;

function NewBadge(const AOwner: TComponent): TRectangle;

implementation

function NewBadge(const AOwner: TComponent): TRectangle;
begin
  // TRectangle (and TCircle, TText, TImage...) lives in FMX.Objects;
  // TComponent, the owner, in System.Classes
  Result := TRectangle.Create(AOwner);
  Result.XRadius := 8;
  Result.YRadius := 8;
end;

end.
