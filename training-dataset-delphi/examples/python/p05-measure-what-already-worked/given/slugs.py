import re


def slugify(text: str) -> str:
    text = text.strip().lower()
    text = re.sub(r"[^a-z0-9]+", "-", text)
    return text.strip("-")


def article_url(title: str) -> str:
    return "/articles/" + slugify(title)


def tag_url(tag: str) -> str:
    return "/tags/" + slugify(tag)
