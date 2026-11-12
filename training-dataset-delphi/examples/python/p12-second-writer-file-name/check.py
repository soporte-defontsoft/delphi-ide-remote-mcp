import os
import sys
from datetime import date

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "tools"))
from pycheck import load  # noqa: E402

day = date(2026, 3, 7)

# the premise: the reader refuses what the second writer writes, and reads the first
given = load(HERE, "given", "report_paths")
assert given.day_of_report(given.emailed_report_name(day)) is None
assert given.day_of_report(given.report_name(day)) == day

paths = load(HERE, "answer", "report_paths")
assert paths.report_name(day) == "report-2026-03-07.txt"
assert paths.emailed_report_name(day) == paths.report_name(day)
assert paths.day_of_report(paths.emailed_report_name(day)) == day
# the reader stays strict
assert paths.day_of_report("report-7.3.2026.txt") is None
assert paths.day_of_report("report-2026-02-30.txt") is None
print("p12 ok")
