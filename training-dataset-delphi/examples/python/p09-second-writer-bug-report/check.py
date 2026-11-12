import os
import sys
from datetime import date

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "tools"))
from pycheck import load  # noqa: E402

day = date(2026, 3, 7)

# the premise: the log writer writes what the reader refuses, the other writer what it reads
given = load(HERE, "given", "session_keys")
assert given.parse_session_key(given.session_key_for_log(7, day)) is None
assert given.parse_session_key(given.session_key(7, day)) == (7, day)

keys = load(HERE, "answer", "session_keys")
assert keys.session_key(7, day) == "7:20260307"
assert keys.session_key_for_log(7, day) == keys.session_key(7, day)
assert keys.parse_session_key(keys.session_key_for_log(7, day)) == (7, day)
# the reader stays strict
assert keys.parse_session_key("7:2026-03-07") is None
assert keys.parse_session_key("x:20260307") is None
assert keys.parse_session_key("7:20261341") is None
print("p09 ok")
