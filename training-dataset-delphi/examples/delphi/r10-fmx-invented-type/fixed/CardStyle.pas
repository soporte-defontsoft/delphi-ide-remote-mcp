unit CardStyle;

interface

uses
  FMX.Objects;

procedure MakeOutline(const ACard: TRectangle);

implementation

uses
  FMX.Graphics;

procedure MakeOutline(const ACard: TRectangle);
begin
  // the kind of a FireMonkey brush is TBrushKind, in FMX.Graphics
  ACard.Fill.Kind := TBrushKind.None;
  ACard.Stroke.Kind := TBrushKind.Solid;
  ACard.Stroke.Thickness := 2;
end;

end.
