---
id: p04-rule-in-one-place
family: every-place
language: python
framework: none
teaches: a bug in one copy of a rule is fixed where the rule should live, so it cannot come back in only one place
judge: python check.py (the bug exists in given/; all three refuse -1 and 101 in answer/); the range check appears once (once)
once: percent < 0 or percent > 100
---

## user
Bug: `commission` in this Python module accepts a negative percentage. Fix it.

{{code:given/percentages.py}}

## assistant
The rule "a percentage goes from 0 to 100" is written three times, and the copy in `commission` is the one that drifted. Fixing only that line would leave three copies waiting for the next drift. Fix it where the rule should live: one `check_percent`, called by the three functions - the bug is gone, and it cannot come back in only one of them.

{{code:answer/percentages.py}}
