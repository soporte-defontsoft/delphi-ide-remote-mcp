---
id: t06-try-finally-free
family: task
language: delphi
framework: rtl
teaches: Create before try, Free in finally
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: t06)
---

## user
In Delphi, write a function that counts the non-empty lines of a text. A line with only spaces counts as empty.

## assistant
A `TStringList` splits the text into lines, and it is freed in a `try...finally`. `Create` goes **before** `try`: if the constructor fails there is nothing to free, and once it has succeeded `finally` frees the list whatever happens inside.

{{code:TextLines.pas}}
