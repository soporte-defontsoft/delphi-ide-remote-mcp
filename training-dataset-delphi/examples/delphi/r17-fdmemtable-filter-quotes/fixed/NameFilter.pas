unit NameFilter;

interface

uses
  FireDAC.Comp.Client;

procedure FilterByName(const ATable: TFDMemTable; const AName: string);

implementation

uses
  System.SysUtils, Data.DB;

procedure FilterByName(const ATable: TFDMemTable; const AName: string);
begin
  // a text value goes quoted in the filter expression; QuotedStr also doubles an inner
  // quote (O'Brien). Without the quotes, the value is read as a column name.
  ATable.Filter := 'Name = ' + QuotedStr(AName);
  ATable.FilterOptions := [foCaseInsensitive];
  ATable.Filtered := True;
end;

end.
