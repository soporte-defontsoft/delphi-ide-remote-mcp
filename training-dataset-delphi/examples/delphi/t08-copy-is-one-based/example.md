---
id: t08-copy-is-one-based
family: task
language: delphi
framework: rtl
teaches: Copy, Pos and S[i] count from 1; the string helper methods count from 0; Copy clips
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: t08 and the counting fact)
---

## user
Delphi: return the first three characters of a product code. Some codes are shorter than three characters.

## assistant
`Copy(S, 1, 3)` does it and is safe on shorter strings: `Copy` clips to what is there. Mind where counting starts: `Copy`, `Pos` and `S[i]` count from **1**, while the string helper methods count from **0** - `'ABCDEF'.Substring(1, 3)` is `'BCD'` and `'ABCDEF'.IndexOf('A')` is 0. Do not mix the two styles in one expression.

{{code:CodePrefix.pas}}
