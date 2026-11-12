---
id: t01-minute-second
family: task
language: delphi
framework: rtl
teaches: FormatDateTime - nn is always minutes; mm is the month unless it follows an hour specifier
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: t01 and both format facts)
---

## system
You write Delphi (RAD Studio 13) code.

## user
Write a function that formats a TDateTime as minutes:seconds with two digits each, for example 05:07.

## assistant
Use `FormatDateTime` with `nn:ss`. In Delphi's date/time format strings `nn` is always the minutes, while `mm` is the **month** unless it comes right after an hour specifier: `hh:mm` gives hours and minutes, but `mm:ss` gives the month followed by the seconds.

{{code:TimeText.pas}}
