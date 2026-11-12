import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "tools"))
from pycheck import load  # noqa: E402

# What the answer claims: the first two tests pass on the CURRENT code, the third does not...
load(HERE, "given", "slugs")
tests = load(HERE, "answer", "test_slugs")
tests.test_article_url_keeps_working()
tests.test_tag_url_keeps_working()
try:
    tests.test_accents_become_plain_letters()
    raise SystemExit("p05: the new test already passes on the given code - it proves nothing")
except AssertionError:
    pass

# ...and all three pass after the change
load(HERE, "answer", "slugs")
tests = load(HERE, "answer", "test_slugs")
tests.test_article_url_keeps_working()
tests.test_tag_url_keeps_working()
tests.test_accents_become_plain_letters()
print("p05 ok")
