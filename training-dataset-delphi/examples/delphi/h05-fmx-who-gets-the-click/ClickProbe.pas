unit ClickProbe;

interface

uses
  System.Types, FMX.Types, FMX.Controls;

// The control that gets a click at AScreenPoint, among ARoot and its children
// (nil = none of them: the click goes to whatever is under ARoot)
function ControlAt(const ARoot: TControl; const AScreenPoint: TPointF): TFmxObject;

implementation

function ControlAt(const ARoot: TControl; const AScreenPoint: TPointF): TFmxObject;
var
  Target: IControl;
begin
  // the question the form itself asks on every click; ObjectAtPoint is
  // protected in TControl and public through IControl
  Target := (ARoot as IControl).ObjectAtPoint(AScreenPoint);
  if Target = nil then
    Result := nil
  else
    Result := Target.GetObject;
end;

end.
