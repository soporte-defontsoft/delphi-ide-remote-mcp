---
id: r20-field-types-need-data-db
family: repair
language: delphi
framework: rtl
teaches: the field types (ftString, ftCurrency...) are values of TFieldType, declared in Data.DB - not in FireDAC's units; a unit only sees what the units it names declare
judge: dcc64 37.0 Win64 - broken gives exactly dcc.txt (compiled from a short path); fixed compiles and runs (verify/DatasetSpecTest: r20 - the two fields; TFieldType read through RTTI)
---

## user
This Delphi unit does not compile:

{{text:dcc.txt}}

{{code:broken/ProductTable.pas}}

## assistant
`ftString` and `ftCurrency` are values of `TFieldType`, which is declared in `Data.DB`, not in FireDAC's own units. Naming `FireDAC.Comp.Client` does not bring them in: in Delphi a unit only sees what the units it names declare, never what those units use in turn. Only the implementation needs them, so `Data.DB` goes in the implementation `uses` clause.

{{code:fixed/ProductTable.pas}}
