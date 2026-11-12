---
id: ho31-rtl-add-months
family: landscape
language: delphi
framework: rtl
teaches: the RTL already adds months: IncMonth stops at the last day of a shorter month, takes negative months and keeps the time of day
judge: dcc64 37.0 Win64 + run (verify/HeldoutSpecTest: ho31 - month ends, a leap February, negative months and the time of day); the RTL is used (must_contain)
must_contain: IncMonth(
varies: x07-rtl-days-in-month x01-rtl-leap-year x02-rtl-days-between
---

## user
Write the Delphi unit `DueDates` with `function DueDate(const AStart: TDateTime; const AMonths: Integer): TDateTime;`: the same day `AMonths` months later (earlier when it is negative); when that month is shorter, its last day - 31 January 2026 plus one month is 28 February 2026. The time of day stays as it was.

## assistant
`IncMonth` (`System.SysUtils`) is exactly that. It adds whole months and stops at the last day of a shorter month (31 January 2024 plus one month is 29 February 2024); it takes negative months, and it keeps the time of day.

{{code:DueDates.pas}}
