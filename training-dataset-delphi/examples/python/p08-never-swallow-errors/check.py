import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "tools"))
from pycheck import load, raises  # noqa: E402

lines = ["3", " 4 ", "x", "", "5"]

# the premise: the given code hides every error, an unexpected one (None instead of a line) too
given = load(HERE, "given", "quantities")
assert given.sum_quantities(lines) == 12
assert not raises(AttributeError, given.sum_quantities, ["3", None])

q = load(HERE, "answer", "quantities")
assert q.sum_quantities(lines) == (12, 2)
# the error nobody expected is raised, not swallowed
assert raises(AttributeError, q.sum_quantities, ["3", None])
print("p08 ok")
