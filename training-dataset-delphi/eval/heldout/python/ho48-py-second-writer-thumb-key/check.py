import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "..", "tools"))
from pycheck import load  # noqa: E402

# the premise: the gallery writes what the reader refuses, the other writer what it reads
given = load(HERE, "given", "thumbs")
assert given.parse_thumb_key(given.gallery_thumb_key(1234, 320)) is None
assert given.parse_thumb_key(given.thumb_key(1234, 320)) == (1234, 320)

thumbs = load(HERE, "answer", "thumbs")
assert thumbs.thumb_key(1234, 320) == "thumb/1234/w320"
assert thumbs.gallery_thumb_key(1234, 320) == thumbs.thumb_key(1234, 320)
assert thumbs.parse_thumb_key(thumbs.gallery_thumb_key(1234, 320)) == (1234, 320)
# the reader stays strict
assert thumbs.parse_thumb_key("thumb/1234/320px") is None
assert thumbs.parse_thumb_key("thumb/x/w320") is None
assert thumbs.parse_thumb_key("thumbs/1234/w320") is None
print("ho48 ok")
