---
id: r04-case-on-string
family: repair
language: delphi
framework: rtl
teaches: E2001 - case needs an ordinal selector; start with the first error, the rest follow from it
judge: dcc64 37.0 Win64 - broken gives exactly dcc.txt (verify/DatasetBrokenProbe); fixed compiles and runs (verify/DatasetSpecTest: r04)
---

## user
In Delphi, why does this not compile, and how do I fix it?

{{text:dcc.txt}}

{{code:broken/SizeCodes.pas}}

## assistant
Start with the first error: `case` needs an ordinal selector (an integer, a character, an enumeration) and `ASize` is a string (E2001). The E2010 lines follow from it, and they go away once it is fixed. Look the string up first and branch on its position: `IndexStr` (System.StrUtils) returns its index in the list, case-sensitive, or -1.

{{code:fixed/SizeCodes.pas}}
