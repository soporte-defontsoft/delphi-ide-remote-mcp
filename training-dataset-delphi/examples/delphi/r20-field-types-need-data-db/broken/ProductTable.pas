unit ProductTable;

interface

uses
  FireDAC.Comp.Client;

function NewProductTable: TFDMemTable;

implementation

function NewProductTable: TFDMemTable;
begin
  Result := TFDMemTable.Create(nil);
  Result.FieldDefs.Add('Name', ftString, 40);
  Result.FieldDefs.Add('Price', ftCurrency);
  Result.CreateDataSet;
end;

end.
