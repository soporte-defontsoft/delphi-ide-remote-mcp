unit BadgeShape;

interface

uses
  FMX.Rectangle;

function NewBadge(const AOwner: TComponent): TRectangle;

implementation

function NewBadge(const AOwner: TComponent): TRectangle;
begin
  Result := TRectangle.Create(AOwner);
  Result.XRadius := 8;
  Result.YRadius := 8;
end;

end.
