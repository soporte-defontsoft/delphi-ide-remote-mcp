unit NameFilter;

interface

uses
  FireDAC.Comp.Client;

procedure FilterByName(const ATable: TFDMemTable; const AName: string);

implementation

procedure FilterByName(const ATable: TFDMemTable; const AName: string);
begin
  ATable.Filter := 'Name = ' + AName;
  ATable.Filtered := True;
end;

end.
