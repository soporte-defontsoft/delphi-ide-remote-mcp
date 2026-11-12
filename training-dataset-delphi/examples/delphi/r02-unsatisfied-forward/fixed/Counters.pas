unit Counters;

interface

type
  TCounter = class
  private
    FValue: Integer;
  public
    procedure Increment;
    procedure Reset;
    property Value: Integer read FValue;
  end;

implementation

procedure TCounter.Increment;
begin
  Inc(FValue);
end;

procedure TCounter.Reset;
begin
  FValue := 0;
end;

end.
