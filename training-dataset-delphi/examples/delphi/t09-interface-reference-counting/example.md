---
id: t09-interface-reference-counting
family: task
language: delphi
framework: rtl
teaches: TInterfacedObject frees itself with its last reference; hand out the interface, never Free it
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: t09)
---

## system
You write Delphi (RAD Studio 13) code.

## user
Write a logger behind an interface (Log adds a line, Count returns how many there are), with an in-memory implementation and a factory function that returns it.

## assistant
The class derives from `TInterfacedObject`, which counts references: hold it through `ILogger` variables and never call `Free` on it - when the last reference goes away, it frees itself. Keeping the class in the implementation section and handing out only the interface means nobody can mix an object variable (and a `Free`) with interface references.

{{code:AppLogger.pas}}
