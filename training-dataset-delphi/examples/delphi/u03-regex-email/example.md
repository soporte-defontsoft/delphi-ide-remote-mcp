---
id: u03-regex-email
family: task
language: delphi
framework: rtl
teaches: TRegEx lives in System.RegularExpressions; TRegEx.IsMatch is a class function - nothing to create or free
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: u03, and the unit of TRegEx read through RTTI)
---

## user
Write `LooksLikeEmail(const AText: string): Boolean` in Delphi with a regular expression: something@something.something, with no spaces.

## assistant
`TRegEx` lives in `System.RegularExpressions`. `TRegEx.IsMatch` is a class function, so there is nothing to create or free. This is a plausibility check, not a full RFC 5322 validator.

{{code:EmailCheck.pas}}
