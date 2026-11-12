---
id: ho46-second-writer-lot-code
family: every-place
language: delphi
framework: rtl
teaches: a bug report against a reader is often a second writer; the writer that drifted calls the one writer, and the reader stays its strict inverse - it is never taught a second shape
judge: dcc64 37.0 Win64 + run (verify/HeldoutSpecTest: ho46 - the printed code reads back, both writers agree, the reader still refuses the other shape and a day that does not exist); the day is formatted once (once)
once: FormatDateTime(
varies: e05-second-writer-bug-report e08-second-writer-file-name p09-second-writer-bug-report p12-second-writer-file-name e02-one-writer-one-reader
---

## user
Boxes scanned at the warehouse are refused: `TryParseLotCode` does not read the code printed on their labels, like `L3-07.03.2026`. Fix this Delphi unit.

{{code:given/LotCodes.pas}}

## assistant
`TryParseLotCode` is right; the bug is a second writer. `LotCode` writes `L3-20260307`, and `LabelLotCode` writes the same lot as `L3-07.03.2026`. Teaching the reader a second shape would make every reader of the code carry both, and the next writer would invent a third. So `LabelLotCode` calls `LotCode`: one writer, and the reader stays its strict inverse. Labels already printed in the other shape can be converted once where they are scanned in, instead of loosening the everyday reader.

{{code:answer/LotCodes.pas}}
