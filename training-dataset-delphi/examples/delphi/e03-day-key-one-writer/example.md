---
id: e03-day-key-one-writer
family: every-place
language: delphi
framework: rtl
teaches: two writers of one format drift (and one may not even be readable); one writer, and the reader as its inverse
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: e03 - round trip, both callers agree, bad keys refused without an exception); the format is written once (once)
once: FormatDateTime('yyyymmdd'
---

## user
Add a function to this Delphi unit that turns a day key back into a date.

{{code:given/DayKeys.pas}}

## assistant
There are already two writers of the key, and they disagree: `DayKey` writes `20260307` and `ArchiveDayKey` writes `202637`. The second one cannot be read back at all: `2026111` could be the 1st of November or the 11th of January. A reader can only be the inverse of one writer. So `DayKey` is the one writer, `ArchiveDayKey` calls it, and the reader is written as its inverse: fixed width, every part checked, and `TryEncodeDate` refuses a day that does not exist.

{{code:answer/DayKeys.pas}}
