import re
import unicodedata


def slugify(text: str) -> str:
    # accented letters become their plain letter: "Café" -> "cafe"
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode("ascii")
    text = text.strip().lower()
    text = re.sub(r"[^a-z0-9]+", "-", text)
    return text.strip("-")


def article_url(title: str) -> str:
    return "/articles/" + slugify(title)


def tag_url(tag: str) -> str:
    return "/tags/" + slugify(tag)
