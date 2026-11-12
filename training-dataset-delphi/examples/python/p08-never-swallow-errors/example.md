---
id: p08-never-swallow-errors
family: task
language: python
framework: none
teaches: a bare "except Exception: pass" silences every error, the unexpected ones too; catch the one you expect and report it
judge: python check.py (on given/ an unexpected error is swallowed; on answer/ the bad lines are counted and the unexpected error is raised)
---

## system
You write Python code.

## user
This function skips the lines that are not numbers with an `except Exception: pass`. Fix it properly: bad lines must not stop the sum, but the caller has to know how many there were.

{{code:given/quantities.py}}

## assistant
`except Exception: pass` silences every error, the ones nobody expected too: a `None` that slipped into the list is dropped as quietly as a typo, and the caller never learns that lines were lost. Catch only the failure you expect - `ValueError` from `int` - and report it, here as a count returned next to the total. Anything else is still raised, where somebody will see it.

{{code:answer/quantities.py}}
