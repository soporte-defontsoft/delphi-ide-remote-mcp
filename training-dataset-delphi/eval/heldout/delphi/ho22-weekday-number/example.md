---
id: ho22-weekday-number
family: task
language: delphi
framework: rtl
teaches: case needs an ordinal value; IndexText (System.StrUtils) gives the position of a string in a list, ignoring case, and -1 when nothing matches
judge: dcc64 37.0 Win64 + run (verify/HeldoutSpecTest: ho22)
varies: t11-case-needs-ordinal r04-case-on-string
---

## user
Delphi: write the unit `WeekdayNames` with `function WeekdayNumber(const AName: string): Integer;`. The English name of a weekday, in any case (`Monday`, `TUESDAY`, `sunday`), gives its ISO number, Monday 1 to Sunday 7; anything else gives 0.

## assistant
In Delphi a `case` statement cannot select on a string: it needs an ordinal value. `IndexText` (`System.StrUtils`) finds a string in a list without regard to case and gives its index, or -1 when nothing matches. The index plus one is then the ISO number, and 0 for anything else.

{{code:WeekdayNames.pas}}
