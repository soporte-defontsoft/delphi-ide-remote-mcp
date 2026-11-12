import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "..", "tools"))
from pycheck import load  # noqa: E402

pages = load(HERE, "answer", "articles")
assert pages.tag_path("Live Music") == "/tags/live-music"
# accents and punctuation go as in the path of an article
assert pages.tag_path("Música en Vivo!") == "/tags/musica-en-vivo"
assert pages.tag_path("  C++ & Rust ") == "/tags/c-rust"
# what already worked
assert pages.article_path(2026, "Café con Leche!") == "/2026/cafe-con-leche"
print("ho42 ok")
