import csv
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "tools"))
from pycheck import load  # noqa: E402

fields = ["Smith, John", 'say "hi"', "42"]

# the premise: joined by hand, the fields do not come back
given = load(HERE, "given", "csv_lines")
assert next(csv.reader([given.to_csv_line(fields)])) != fields

lines = load(HERE, "answer", "csv_lines")
line = lines.to_csv_line(fields)
assert line == '"Smith, John","say ""hi""",42'
assert next(csv.reader([line])) == fields
print("p11 ok")
