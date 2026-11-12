unit ScoreBoard;

interface

type
  TScoreBoard = class
  private
    FTotal: Integer;
  public
    procedure Add(const APoints: Integer);
    property Total: Integer read FTotal;
  end;

implementation

procedure TScoreBoard.Add(const APoints: Integer);
begin
  if APoints > 0 then
    Inc(FTotal, APoints);
end;

end.
