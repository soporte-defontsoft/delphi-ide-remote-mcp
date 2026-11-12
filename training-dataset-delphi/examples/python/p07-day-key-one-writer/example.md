---
id: p07-day-key-one-writer
family: every-place
language: python
framework: none
teaches: two writers of one format drift (and one may not even be readable); one writer, and the reader as its inverse
judge: python check.py (the premise on given/; round trip, both callers agree, bad keys refused on answer/); the format is written once (once)
once: "%Y%m%d"
---

## user
Add a function to this Python module that turns a day key back into a date.

{{code:given/day_keys.py}}

## assistant
There are already two writers of the key, and they disagree: `day_key` writes `20260307` and `archive_day_key` writes `202637`. The second one cannot be read back at all: `2026111` could be the 1st of November or the 11th of January. A reader can only be the inverse of one writer. So `day_key` is the one writer, `archive_day_key` calls it, the format lives in one constant, and the reader is written as its inverse.

{{code:answer/day_keys.py}}
