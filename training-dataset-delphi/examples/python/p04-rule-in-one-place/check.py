import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "tools"))
from pycheck import load, raises  # noqa: E402

# the premise: the given commission accepts a negative percentage
given = load(HERE, "given", "percentages")
assert not raises(ValueError, given.commission, 100, -5)

p = load(HERE, "answer", "percentages")
assert raises(ValueError, p.commission, 100, -5)
for fn in (p.apply_discount, p.apply_surcharge, p.commission):
    assert raises(ValueError, fn, 100, -1)
    assert raises(ValueError, fn, 100, 101)
assert p.apply_discount(200, 10) == 180
assert p.apply_surcharge(200, 10) == 220
assert p.commission(200, 10) == 20
print("p04 ok")
