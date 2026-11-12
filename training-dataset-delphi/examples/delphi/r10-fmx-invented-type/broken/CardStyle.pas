unit CardStyle;

interface

uses
  FMX.Objects;

procedure MakeOutline(const ACard: TRectangle);

implementation

procedure MakeOutline(const ACard: TRectangle);
begin
  ACard.Fill.Kind := TFillType.None;
  ACard.Stroke.Kind := TFillType.Solid;
  ACard.Stroke.Thickness := 2;
end;

end.
