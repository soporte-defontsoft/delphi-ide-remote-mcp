unit ToolbarSetup;

interface

uses
  FMX.StdCtrls;

procedure DockAtTop(const ABar: TToolBar);

implementation

uses
  FMX.Types;

procedure DockAtTop(const ABar: TToolBar);
begin
  // FireMonkey's alignment type is TAlignLayout (FMX.Types)
  ABar.Align := TAlignLayout.Top;
end;

end.
