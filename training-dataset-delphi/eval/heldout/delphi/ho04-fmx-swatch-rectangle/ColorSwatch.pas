unit ColorSwatch;

interface

uses
  System.UITypes,
  FMX.Types,
  FMX.Objects;

// A 24 x 24 square filled with AColor, with no border, added to AParent
function AddSwatch(const AParent: TFmxObject; const AColor: TAlphaColor): TRectangle;

implementation

uses
  FMX.Graphics;

function AddSwatch(const AParent: TFmxObject; const AColor: TAlphaColor): TRectangle;
begin
  // TRectangle lives in FMX.Objects; the kinds of a brush (TBrushKind) in FMX.Graphics
  Result := TRectangle.Create(AParent);
  Result.Parent := AParent;
  Result.Width := 24;
  Result.Height := 24;
  Result.Fill.Kind := TBrushKind.Solid;
  Result.Fill.Color := AColor;
  Result.Stroke.Kind := TBrushKind.None;
end;

end.
