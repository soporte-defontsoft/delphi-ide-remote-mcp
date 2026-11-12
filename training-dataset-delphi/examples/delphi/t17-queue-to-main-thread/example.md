---
id: t17-queue-to-main-thread
family: task
language: delphi
framework: rtl
teaches: work runs on a background thread; what touches the UI goes back to the main thread with TThread.Queue (or Synchronize, which waits)
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: t17 - the callback arrives on the main thread, MainThreadID, with the right total)
---

## user
In Delphi, sum the numbers 1..N on a background thread, so the application does not freeze, and hand the total to a callback that updates the UI. Write `SumInBackground(const ACount: Integer; const AOnDone: TProc<Int64>)`.

## assistant
The work goes to a background thread (`TThread.CreateAnonymousThread`), but the callback updates the UI, and the UI may only be touched from the main thread. `TThread.Queue` hands a procedure to the main thread and returns at once; `TThread.Synchronize` would wait until the main thread has run it. Both live in `System.Classes`; `TProc<T>` comes from `System.SysUtils`. (In a console program the main thread runs what was queued when it calls `CheckSynchronize`; a VCL or FireMonkey application does it on its own.)

{{code:BackgroundSum.pas}}
