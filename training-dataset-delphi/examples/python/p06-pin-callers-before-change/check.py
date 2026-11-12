import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "tools"))
from pycheck import load  # noqa: E402

# What the answer claims: the first two tests pass on the CURRENT code, the third does not...
load(HERE, "given", "prices")
tests = load(HERE, "answer", "test_prices")
tests.test_line_total_keeps_working()
tests.test_with_tax_keeps_working()
try:
    tests.test_halves_round_up()
    raise SystemExit("p06: the new test already passes on the given code - it proves nothing")
except AssertionError:
    pass

# ...and all three pass after the change
load(HERE, "answer", "prices")
tests = load(HERE, "answer", "test_prices")
tests.test_line_total_keeps_working()
tests.test_with_tax_keeps_working()
tests.test_halves_round_up()
print("p06 ok")
