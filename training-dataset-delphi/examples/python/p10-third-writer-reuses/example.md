---
id: p10-third-writer-reuses
family: every-place
language: python
framework: none
teaches: a new place that needs an existing format calls its one writer - it does not write the format again
judge: python check.py (the subject, and the code inside it reads back); the format is written once (once) and the new function calls the writer (must_contain)
once: "TCK-{
must_contain: "Re: " + ticket_code(year, number)
---

## user
Add `reply_subject(year: int, number: int) -> str` to this Python module: the subject of the e-mail that answers a ticket, `Re: ` followed by the ticket code.

{{code:given/ticket_codes.py}}

## assistant
The module already has the one writer of a ticket code, `ticket_code`, and `parse_ticket_code` reads exactly what it writes. The subject calls it instead of writing `TCK-...` a second time: if the format ever changes, it changes in one place, and the code in the subject is always one the reader understands.

{{code:answer/ticket_codes.py}}
