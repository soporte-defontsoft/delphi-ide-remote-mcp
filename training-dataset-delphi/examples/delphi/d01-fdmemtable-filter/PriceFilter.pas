unit PriceFilter;

interface

function CountAbove(const APrices: array of Currency; const ALimit: Currency): Integer;

implementation

uses
  System.SysUtils, Data.DB, FireDAC.Comp.Client;

function CountAbove(const APrices: array of Currency; const ALimit: Currency): Integer;
var
  Table: TFDMemTable;
  Price: Currency;
begin
  Table := TFDMemTable.Create(nil);
  try
    Table.FieldDefs.Add('Price', ftCurrency);
    Table.CreateDataSet;
    for Price in APrices do
      Table.AppendRecord([Price]);
    // the filter is an expression: its numbers take a dot, whatever the user's locale
    Table.Filter := 'Price > ' + CurrToStr(ALimit, TFormatSettings.Invariant);
    Table.Filtered := True;
    Result := Table.RecordCount; // FireDAC counts the rows the filter lets through
  finally
    Table.Free;
  end;
end;

end.
