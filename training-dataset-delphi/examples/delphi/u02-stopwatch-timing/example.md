---
id: u02-stopwatch-timing
family: task
language: delphi
framework: rtl
teaches: TStopwatch lives in System.Diagnostics; TProc in System.SysUtils, needed in the interface when the signature uses it
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: u02, and the unit of TStopwatch read through RTTI)
---

## system
You write Delphi (RAD Studio 13) code.

## user
Write a function `ElapsedMs(const AWork: TProc): Int64` that runs a piece of code and returns how many milliseconds it took.

## assistant
`TStopwatch`, a record in `System.Diagnostics`, is the high-resolution timer: `StartNew`, then `ElapsedMilliseconds`. `TProc`, the type of a parameterless anonymous procedure, comes from `System.SysUtils`, and the interface `uses` it because the signature does.

{{code:Timing.pas}}
