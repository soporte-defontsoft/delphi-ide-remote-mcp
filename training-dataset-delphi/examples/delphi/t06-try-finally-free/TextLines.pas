unit TextLines;

interface

function CountNonEmptyLines(const AText: string): Integer;

implementation

uses
  System.Classes, System.SysUtils;

function CountNonEmptyLines(const AText: string): Integer;
var
  Lines: TStringList;
  Line: string;
begin
  Result := 0;
  Lines := TStringList.Create;
  try
    Lines.Text := AText;
    for Line in Lines do
      if Trim(Line) <> '' then
        Inc(Result);
  finally
    Lines.Free;
  end;
end;

end.
