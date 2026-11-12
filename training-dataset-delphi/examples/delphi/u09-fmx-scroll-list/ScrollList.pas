unit ScrollList;

interface

uses
  FMX.Layouts;

procedure FillList(const ABox: TVertScrollBox; const AItems: array of string);

implementation

uses
  FMX.Types, FMX.StdCtrls;

procedure FillList(const ABox: TVertScrollBox; const AItems: array of string);
var
  Item: string;
  Lbl: TLabel;
begin
  for Item in AItems do
  begin
    Lbl := TLabel.Create(ABox);
    Lbl.Text := Item;
    Lbl.Align := TAlignLayout.Top;
    Lbl.Parent := ABox; // a scroll box hands its children to its Content
  end;
end;

end.
