import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "tools"))
from pycheck import load  # noqa: E402

names = load(HERE, "answer", "names")
assert names.customer_label(" Ann ", "Lee") == "Customer: Ann Lee"
assert names.customer_label("", "Lee") == "Customer: Lee"
print("p01 ok")
