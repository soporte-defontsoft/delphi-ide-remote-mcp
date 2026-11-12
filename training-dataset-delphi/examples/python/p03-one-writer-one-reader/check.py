import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "tools"))
from pycheck import load  # noqa: E402

# the premise: the two writers of the given module disagree
given = load(HERE, "given", "export_names")
assert given.archive_file_name(2026, 7) != given.export_file_name(2026, 7)

names = load(HERE, "answer", "export_names")
assert names.export_file_name(2026, 7) == "export-2026-0007.csv"
assert names.archive_file_name(2026, 7) == names.export_file_name(2026, 7)
assert names.parse_export_file_name(names.export_file_name(2026, 7)) == (2026, 7)
assert names.parse_export_file_name("export-2026-7.csv") == (2026, 7)
assert names.parse_export_file_name("report.csv") is None
print("p03 ok")
