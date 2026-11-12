---
id: r17-fdmemtable-filter-quotes
family: repair
language: delphi
framework: rtl
teaches: a text value in a FireDAC filter goes quoted (QuotedStr, which also doubles an inner quote); without quotes it is read as a column name; FilterOptions for case
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: r17 - the exception of exception.txt, word for word; the fix with a case difference and with an inner quote)
---

## user
I filter a TFDMemTable by name and get this exception:

{{text:exception.txt}}

{{code:broken/NameFilter.pas}}

The search should also ignore upper and lower case.

## assistant
The filter is an expression: `Name = Ann` compares the column `Name` with a column (or function) called `Ann`, which does not exist. A text value goes in quotes: `Name = 'Ann'`. Build it with `QuotedStr`, which also doubles a quote inside the value (`O'Brien`), so the name cannot break the expression. The comparison is case-sensitive by default; `FilterOptions := [foCaseInsensitive]` changes that.

{{code:fixed/NameFilter.pas}}
