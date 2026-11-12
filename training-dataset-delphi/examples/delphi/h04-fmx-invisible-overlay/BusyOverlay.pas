unit BusyOverlay;

interface

uses
  FMX.Objects;

procedure ShowBusy(const AOverlay: TRectangle; const ABusy: Boolean);

implementation

procedure ShowBusy(const AOverlay: TRectangle; const ABusy: Boolean);
begin
  // FireMonkey hit-tests the control's rectangle, not its pixels: a transparent
  // overlay that stays Visible keeps taking every click. Hide it when idle;
  // while it shows, blocking the clicks is what it is for.
  AOverlay.Visible := ABusy;
end;

end.
