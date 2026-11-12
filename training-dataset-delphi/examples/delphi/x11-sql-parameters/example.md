---
id: x11-sql-parameters
family: landscape
language: delphi
framework: rtl
teaches: a value goes into SQL as a parameter, never concatenated - a quote breaks the query, and a crafted value changes it; quoting by hand is the short list again
judge: dcc64 37.0 Win64 + run against SQLite in memory through FireDAC (verify/DatasetSpecTest: x11 - a quote in the name, a value that tries to change the query; facts: concatenated, the message of exception.txt, and a value that counts every row); the answer uses a parameter (must_contain)
must_contain: = :name', [AName])
---

## user
This Delphi function fails when the name has a quote in it, like `O'Brien`:

{{text:exception.txt}}

{{code:given/CustomerQueries.pas}}

## assistant
Doubling the quote by hand would fix `O'Brien` and leave the real problem: the value is part of the SQL text. A name such as `x' or '1'='1` turns the query into `where name = 'x' or '1'='1'`, which counts every row. The value goes as a parameter instead: `:name` in the SQL, and the value apart, `ExecSQLScalar(SQL, [AName])`. It never becomes part of the SQL text, so there is nothing to quote, and nothing in it can change the query.

{{code:answer/CustomerQueries.pas}}
