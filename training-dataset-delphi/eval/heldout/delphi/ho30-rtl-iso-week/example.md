---
id: ho30-rtl-iso-week
family: landscape
language: delphi
framework: rtl
teaches: the RTL already has the ISO 8601 week number: WeekOfTheYear (System.DateUtils)
judge: dcc64 37.0 Win64 + run (verify/HeldoutSpecTest: ho30 - weeks 53 and 1 at both ends of a year, with and without a time of day); the RTL is used (must_contain)
must_contain: WeekOf
varies: x01-rtl-leap-year x02-rtl-days-between x07-rtl-days-in-month
---

## user
We need ISO 8601 week numbers in a Delphi (RAD Studio 13) program. Write the unit `WeekNumbers` with `function IsoWeek(const ADate: TDateTime): Integer;`.

## assistant
The RTL already has it: `WeekOfTheYear` in `System.DateUtils` follows ISO 8601. Weeks start on Monday, and week 1 is the one that holds the year's first Thursday, so 3 January 2021 is in week 53 (of 2020) and 30 December 2024 in week 1 (of 2025). The time of day does not change the week.

{{code:WeekNumbers.pas}}
