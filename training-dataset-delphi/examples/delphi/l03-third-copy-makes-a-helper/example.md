---
id: l03-third-copy-makes-a-helper
family: landscape
language: delphi
framework: rtl
teaches: two copies are the signal - the third is written as one helper with parameters, and the others call it
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: l03); the date format appears once in the answer (once)
once: FormatDateTime('yyyy-mm-dd'
---

## user
Add `ReturnLine` to this Delphi unit: the same line as the other two, for returns ("Return 7 - 2026-11-12").

{{code:given/ReportLines.pas}}

## assistant
This would be the third copy of the same line. Two copies are already the signal: write the line once, in a helper that takes what changes (the kind of document) as a parameter, and make the three functions call it. The next change to the format - another date style, a prefix - is then made in one place.

{{code:answer/ReportLines.pas}}
