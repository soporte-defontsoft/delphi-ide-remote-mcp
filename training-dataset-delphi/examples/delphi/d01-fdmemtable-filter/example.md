---
id: d01-fdmemtable-filter
family: task
language: delphi
framework: rtl
teaches: a TFDMemTable built in code (FieldDefs, CreateDataSet, AppendRecord); a filter is an expression whose numbers take a dot; RecordCount counts the filtered rows
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: d01, and the fact that a decimal comma in the expression is refused)
---

## system
You write Delphi (RAD Studio 13) code.

## user
Load a list of prices into a TFDMemTable and count how many are above a limit, using the table's filter. Write `CountAbove(const APrices: array of Currency; const ALimit: Currency): Integer`.

## assistant
A `TFDMemTable` (`FireDAC.Comp.Client`) is defined in code with `FieldDefs` and `CreateDataSet`; the field types (`ftCurrency`) come from `Data.DB`. A filter is an expression, and its numbers take a dot whatever the user's locale: a decimal comma is refused. Build the number with `TFormatSettings.Invariant`. With the filter on, FireDAC's `RecordCount` counts the rows that pass it.

{{code:PriceFilter.pas}}
