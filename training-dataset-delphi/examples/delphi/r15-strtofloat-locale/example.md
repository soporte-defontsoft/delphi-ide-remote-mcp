---
id: r15-strtofloat-locale
family: repair
language: delphi
framework: rtl
teaches: StrToFloat without settings uses the user's locale - on a Spanish Windows the decimal separator is ','; data files are parsed with TFormatSettings.Invariant
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: r15 - the exception of exception.txt, raised with the Spanish settings whatever the machine's own)
---

## user
This Delphi function reads prices from a CSV file written with a dot (`1.5`). On my machine it works, but on a Spanish Windows it fails with:

{{text:exception.txt}}

{{code:broken/DecimalText.pas}}

## assistant
`StrToFloat` without settings uses the user's regional settings, and on a Spanish Windows the decimal separator is `,` (the dot is the thousands separator), so `'1.5'` is not a number there. A file has its own format, whatever the machine: parse it with `TFormatSettings.Invariant` (dot as the decimal separator). The user's settings are for what the user types and reads on screen.

{{code:fixed/DecimalText.pas}}
