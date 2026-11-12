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

function IsWeekend(const ADate: TDateTime): Boolean;

implementation

uses
  System.DateUtils;

constructor TShift.Create(const AStart: TDateTime);
begin
  inherited Create;
  FStart := AStart;
end;

function IsWeekend(const ADate: TDateTime): Boolean;
begin
  // DayOfTheWeek is ISO 8601: Monday = 1 ... Sunday = 7
  Result := DayOfTheWeek(ADate) >= 6;
end;

end.
