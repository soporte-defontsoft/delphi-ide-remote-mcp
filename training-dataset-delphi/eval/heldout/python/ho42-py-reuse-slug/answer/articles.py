"""Paths of the blog's pages."""
import re
import unicodedata


def slugify(title):
    """The URL form of a title: no accents, lower case, words joined by '-' ('Cafe con Leche!' -> 'cafe-con-leche')."""
    text = unicodedata.normalize("NFKD", title).encode("ascii", "ignore").decode("ascii")
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def article_path(year, title):
    """The path of an article: '/2026/cafe-con-leche'."""
    return f"/{year}/{slugify(title)}"


def tag_path(tag):
    """The path of a tag's page: '/tags/live-music'."""
    return f"/tags/{slugify(tag)}"
