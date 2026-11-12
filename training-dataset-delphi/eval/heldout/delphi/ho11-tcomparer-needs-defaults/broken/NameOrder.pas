unit NameOrder;

interface

// Shortest names first; names of the same length in alphabetical order
procedure SortByLength(var ANames: TArray<string>);

implementation

uses
  System.Generics.Collections;

procedure SortByLength(var ANames: TArray<string>);
begin
  TArray.Sort<string>(ANames, TComparer<string>.Construct(
    function(const A, B: string): Integer
    begin
      Result := Length(A) - Length(B);
      if Result = 0 then
        Result := CompareStr(A, B);
    end));
end;

end.
