unit ProductTable;

interface

uses
  FireDAC.Comp.Client;

function NewProductTable: TFDMemTable;

implementation

uses
  Data.DB;

function NewProductTable: TFDMemTable;
begin
  // the field types (ftString, ftCurrency...) are declared in Data.DB, not in FireDAC
  Result := TFDMemTable.Create(nil);
  Result.FieldDefs.Add('Name', ftString, 40);
  Result.FieldDefs.Add('Price', ftCurrency);
  Result.CreateDataSet;
end;

end.
