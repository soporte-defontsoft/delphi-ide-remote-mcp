unit CardBuilder;

interface

uses
  System.Classes, FMX.Objects;

function NewCard(const AOwner: TComponent; const ATitle: string): TRectangle;

implementation

uses
  System.UITypes, FMX.Types, FMX.Graphics;

function NewCard(const AOwner: TComponent; const ATitle: string): TRectangle;
var
  Title: TText;
begin
  Result := TRectangle.Create(AOwner);
  Result.XRadius := 8;
  Result.YRadius := 8;
  Result.Fill.Color := TAlphaColors.White;
  Result.Stroke.Kind := TBrushKind.Solid;
  Result.Stroke.Color := TAlphaColors.Lightgray;
  Title := TText.Create(Result);
  Title.Parent := Result;
  Title.Align := TAlignLayout.Client;
  Title.Text := ATitle;
  Title.HitTest := False; // the card, not its title, takes the click
end;

end.
