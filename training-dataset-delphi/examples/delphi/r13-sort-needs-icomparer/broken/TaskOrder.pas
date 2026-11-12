unit TaskOrder;

interface

uses
  System.Generics.Collections;

type
  TTask = record
    Title: string;
    Priority: Integer;
  end;

procedure SortByPriority(const ATasks: TList<TTask>);

implementation

procedure SortByPriority(const ATasks: TList<TTask>);
begin
  ATasks.Sort(
    function(const ALeft, ARight: TTask): Integer
    begin
      Result := ALeft.Priority - ARight.Priority;
    end);
end;

end.
