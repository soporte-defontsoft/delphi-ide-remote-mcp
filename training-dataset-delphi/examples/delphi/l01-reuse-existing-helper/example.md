---
id: l01-reuse-existing-helper
family: landscape
language: delphi
framework: rtl
teaches: look at what the unit already has before writing; call the helper instead of writing its twin
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: l01); the answer calls FullName (must_contain)
must_contain: 'Customer: ' + FullName(AFirst, ALast)
---

## user
Add a function `CustomerLabel(const AFirst, ALast: string): string` to this Delphi unit. It returns `Customer: ` followed by the customer's full name.

{{code:given/CustomerText.pas}}

## assistant
Before writing it, look at what the unit already has: `FullName` builds exactly that name - it trims both parts and leaves no stray space when one of them is empty. `CustomerLabel` calls it instead of building the name again: a second copy would give a different answer the first time someone changes how names are built.

{{code:answer/CustomerText.pas}}
