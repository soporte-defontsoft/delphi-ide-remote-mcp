---
id: x07-rtl-days-in-month
family: landscape
language: delphi
framework: rtl
teaches: look before you write includes the RTL - DaysInAMonth (System.DateUtils) knows leap years; a table of month lengths is a second copy of the calendar
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: x07 - February 2024 and 2026, April); the answer calls the RTL (must_contain)
must_contain: DaysInAMonth(AYear, AMonth)
---

## user
Write `DaysIn(const AYear, AMonth: Word): Word` in Delphi: how many days a month has.

## assistant
`System.DateUtils` already has it: `DaysInAMonth`, leap years included (February 2024 has 29 days, February 2026 has 28). A table of month lengths plus a leap-year rule would be a second copy of the calendar - more code to get wrong. Better still, call `DaysInAMonth` directly wherever you need it.

{{code:MonthDays.pas}}
