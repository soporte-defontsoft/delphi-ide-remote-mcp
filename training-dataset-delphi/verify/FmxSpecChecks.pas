unit FmxSpecChecks;

// What the FireMonkey judges share: which control FireMonkey gives a click to, and how such a judge leaves.

interface

uses
  FMX.Types,
  FMX.Controls;

// Which object gets a click at (X, Y), asked of FireMonkey
function Hit(const ARoot: TControl; const X, Y: Single): TFmxObject;
// Leaves the judge with its verdict as the exit code, without FireMonkey's unit finalization (see the body)
procedure LeaveJudge(const AFailures: Integer);

implementation

uses
  System.Types,
  Winapi.Windows;

function Hit(const ARoot: TControl; const X, Y: Single): TFmxObject;
var
  C: IControl;
begin
  // ObjectAtPoint is protected in TControl and public through IControl, as the form uses it
  C := (ARoot as IControl).ObjectAtPoint(PointF(X, Y));
  if C = nil then
    Result := nil
  else
    Result := C.GetObject;
end;

procedure LeaveJudge(const AFailures: Integer);
begin
  // The verdict is complete here. The controls of a judge live without an application, a form or a
  // window, and FireMonkey's own unit finalization then ends now and then in an access violation
  // inside ntdll (Runtime error 217). Measured 12-nov, out of the examples' code (after the last
  // check): 0 of 8 runs with the v5 controls, up to 2 of 4 with TToolBar, TComboBox, TSwitch and
  // TTabControl as well; FMX.Forms in the uses does not change it; the cause is NOT measured.
  // So the judge leaves here, after flushing its output, without running that finalization.
  Flush(Output);
  ExitProcess(Cardinal(AFailures));
end;

end.
