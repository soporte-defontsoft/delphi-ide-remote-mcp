---
id: ho42-py-reuse-slug
family: landscape
language: python
framework: none
teaches: look at what the module already has before writing; the URL form of a name is the slug function it has, not a second one
judge: python check.py (accents and punctuation as in the path of an article, and the article path as before); the answer calls slugify (must_contain)
must_contain: slugify(tag)
varies: p01-reuse-existing-helper l01-reuse-existing-helper l02-reuse-normalizer
---

## user
Add to this Python module a function `tag_path(tag)`: the path of a tag's page, `/tags/` followed by the tag as it goes in a URL, like `/tags/live-music`.

{{code:given/articles.py}}

## assistant
The module already turns a name into its URL form: `slugify` drops the accents, lowers the case and joins the words with `-`, and `article_path` uses it. `tag_path` calls it too. A second conversion written for tags (`tag.lower().replace(" ", "-")`) would keep the accents and the punctuation that the article paths drop, and the two kinds of path would disagree on the first tag with an accent.

{{code:answer/articles.py}}
