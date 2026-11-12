---
id: e02-one-writer-one-reader
family: every-place
language: delphi
framework: rtl
teaches: one function composes a format and its inverse reads it; two writers of the same name drift apart
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: e02 - round trip, both callers agree); the name is composed once (once)
once: Format(ExportPrefix + '%d-%.4d' + ExportSuffix
---

## user
Add a function to this Delphi unit that reads the year and the number back from an export file name.

{{code:given/ExportNames.pas}}

## assistant
There are already two writers of this name and they disagree: `ExportFileName` pads the number to four digits (`export-2026-0007.csv`) and `ArchiveFileName` does not (`export-2026-7.csv`). A reader can only be the inverse of one writer. So: one function composes the name, the other caller uses it, and the reader is written as its inverse, sharing the same prefix and suffix - the three can no longer drift apart. The reader still accepts the old unpadded names, since `TryStrToInt('7')` works.

{{code:answer/ExportNames.pas}}
