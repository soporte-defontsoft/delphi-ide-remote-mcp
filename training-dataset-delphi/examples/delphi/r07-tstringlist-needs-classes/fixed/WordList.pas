unit WordList;

interface

function SortedWords(const AText: string): string;

implementation

uses
  System.Classes, System.SysUtils;

function SortedWords(const AText: string): string;
var
  Words: TStringList;
begin
  Words := TStringList.Create;
  try
    Words.Delimiter := ' ';
    Words.StrictDelimiter := True;
    Words.DelimitedText := Trim(AText);
    Words.Sort;
    Result := Words.DelimitedText;
  finally
    Words.Free;
  end;
end;

end.
