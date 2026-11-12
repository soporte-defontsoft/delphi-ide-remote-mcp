---
id: t18-parallel-counter
family: task
language: delphi
framework: rtl
teaches: TParallel.For (System.Threading) runs the body on several threads; a shared counter needs TInterlocked (System.SyncObjs)
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: t18; the units of TParallel and TInterlocked read from the classes)
---

## user
In Delphi, count the multiples of a step between 1 and a limit using all the cores. Write `CountMultiples(const ALimit, AStep: Integer): Integer`.

## assistant
`TParallel.For`, in `System.Threading`, runs the body on several threads at once. The counter is shared by all of them, and `Inc(Count)` is not atomic: two threads can read the same value and one increment is lost. `TInterlocked.Increment`, from `System.SyncObjs`, makes each increment atomic.

{{code:ParallelCount.pas}}
