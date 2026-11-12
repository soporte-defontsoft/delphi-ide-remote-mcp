---
id: p02-third-copy-makes-a-helper
family: landscape
language: python
framework: none
teaches: two copies are the signal - the third is written as one helper with parameters, and the others call it
judge: python check.py (behaviour); the date format appears once in the answer (once)
once: %Y-%m-%d
---

## user
Add `return_line(number, day)` to this Python module: the same line as the other two, for returns ("Return 7 - 2026-11-12").

{{code:given/report_lines.py}}

## assistant
This would be the third copy of the same line. Two copies are already the signal: write the line once, in a helper that takes what changes (the kind of document) as a parameter, and make the three functions call it. The next change to the format is then made in one place.

{{code:answer/report_lines.py}}
