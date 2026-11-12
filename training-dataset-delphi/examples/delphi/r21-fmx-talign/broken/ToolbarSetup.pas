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
  ABar.Align := TAlign.Top;
end;

end.
