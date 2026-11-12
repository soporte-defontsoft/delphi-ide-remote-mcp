unit Shifts;

interface

type
  TShift = class
  private
    FStart: TDateTime;
  public
    constructor Create(const AStart: TDateTime);
    property Start: TDateTime read FStart;
  end;

implementation

constructor TShift.Create(const AStart: TDateTime);
begin
  inherited Create;
  FStart := AStart;
end;

end.
