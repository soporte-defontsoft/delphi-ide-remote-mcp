import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "tools"))
from pycheck import load  # noqa: E402

# the premise: the given module has no subject yet
given = load(HERE, "given", "ticket_codes")
assert not hasattr(given, "reply_subject")

tickets = load(HERE, "answer", "ticket_codes")
assert tickets.reply_subject(2026, 7) == "Re: TCK-2026-00007"
# the code inside the subject is one the reader understands
assert tickets.parse_ticket_code(tickets.reply_subject(2026, 7)[len("Re: "):]) == (2026, 7)
print("p10 ok")
