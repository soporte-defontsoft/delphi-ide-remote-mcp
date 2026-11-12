import os
import sys
from datetime import date

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "tools"))
from pycheck import load  # noqa: E402

lines = load(HERE, "answer", "report_lines")
day = date(2026, 11, 12)
assert lines.invoice_line(7, day) == "Invoice 7 - 2026-11-12"
assert lines.delivery_line(7, day) == "Delivery 7 - 2026-11-12"
assert lines.return_line(7, day) == "Return 7 - 2026-11-12"
print("p02 ok")
