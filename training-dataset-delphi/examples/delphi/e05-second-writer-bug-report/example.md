---
id: e05-second-writer-bug-report
family: every-place
language: delphi
framework: rtl
teaches: a bug report against a reader is often a second writer; the writer that drifted calls the one writer, and the reader stays its strict inverse - it is never taught a second shape
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: e05 - the archive reference reads back, both writers agree, the reader still refuses the short shape); the format is written once (once)
once: Format('ORD-%d-%.5d'
---

## user
Users report that the references printed on archived orders, like `ORD-2026-42`, are refused by `TryParseOrderRef` in this Delphi unit. Fix it.

{{code:given/OrderRefs.pas}}

## assistant
The reader is right; the bug is a second writer. `OrderRef` writes `ORD-2026-00042`, and `ArchiveOrderRef` builds the same reference by hand as `ORD-2026-42`. Teaching the reader a second shape would make every reader of the format carry both, and the next writer would invent a third. So `ArchiveOrderRef` calls `OrderRef`: one writer, and `TryParseOrderRef` stays its strict inverse. If short references were already stored, convert them once to the real shape instead of loosening the everyday reader.

{{code:answer/OrderRefs.pas}}
