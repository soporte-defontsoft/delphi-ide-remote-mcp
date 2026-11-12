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

uses
  System.Generics.Defaults;

procedure SortByPriority(const ATasks: TList<TTask>);
begin
  // TList<T>.Sort takes an IComparer<T>: TComparer<T>.Construct wraps the function
  ATasks.Sort(TComparer<TTask>.Construct(
    function(const ALeft, ARight: TTask): Integer
    begin
      Result := ALeft.Priority - ARight.Priority;
    end));
end;

end.
