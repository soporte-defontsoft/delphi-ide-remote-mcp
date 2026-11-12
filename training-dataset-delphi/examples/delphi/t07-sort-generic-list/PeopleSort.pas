unit PeopleSort;

interface

uses
  System.Generics.Collections;

type
  TPerson = record
    Name: string;
    Age: Integer;
  end;

procedure SortByName(const APeople: TList<TPerson>);

implementation

uses
  System.Generics.Defaults, System.SysUtils;

procedure SortByName(const APeople: TList<TPerson>);
begin
  APeople.Sort(TComparer<TPerson>.Construct(
    function(const ALeft, ARight: TPerson): Integer
    begin
      Result := CompareText(ALeft.Name, ARight.Name);
    end));
end;

end.
