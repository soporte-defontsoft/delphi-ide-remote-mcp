---
id: u01-dictionary-word-count
family: task
language: delphi
framework: rtl
teaches: TDictionary lives in System.Generics.Collections; Split with ExcludeEmpty skips the empty pieces
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: u01, and the unit of TDictionary read from the class)
---

## user
In Delphi, write `MostFrequentWord(const AText: string): string`: the word that appears most often in a text, ignoring case. Words are separated by spaces.

## assistant
A `TDictionary<string, Integer>` counts each word. It lives in `System.Generics.Collections`, with `TList<T>`, `TObjectList<T>` and `TQueue<T>`. `Split` with `TStringSplitOptions.ExcludeEmpty` skips the empty pieces that double spaces leave; both come from `System.SysUtils`.

{{code:WordFrequency.pas}}
