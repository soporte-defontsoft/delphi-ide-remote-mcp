from slugs import article_url, slugify, tag_url


# What already worked, pinned BEFORE the change: both callers of slugify
def test_article_url_keeps_working():
    assert article_url("Hello, World!") == "/articles/hello-world"


def test_tag_url_keeps_working():
    assert tag_url("  Delphi 13 ") == "/tags/delphi-13"


# The new rule
def test_accents_become_plain_letters():
    assert slugify("Café con leche") == "cafe-con-leche"
