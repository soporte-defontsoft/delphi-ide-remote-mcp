---
id: x03-rtl-iso8601
family: landscape
language: delphi
framework: rtl
teaches: ISO8601ToDate already exists; a time without an offset is read as UTC - the default returns it as written, AReturnUTC = False converts it to local time
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: x03 and its three facts, the time-zone ones independent of the machine's zone); the answer calls ISO8601ToDate (must_contain)
must_contain: ISO8601ToDate(AText)
---

## user
In Delphi, parse `2026-11-12T09:05:07` (ISO 8601) into a TDateTime. Write `ParseStamp(const AText: string): TDateTime`.

## assistant
System.DateUtils already has it: `ISO8601ToDate` (and `DateToISO8601` for the way back). A hand-written parser with `Copy` and `StrToInt` would be a copy of it that misses what it already handles, such as fractions of a second. Mind the time zone: a time without an offset is read as UTC. The default (`AReturnUTC = True`) returns it as written; `False` would convert it to the local time zone.

{{code:IsoStamp.pas}}
