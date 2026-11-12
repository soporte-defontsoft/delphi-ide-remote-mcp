unit PanelFill;

interface

uses
  FMX.StdCtrls;

// The content panel takes all the room its parent has left
procedure FillParent(const APanel: TPanel);

implementation

uses
  FMX.Types;

procedure FillParent(const APanel: TPanel);
begin
  // alClient is not a FireMonkey name: FireMonkey aligns with TAlignLayout, declared in FMX.Types
  APanel.Align := TAlignLayout.Client;
end;

end.
