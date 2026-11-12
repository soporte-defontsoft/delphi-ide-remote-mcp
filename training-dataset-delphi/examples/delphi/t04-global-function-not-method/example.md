---
id: t04-global-function-not-method
family: task
language: delphi
framework: rtl
teaches: a global function is declared in the interface outside the class; DayOfTheWeek is ISO, DayOfWeek starts on Sunday; a unit only the implementation needs goes in the implementation uses
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: t04 and the day-of-week fact)
---

## user
Add a global function `IsWeekend(const ADate: TDateTime): Boolean` to this Delphi unit. It must be a plain function that other units can call, not a method of TShift.

{{code:given/Shifts.pas}}

## assistant
A global function is declared in the `interface` section, outside the class, and implemented in `implementation` without a class prefix. `DayOfTheWeek` (System.DateUtils) is ISO 8601: Monday = 1 ... Sunday = 7, so the weekend is 6 and 7. (`DayOfWeek` in System.SysUtils counts from Sunday = 1, a classic source of off-by-one bugs.) Only the implementation needs System.DateUtils, so it goes in the implementation `uses` clause.

{{code:answer/Shifts.pas}}
