unit WordFrequency;

interface

function MostFrequentWord(const AText: string): string;

implementation

uses
  System.SysUtils, System.Generics.Collections;

function MostFrequentWord(const AText: string): string;
var
  Counts: TDictionary<string, Integer>;
  Word: string;
  Count, Best: Integer;
begin
  Result := '';
  Best := 0;
  Counts := TDictionary<string, Integer>.Create;
  try
    for Word in LowerCase(AText).Split([' '], TStringSplitOptions.ExcludeEmpty) do
    begin
      if not Counts.TryGetValue(Word, Count) then
        Count := 0;
      Inc(Count);
      Counts.AddOrSetValue(Word, Count);
      if Count > Best then
      begin
        Best := Count;
        Result := Word;
      end;
    end;
  finally
    Counts.Free;
  end;
end;

end.
