---
id: ho10-interlocked-needs-syncobjs
family: repair
language: delphi
framework: rtl
teaches: TInterlocked lives in System.SyncObjs; an unknown name breeds an E2066 on its own line - fix the first error
judge: dcc64 37.0 Win64 - broken gives exactly dcc.txt (compiled from a short path); fixed compiles and runs (verify/HeldoutSpecTest: ho10 - hits counted from parallel threads, and the unit read from the class)
varies: r07-tstringlist-needs-classes r18-stream-needs-classes r20-field-types-need-data-db t18-parallel-counter
---

## user
This Delphi unit does not compile:

{{text:dcc.txt}}

{{code:broken/HitCounter.pas}}

## assistant
`TInterlocked` is declared in `System.SyncObjs`, and the unit has no `uses` clause at all. The E2066 on the same line is the compiler losing its way after the unknown name; it goes away with the first error. Only the implementation uses the class, so `System.SyncObjs` goes in the implementation `uses` clause. `TInterlocked.Increment` is what keeps the count right when several threads call `Hit` at once.

{{code:fixed/HitCounter.pas}}
