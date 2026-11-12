---
id: ho60-record-operators
family: task
language: delphi
framework: rtl
teaches: operators on a record (class operator Add, Multiply, Equal) - a control: no example of the dataset teaches it
judge: dcc64 37.0 Win64 + run (verify/HeldoutSpecTest: ho60)
varies: none
---

## user
Write the Delphi unit `Vectors`: a record `TVec2` with the fields `X, Y: Double`; operators so that `A + B` adds two vectors, `A * K` multiplies one by a number and `A = B` compares two of them; a method `function Length: Double` (its length); and a global function `Vec2(const AX, AY: Double): TVec2` that builds one.

## assistant
A Delphi record declares its operators as `class operator`: `Add` for `+`, `Multiply` for `*` (here a vector and a `Double`, in that order) and `Equal` for `=`. They live inside the record, so the operators work wherever the type is used. `Vec2` is a global function, declared in the interface outside the record.

{{code:Vectors.pas}}
