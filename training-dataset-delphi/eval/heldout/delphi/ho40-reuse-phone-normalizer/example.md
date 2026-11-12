---
id: ho40-reuse-phone-normalizer
family: landscape
language: delphi
framework: rtl
teaches: look at what the unit already has before writing; compare through the normalizer it has instead of writing a second one
judge: dcc64 37.0 Win64 + run (verify/HeldoutSpecTest: ho40 - a 00 prefix and a + are the same number, a missing + is not); the answer calls the normalizer (must_contain)
must_contain: NormalizePhone(A)
varies: l01-reuse-existing-helper l02-reuse-normalizer p01-reuse-existing-helper
---

## user
Add to this Delphi unit a function `SamePhone(const A, B: string): Boolean`: true when two phone numbers, as people type them, are the same number.

{{code:given/PhoneBook.pas}}

## assistant
The unit already knows what makes two phone numbers the same: `NormalizePhone` keeps the digits, keeps a leading `+`, and reads a leading `00` as `+`. `SamePhone` compares what it gives for each number. A second filter written inside `SamePhone` would forget one of those rules today, or the next one tomorrow.

{{code:answer/PhoneBook.pas}}
