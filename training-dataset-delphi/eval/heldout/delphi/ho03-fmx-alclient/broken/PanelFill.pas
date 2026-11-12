unit PanelFill;

interface

uses
  FMX.StdCtrls;

// The content panel takes all the room its parent has left
procedure FillParent(const APanel: TPanel);

implementation

procedure FillParent(const APanel: TPanel);
begin
  APanel.Align := alClient;
end;

end.
