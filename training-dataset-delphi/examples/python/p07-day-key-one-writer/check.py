import os
import sys
from datetime import date

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "tools"))
from pycheck import load  # noqa: E402

day = date(2026, 3, 7)

# the premise: the two writers of the given module disagree
given = load(HERE, "given", "day_keys")
assert given.archive_day_key(day) != given.day_key(day)

keys = load(HERE, "answer", "day_keys")
assert keys.day_key(day) == "20260307"
assert keys.archive_day_key(day) == keys.day_key(day)
assert keys.date_from_day_key(keys.day_key(day)) == day
assert keys.date_from_day_key("20261341") is None
assert keys.date_from_day_key("2026-1-1") is None
print("p07 ok")
