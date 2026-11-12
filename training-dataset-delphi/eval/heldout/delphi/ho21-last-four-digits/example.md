---
id: ho21-last-four-digits
family: task
language: delphi
framework: rtl
teaches: Delphi strings start at 1: the last N characters start at Length - N + 1
judge: dcc64 37.0 Win64 + run (verify/HeldoutSpecTest: ho21)
varies: t08-copy-is-one-based
---

## user
In Delphi, write the unit `CardMask` with `function MaskCard(const ANumber: string): string;`. A card number (digits only, at least four of them) becomes `**** ` followed by its last four digits: `4111111111111234` gives `**** 1234`.

## assistant
Delphi strings start at 1, so the last four characters start at `Length(ANumber) - 3`, not at `Length(ANumber) - 4`: `Copy(ANumber, Length(ANumber) - 3, 4)`. With exactly four digits that is `Copy(ANumber, 1, 4)`, the whole number.

{{code:CardMask.pas}}
