---
id: e01-rule-in-one-place
family: every-place
language: delphi
framework: rtl
teaches: a bug in one copy of a rule is fixed where the rule should live, so it cannot come back in only one place
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: e01 - all three refuse -5 and 101); the range check appears once (once)
once: (APercent < 0) or (APercent > 100)
---

## user
Bug: `Commission` in this Delphi unit accepts a negative percentage. Fix it.

{{code:given/Percentages.pas}}

## assistant
The rule "a percentage goes from 0 to 100" is written three times, and the copy in `Commission` is the one that drifted. Fixing only that line would leave three copies waiting for the next drift. Fix it where the rule should live: one `CheckPercent`, called by the three functions - the bug is gone, and it cannot come back in only one of them.

{{code:answer/Percentages.pas}}
