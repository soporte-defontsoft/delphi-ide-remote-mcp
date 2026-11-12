---
id: x02-rtl-days-between
family: landscape
language: delphi
framework: rtl
teaches: DaysBetween already exists and counts whole 24-hour days in either order; DateOf turns it into calendar days
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: x02 and both facts); the answer calls DaysBetween (must_contain)
must_contain: DaysBetween(AFrom, ATo)
---

## system
You write Delphi (RAD Studio 13) code.

## user
How many days are there between two dates, whatever their order? Write `DaysApart(const AFrom, ATo: TDateTime): Integer`.

## assistant
`DaysBetween`, in System.DateUtils, already does it, in either order. It counts whole 24-hour days: from the 12th at 08:00 to the 13th at 07:00 it gives 0. To count calendar days instead, pass `DateOf(...)` of both dates (then it gives 1).

{{code:DayCount.pas}}
