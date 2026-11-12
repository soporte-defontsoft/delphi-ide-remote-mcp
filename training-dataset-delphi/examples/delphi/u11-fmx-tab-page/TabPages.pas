unit TabPages;

interface

uses
  FMX.TabControl;

function AddPage(const ATabs: TTabControl; const ATitle: string): TTabItem;

implementation

function AddPage(const ATabs: TTabControl; const ATitle: string): TTabItem;
begin
  // TTabControl and TTabItem live in FMX.TabControl; Add creates the page inside the control
  Result := ATabs.Add;
  Result.Text := ATitle;
end;

end.
