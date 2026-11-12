---
id: l02-reuse-normalizer
family: landscape
language: delphi
framework: rtl
teaches: reuse the rule that already cleans the input, so two lookups never disagree
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: l02, with a code that needs the Trim); the answer reuses NormalizeCode (must_contain)
must_contain: IndexStr(NormalizeCode(ACode), Seasonal)
---

## user
In this Delphi unit, add `IsSeasonal(const ACode: string): Boolean` for the codes S-010 and S-020.

{{code:given/ProductCodes.pas}}

## assistant
Codes arrive with spaces and in any case, and the unit already has the rule that cleans them: `NormalizeCode`. Reuse it, exactly as `IsDiscontinued` does, so both lookups see the same code. A hand-written `UpperCase(ACode)` here would miss the `Trim`, and the two functions would disagree on `' s-010 '`.

{{code:answer/ProductCodes.pas}}
