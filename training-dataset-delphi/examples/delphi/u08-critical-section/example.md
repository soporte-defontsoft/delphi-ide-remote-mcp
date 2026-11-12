---
id: u08-critical-section
family: task
language: delphi
framework: rtl
teaches: state shared by several threads goes behind one TCriticalSection (System.SyncObjs) - Enter, then try/finally Leave, for reads too; the field types are part of the class declaration, so their units go in the interface uses
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: u08 - 2000 lines added from TParallel.For, 2000 counted; TCriticalSection's unit read through RTTI)
---

## user
Write a Delphi class `TSafeLog` that keeps lines of text in memory, with `Add(const AText: string)` and `Count: Integer`, safe to call from several threads at once.

## assistant
`TStringList` has no lock of its own, so every access goes through one: a `TCriticalSection` from `System.SyncObjs`, with `Enter` and then `try ... finally Leave`, so that an exception never leaves it locked. `Count` takes the lock too, so nobody reads the list while another thread is changing it. The types of the fields (`TStringList` from `System.Classes`, `TCriticalSection`) are part of the class declaration, so both units go in the interface `uses` clause. The class creates both objects and frees them in its destructor.

{{code:SafeLog.pas}}
