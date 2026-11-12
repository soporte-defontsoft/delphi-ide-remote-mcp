---
id: x01-rtl-leap-year
family: landscape
language: delphi
framework: rtl
teaches: look before you write includes the RTL - IsLeapYear already exists; a second copy of the rule is a twin
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: x01); the answer calls IsLeapYear (must_contain)
must_contain: IsLeapYear(AYear)
---

## user
Write `IsLeap(const AYear: Word): Boolean` for the Gregorian calendar in Delphi.

## assistant
System.SysUtils already has it: `IsLeapYear`. Writing the rule again (every 4 years, except centuries, except every 400) would be a copy of the RTL - more code to get wrong, and one more place to look when it is wrong. Better still, call `IsLeapYear` directly wherever you need it.

{{code:LeapYears.pas}}
